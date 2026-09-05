<#
.SYNOPSIS
Run a set of agent sessions unattended: background sessions in their own git
worktrees, in parallel lanes, surviving usage limits, API outages and early stops.

.DESCRIPTION
A GENERAL, PORTABLE runner. Copy this folder into any git repository, run -Init,
edit the sessions, and go — nothing here is specific to the repository it came
from, and the session tool itself is a swappable adapter (see `launcher` in the
config), so it can drive agents other than Claude Code.

  -Init        scaffold a config for the repo you are standing in
  -Validate    check the config; report repo, branch, lanes, guards, launcher
  -EmitBriefs  render every brief as copy-pasteable markdown, launch nothing
  -DryRun      rehearse: preflight and lane dispatch, but no session is started
  -Cleanup     stop, remove and prune every MERGED session's background process,
               worktree, branch and Serena project row; launches nothing
  (no flag)    run it

While it runs, <stateDir>/queue is the operator's control surface: drop
lane-<name>.json ({"sessions": ["X"]}) to start another lane (the child re-reads
the config, so a session added to it after the start is launchable), or an empty
stop-<session key> file to stop that session's lane at its next decision point.
<stateDir>/load.json carries cpu_percent and the running sessions, refreshed
every poll, for briefs that defer heavy runs under a machine budget.

The repository is DETECTED (`git rev-parse --show-toplevel`), so a committed
config carries no machine-specific path and works for everyone who clones it.

For each session, in its lane:
  1. a worktree <worktreeParent>/<worktreePrefix>-<name> on branch
     <branchPrefix>/<name> is created from the CURRENT base branch (pruned
     first, so a deleted directory is recreated), with any `linkDirs` linked to
     the main checkout's copies (junction on Windows, symlink elsewhere);
  2. the session is started through the launcher adapter's `start` action with a
     self-contained brief on the model the config assigns, under a stable
     remote-control name so it stays listed and joinable. The runner polls the
     adapter's `list` action until the session leaves its working state, then
     reads its log: on a usage limit ("usage limit reached|<epoch>") it sleeps
     until that reset (else 30 min) and RESUMES the same session; on an API
     outage it waits 5 min and resumes; when the session stops without writing
     its DONE note it is resumed with a nudge, up to -MaxContinues times; a
     single turn running past -MaxSessionHours is stopped and resumed;
  3. the config's guard command runs in the worktree; if it passes and -NoMerge
     is not set, the branch is merged into the base branch (--no-ff, under a
     cross-process lock so lanes never merge at once); a red guard or a merge
     conflict stops THAT lane only.

State lives in <stateDir>/state.json (one entry per session: status, session id,
attempts, last error); a re-run skips sessions already merged and resumes ones
left running. Everything is logged to <stateDir>/runner.log.

-WaitUntil "yyyy-MM-dd HH:mm" sleeps before starting. -FollowUp
"yyyy-MM-dd HH:mm" additionally spawns a detached child that waits until then
and runs -FollowUpSessions fresh, so one invocation covers a night and a morning.

Keep the machine awake (no sleep/hibernate); the runner cannot change power
settings.

Permissions: an unattended session cannot answer prompts, so the config's
`allowedTools` are pre-allowed. Repository hooks still run on every call — the
hook, not the prompt, is the guard.

See SKILL.md for the model and adoption guide, and handoff.config.example.json
for every field annotated.

.EXAMPLE
pwsh -File run_handoff_sessions.ps1 -Init
pwsh -File run_handoff_sessions.ps1 -Validate
pwsh -File run_handoff_sessions.ps1 -EmitBriefs -OutFile briefs.md
pwsh -File run_handoff_sessions.ps1 -DryRun
pwsh -File run_handoff_sessions.ps1 -Sessions build
#>
param(
    [string]$Config = "",
    [string[]]$Sessions = @(),
    [string[]]$Lanes = @(),
    [switch]$NoMerge,
    [switch]$DryRun,
    [switch]$Fresh,
    [switch]$Validate,
    [switch]$EmitBriefs,
    [switch]$Init,
    [switch]$Force,
    [string]$OutFile = "",
    [string]$WaitUntil = "",
    [string]$FollowUp = "",
    [string[]]$FollowUpSessions = @(),
    [int]$MaxContinues = 0,
    [int]$MaxRetries = 0,
    [int]$MaxSessionHours = 0,
    [switch]$Cleanup,
    [string]$LaneName = ""
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "HandoffCore.psm1") -Force -DisableNameChecking

# --------------------------------------------------------------------------
# Config discovery: explicit -Config, else the conventional locations. Being
# able to run with no arguments from a configured repo is what makes this
# reusable rather than a script every repo re-parameterises by hand.
# --------------------------------------------------------------------------
$detectedRoot = Resolve-HandoffRepoRoot "."
$configCandidates = @(".claude/handoff.config.json", "handoff.config.json", ".handoff.json")

if ($Init) {
    # Scaffold a runnable config for whatever repository this was copied into.
    $target = if ($Config) { $Config } else { ".claude/handoff.config.json" }
    $base = if ($detectedRoot) {
        $b = (& git -C $detectedRoot rev-parse --abbrev-ref HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $b) { ([string]$b).Trim() } else { "main" }
    } else { "main" }
    $written = New-HandoffConfigScaffold -Path $target -RepoRoot $detectedRoot -BaseBranch $base -Force:$Force
    Write-Host "wrote $written (base branch: $base)"
    Write-Host "next: edit the sessions, then -Validate, then -EmitBriefs or -DryRun"
    exit 0
}

if (-not $Config) {
    foreach ($c in $configCandidates) { if (Test-Path $c) { $Config = $c; break } }
    # Also look beside the repo root, so the runner works from a subdirectory.
    if (-not $Config -and $detectedRoot) {
        foreach ($c in $configCandidates) {
            $p = Join-Path $detectedRoot $c
            if (Test-Path $p) { $Config = $p; break }
        }
    }
}
if (-not $Config) {
    throw "no config found ($($configCandidates -join ', ')). Create one with:  pwsh -File $PSCommandPath -Init"
}
# `repo` may be absent from the config on purpose; the detected root fills it in,
# which is what lets a committed config be shared between machines.
$cfg = Read-HandoffConfig $Config -DefaultRepo $detectedRoot
# Where this skill lives: briefs, guards and postWorktree may reference the
# bundled helpers as {{skillDir}} instead of a path that belongs to one repo.
$cfg["skillDir"] = $PSScriptRoot

# CLI overrides beat config; config beats the module defaults.
if ($MaxContinues -gt 0) { $cfg.maxContinues = $MaxContinues }
if ($MaxRetries -gt 0) { $cfg.maxRetries = $MaxRetries }
if ($MaxSessionHours -gt 0) { $cfg.maxSessionHours = $MaxSessionHours }

$repo = $cfg.repo
$stateDir = if ([System.IO.Path]::IsPathRooted($cfg.stateDir)) { $cfg.stateDir } else { Join-Path $repo $cfg.stateDir }
$stateFile = Join-Path $stateDir "state.json"
$runnerLog = Join-Path $stateDir "runner.log"
$queueDir = Join-Path $stateDir "queue"
$loadFile = Join-Path $stateDir "load.json"
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
New-Item -ItemType Directory -Force -Path $queueDir | Out-Null

function Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$LaneName] $msg"
    Write-Host $line
    Add-Content -Path $runnerLog -Value $line -Encoding utf8
}

function Invoke-WithLock([scriptblock]$body) {
    <#  Cross-process mutual exclusion, portably, RETURNING the body's value.

        Named mutexes are a Windows facility: `System.Threading.Mutex` with a name
        throws PlatformNotSupportedException on Linux and macOS, so a copied skill
        would die on its first state write. Elsewhere an exclusive lock file gives
        the same guarantee — two lanes never merge at once.

        It returns the value rather than letting callers assign inside the
        scriptblock, because a `$script:` assignment in there writes a DIFFERENT
        variable from the function-scoped one read afterwards: that bug reported
        every successful merge as a conflict and stopped its lane.  #>
    $isWin = (Get-HandoffLinkType) -eq "Junction"
    if ($isWin) {
        $m = New-Object System.Threading.Mutex($false, $cfg.mutexName)
        [void]$m.WaitOne()
        try { return (& $body) } finally { $m.ReleaseMutex(); $m.Dispose() }
    }
    $lockFile = Join-Path $stateDir "runner.lock"
    $fs = $null
    for ($i = 0; $i -lt 600 -and -not $fs; $i++) {
        try { $fs = [System.IO.File]::Open($lockFile, 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $fs) { throw "could not acquire the runner lock at $lockFile after 5 minutes" }
    try { return (& $body) } finally { $fs.Dispose() }
}

function Update-State([string]$key, [hashtable]$fields) {
    Invoke-WithLock {
        $state = Read-HandoffState $stateFile
        if (-not $state.ContainsKey($key)) { $state[$key] = @{} }
        foreach ($k in $fields.Keys) { $state[$key][$k] = $fields[$k] }
        $state[$key]["updated"] = (Get-Date -Format "s")
        Write-HandoffState $stateFile $state
    }
}

function Parse-Result([string]$path) {
    # The JSON result is the last {...} object in the file; anything before it is
    # stderr noise.
    $out = @{ is_error = $true; result = ""; session_id = $null }
    if (-not (Test-Path $path)) { $out.result = "no transcript written"; return $out }
    $text = Get-Content $path -Raw
    $start = $text.LastIndexOf("`n{")
    if ($start -lt 0) { $start = $text.IndexOf("{") } else { $start += 1 }
    if ($start -lt 0) { $out.result = $text; return $out }
    try {
        $obj = $text.Substring($start) | ConvertFrom-Json
        $out.is_error = [bool]$obj.is_error
        $out.result = [string]$obj.result
        $out.session_id = $obj.session_id
        if ($obj.subtype -and $obj.subtype -ne "success") {
            $out.is_error = $true
            if (-not $out.result) { $out.result = [string]$obj.subtype }
        }
    }
    catch { $out.result = $text }
    return $out
}

# Lanes run as child processes: PowerShell 7 when present, without the user's
# profile, whose PSReadLine setup errors out on a redirected console.
$shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }

function Ensure-Worktree([string]$wt, [string]$branch, [hashtable]$vars) {
    git -C $repo worktree prune 2>$null
    if (-not (Test-Path $wt)) {
        $exists = git -C $repo branch --list $branch
        if ($exists) { git -C $repo worktree add $wt $branch 2>&1 | Out-Null }
        else { git -C $repo worktree add $wt -b $branch $cfg.baseBranch 2>&1 | Out-Null }
        if ($LASTEXITCODE -ne 0) { throw "git worktree add failed for $wt" }
    }
    # Directories shared with the main checkout rather than copied — a generated
    # graph, a model cache. Junctions, so the worktree sees one artifact.
    foreach ($d in @($cfg.linkDirs)) {
        if (-not $d) { continue }
        $link = Join-Path $wt $d
        $target = Join-Path $repo $d
        if ((Test-Path $target) -and -not (Test-Path $link)) {
            New-Item -ItemType (Get-HandoffLinkType) -Path $link -Target $target -ErrorAction SilentlyContinue | Out-Null
        }
    }
    # Directories COPIED from the main checkout, so each worktree owns an
    # independent instance it may rebuild or append to without touching the
    # others' - a per-worktree code graph, a gitignored working ledger. Use
    # linkDirs for one shared artifact, copyDirs for one artifact per session.
    foreach ($d in @($cfg.copyDirs)) {
        if (-not $d) { continue }
        $dst = Join-Path $wt $d
        $src = Join-Path $repo $d
        if ((Test-Path $src) -and -not (Test-Path $dst)) {
            $parent = Split-Path $dst -Parent
            if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
            Copy-Item -Recurse -Force $src $dst
        }
    }
    # A brand-new worktree is an unapproved folder: the first session in it asks
    # to trust the directory and its hooks, and a BACKGROUND session cannot
    # answer — it goes `blocked` and stays there. Pre-approving it is what an
    # interactive session would have done once. The repo supplies the command.
    if ($cfg.postWorktree) {
        $cmd = Expand-HandoffTemplate ([string]$cfg.postWorktree) $vars
        $out = & $shell -NoProfile -Command $cmd 2>&1 | Out-String
        Log "postWorktree: $(($out -replace '\s+', ' ').Trim())"
    }
}

function Invoke-Launcher([string]$action, [hashtable]$vars) {
    # Every call to the session tool goes through the adapter, so a repository can
    # drive a different agent by replacing config rather than editing this script.
    $argv = Build-HandoffLaunchArgs $cfg $action $vars
    return (& $cfg.launcher.command @argv 2>&1 | Out-String)
}

function Start-Bg([string]$wt, [string]$action, [hashtable]$vars, [string]$log) {
    # `claude --bg` returns at once and prints the short id that `claude agents`,
    # `attach`, `logs` and `stop` take. Background sessions are listed in the
    # agents view, so the operator can follow and even join them — which a `-p`
    # print session does not allow.
    Push-Location $wt
    try {
        $out = Invoke-Launcher $action $vars
        $out | Out-File -Encoding utf8 $log
    }
    finally { Pop-Location }
    if ($out -match $cfg.launcher.idPattern) { return $Matches[1] }
    Log "could not read a background id from: $(($out -replace '\s+', ' ').Trim())"
    return $null
}

function Get-BgEntry([string]$id) {
    try {
        $arr = (Invoke-Launcher "list" @{} | ConvertFrom-Json)
        return ($arr | Where-Object { $_.id -eq $id } | Select-Object -First 1)
    }
    catch { return $null }
}

function Write-Load {
    # <stateDir>/load.json: the one number briefs can read before a heavy run.
    try {
        $cpu = $null
        if ((Get-HandoffLinkType) -eq "Junction") {
            $cpu = [double](Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        }
        elseif (Test-Path "/proc/loadavg") {
            $la = [double](((Get-Content /proc/loadavg -Raw) -split " ")[0])
            $cpu = [math]::Round(100.0 * $la / [math]::Max(1, [Environment]::ProcessorCount), 1)
        }
        $st = Read-HandoffState $stateFile
        $running = @()
        foreach ($k in @($st.Keys)) { $e = $st[$k]; if ($e -is [hashtable] -and $e.ContainsKey("status") -and $e["status"] -eq "running") { $running += $k } }
        @{ updated = (Get-Date -Format "s"); cpu_percent = $cpu; running_sessions = $running; lane = $LaneName } |
            ConvertTo-Json -Depth 4 | Set-Content -Path $loadFile -Encoding utf8
    }
    catch { }
}

function Remove-Worktree([string]$wt, [string]$branch) {
    if (Test-Path $wt) { git -C $repo worktree remove --force $wt 2>&1 | Out-Null }
    git -C $repo worktree prune 2>$null
    if (git -C $repo branch --list $branch) { git -C $repo branch -d $branch 2>&1 | Out-Null }
    Remove-SerenaProjectRow $wt
}

function Remove-SerenaProjectRow([string]$wt) {
    # Serena appends a `projects:` row per activated worktree and never removes
    # one; a page of dead rows is what every unattended day used to leave.
    $home = if ($env:SERENA_HOME) { $env:SERENA_HOME } else { Join-Path $HOME ".serena" }
    $cfgPath = Join-Path $home "serena_config.yml"
    if (-not (Test-Path $cfgPath)) { return }
    try {
        $lines = Get-Content $cfgPath
        $a = $wt.Replace('/', '\'); $b = $wt.Replace('\', '/')
        $kept = @($lines | Where-Object { ($_.Trim() -ne "- $a") -and ($_.Trim() -ne "- $b") })
        if ($kept.Count -ne $lines.Count) {
            Copy-Item $cfgPath "$cfgPath.bak-$(Get-Date -Format 'yyyyMMdd')" -ErrorAction SilentlyContinue
            $kept | Set-Content $cfgPath -Encoding utf8
            Log "pruned the Serena project row for $wt"
        }
    }
    catch { Log "could not prune the Serena project row for ${wt}: $($_.Exception.Message)" }
}

function Test-DoneQuiet([string]$wt, [string]$doneNotePath) {
    # The DONE note exists, the branch is clean, and nothing was committed for
    # quietMinutes: the session is finished whatever the agents view says.
    if (-not $doneNotePath -or -not (Test-Path $doneNotePath)) { return $false }
    $last = Get-HandoffText (git -C $wt log -1 --format=%ct 2>$null)
    $epoch = 0; if ($last) { $epoch = [long]$last }
    $dirty = [bool](git -C $wt status --porcelain 2>$null)
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    return (Test-HandoffDoneQuiet $true $epoch $now ([int]$cfg.quietMinutes) $dirty)
}

function Wait-Bg([string]$id, [datetime]$deadline, [string]$wt = "", [string]$doneNotePath = "") {
    # "working" while the session is in a turn; anything else (idle, done, gone)
    # means the turn ended and the runner may look at what it produced. A
    # session that wrote its DONE note and went quiet is finished even if the
    # agents view still says "working" (measured: three hours of that, twice).
    $missing = 0
    while ((Get-Date) -lt $deadline) {
        Write-Load
        if ($wt -and (Test-DoneQuiet $wt $doneNotePath)) { return "done-note" }
        $e = Get-BgEntry $id
        if (-not $e) {
            $missing++
            # Two consecutive absences, so ONE failed `claude agents` call is not
            # read as a finished session.
            if ($missing -ge 2) { return "gone" }
        }
        else {
            $missing = 0
            if ($e.state -and $e.state -ne $cfg.launcher.workingState) { return [string]$e.state }
        }
        Start-Sleep -Seconds $cfg.pollSeconds
    }
    return "timeout"
}

function Run-Session([string]$s, [bool]$isFollowUpRun) {
    # NOT named $followUp: PowerShell variable names are case-insensitive, so a
    # local $followUp IS the [string]$FollowUp parameter, and assigning a bool to
    # it silently became the string "False" — which then failed to bind here.
    $info = $cfg.sessions[$s]
    # Vars and brief come from HandoffCore, the same path -EmitBriefs uses, so a
    # brief pasted by hand is byte-identical to the one the runner launches.
    $vars = Get-HandoffSessionVars $cfg $s $isFollowUpRun
    $wt = $vars["worktree"]; $branch = $vars["branch"]; $key = $vars["key"]

    $state = Read-HandoffState $stateFile
    if ($state.ContainsKey($key) -and $state[$key]["status"] -eq "merged" -and -not $Fresh) {
        Log "session $key already merged; skipping"; return $true
    }
    Log "=== session $key ($($info.name)) on $branch in $wt, model $($info.model)"
    # Cross-lane dependencies: wait until every listed session has merged, so
    # the worktree cut below forks from a base branch that already carries
    # their work. A dependency that ends without merging stops this lane.
    $deps = @($info["dependsOn"])
    if ($deps.Count) {
        if ($DryRun) { Log "dry run: $key would wait for $($deps -join ', ') to merge" }
        else {
            $depDeadline = (Get-Date).AddHours($cfg.maxDependencyHours)
            $announced = $false
            while ($true) {
                $ds = Get-HandoffDependencyState (Read-HandoffState $stateFile) $deps
                if ($ds.ready) { break }
                if (@($ds.failed).Count) {
                    Log "$key cannot start: dependency $(@($ds.failed) -join ', ') ended without merging"
                    Update-State $key @{ status = "dependency-failed"; last_error = "dependency failed: $(@($ds.failed) -join ', ')" }
                    return $false
                }
                if (-not $announced) {
                    Log "$key waiting for $(@($ds.waiting) -join ', ') to merge"
                    Update-State $key @{ status = "waiting"; waiting_for = (@($ds.waiting) -join ",") }
                    $announced = $true
                }
                if ((Get-Date) -gt $depDeadline) {
                    Log "$key gave up waiting for $(@($ds.waiting) -join ', ') after $($cfg.maxDependencyHours) h"
                    Update-State $key @{ status = "dependency-timeout" }; return $false
                }
                Start-Sleep -Seconds $cfg.pollSeconds
            }
            Log "$key dependencies merged: $($deps -join ', ')"
        }
    }
    # Operator control: an empty stop-<key> file in the queue directory ends
    # this lane before the session starts.
    if (Test-Path (Join-Path $queueDir "stop-$key")) {
        Log "$key stopped by the operator's stop marker before starting"
        Update-State $key @{ status = "stopped-by-operator" }; return $false
    }
    # Merged elsewhere - by hand, or by another runner over the same state: an
    # existing branch whose tip is already an ancestor of the base branch and
    # is not simply equal to it (a freshly cut branch is an ancestor too).
    if (-not $Fresh -and -not $DryRun) {
        $tipB = Get-HandoffText (git -C $repo rev-parse --verify --quiet $branch 2>$null)
        $tipBase = Get-HandoffText (git -C $repo rev-parse --verify --quiet $cfg.baseBranch 2>$null)
        if ($tipB -and $tipBase -and $tipB -ne $tipBase) {
            git -C $repo merge-base --is-ancestor $branch $cfg.baseBranch 2>$null
            if ($LASTEXITCODE -eq 0) {
                Log "$key ($branch) is already merged into $($cfg.baseBranch); skipping"
                Update-State $key @{ status = "merged"; finished_by = "merged-elsewhere"; merged_into = $tipBase }
                return $true
            }
        }
    }
    # Resource exclusion: never start while a RUNNING session holds a
    # conflicting resource (write excludes all; read excludes write).
    $wanted = @($info["resources"])
    if ($wanted.Count) {
        if ($DryRun) { Log "dry run: $key would hold $($wanted -join ', ') and wait for any running holder" }
        else {
            $announced = $false
            while ($true) {
                $st = Read-HandoffState $stateFile
                $held = @()
                foreach ($k in @($st.Keys)) {
                    if ($k -eq $key) { continue }
                    $e = $st[$k]
                    if ($e -is [hashtable] -and $e.ContainsKey("status") -and $e["status"] -eq "running" -and $e.ContainsKey("resources")) {
                        $held += , @{ key = $k; resources = @($e["resources"]) }
                    }
                }
                $c = @(Test-HandoffResourceConflict $held $wanted)
                if (-not $c.Count) { break }
                if (-not $announced) {
                    Log "$key waiting for resources held by $($c -join ', ') (wants $($wanted -join ', '))"
                    Update-State $key @{ status = "waiting-resource"; waiting_for = ($c -join ",") }
                    $announced = $true
                }
                Start-Sleep -Seconds $cfg.pollSeconds
            }
        }
    }
    if ($DryRun) {
        if ($info["guardsOnly"]) { Log "dry run: $key is guards-only; would cut $wt at $($cfg.baseBranch) and run the guards there" }
        Log "dry run: would create $wt and run claude there"; return $true
    }

    Ensure-Worktree $wt $branch $vars
    Update-State $key @{ status = "running"; worktree = $wt; branch = $branch; model = $info.model; resources = @($info["resources"]) }

    if ($info["guardsOnly"]) {
        # No agent: the pinned, idle final suite on a worktree at the merged HEAD.
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $guard = Build-HandoffGuardCommand $cfg $vars
        if (-not $guard) { Log "$key is guards-only but no guards are configured; nothing to do"; Update-State $key @{ status = "guards-green" }; return $true }
        $guardLog = Join-Path $stateDir "session-$key-$stamp-guards.txt"
        Log "$key is guards-only: running the guards on $wt (cut at $($cfg.baseBranch)'s HEAD), no agent launched"
        Push-Location $wt
        try { & $guard.command @($guard.args) 2>&1 | Out-File -Encoding utf8 $guardLog; $green = ($LASTEXITCODE -eq 0) }
        finally { Pop-Location }
        $baseSha = Get-HandoffText (git -C $repo rev-parse HEAD 2>$null)
        Log "guards $(if ($green) { 'GREEN' } else { 'RED' }) at $baseSha`: $guardLog"
        Update-State $key @{ status = $(if ($green) { "guards-green" } else { "guards-red" }); guard_log = $guardLog; base_sha = $baseSha }
        return $green
    }

    $doneNote = Join-Path $wt $vars["doneNote"]
    $sessionId = $null
    if (-not $Fresh -and $state.ContainsKey($key) -and $state[$key]["session_id"]) { $sessionId = $state[$key]["session_id"] }
    $continues = 0; $retries = 0
    $brief = Build-HandoffBrief $cfg $s $vars
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"

    while ($true) {
        if (Test-Path (Join-Path $queueDir "stop-$key")) {
            # The operator says this session is done: never resume it again.
            if (Test-Path $doneNote) { Log "$key has the operator's stop marker and a DONE note; proceeding to the guards"; break }
            Log "$key stopped by the operator's stop marker; lane stops"
            Update-State $key @{ status = "stopped-by-operator" }; return $false
        }
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $log = Join-Path $stateDir "session-$key-$stamp.log"
        # ARGUMENT ORDER MATTERS: `--allowedTools <tools...>` is variadic and
        # swallows everything up to the next flag, so a prompt placed after it
        # becomes another "tool name" and the session starts with NO task. The
        # tool list therefore comes first and the prompt last, after a flag that
        # takes exactly one value.
        if ($sessionId) {
            $action = "resume"
            $lvars = @{
                sessionId = $sessionId; model = $info.model; rcName = $vars["rcName"]
                prompt    = "Continue from where you stopped; nothing you committed is lost. If the DONE note is not written yet, keep working until it is, then stop."
            }
            Log "resuming $key (session $sessionId)"
        }
        else {
            $action = "start"
            # The remote-control name gives the session a stable handle an operator
            # can join from anywhere, so an unattended run stays interactive on
            # demand rather than being a black box until morning.
            $lvars = @{ rcName = $vars["rcName"]; model = $info.model; prompt = $brief }
            Log "starting $key as a background session named $($vars['rcName'])"
        }
        $bgId = Start-Bg $wt $action $lvars $log
        if (-not $bgId) {
            $retries++
            $f = Classify-HandoffFailure (Get-Content $log -Raw)
            Update-State $key @{ last_error = "could not start a background session"; retries = $retries; failure_kind = $f.kind }
            if ($f.kind -eq "auth") {
                Log "AUTHENTICATION FAILED for $key — run 'claude login', then re-run this script"
                Update-State $key @{ status = "auth-failed" }; return $false
            }
            if ($retries -gt $cfg.maxRetries) { Log "giving up on $key after $retries retries"; Update-State $key @{ status = "failed" }; return $false }
            Start-Sleep -Seconds ([math]::Max(60, $f.wait)); continue
        }
        $entry = Get-BgEntry $bgId
        if ($entry -and $entry.sessionId) { $sessionId = [string]$entry.sessionId }
        Update-State $key @{ bg_id = $bgId; session_id = $sessionId; attach = "claude attach $bgId" }
        Log "$key is background session $bgId (join it: $($cfg.launcher.command) attach $bgId)"

        $ended = Wait-Bg $bgId (Get-Date).AddHours($cfg.maxSessionHours) $wt $doneNote
        if ($ended -eq "done-note" -or ($ended -eq "timeout" -and (Test-Path $doneNote))) {
            # Finished on the evidence that matters: the DONE note is there and
            # the branch has been quiet. Never resume a finished session.
            Log "$key finished by DONE note ($ended); stopping session $bgId and proceeding to the guards"
            Update-State $key @{ finished_by = $ended }
            Invoke-Launcher "stop" @{ id = $bgId } | Out-Null
            break
        }
        $text = try { Invoke-Launcher "logs" @{ id = $bgId } } catch { "" }
        $text | Out-File -Append -Encoding utf8 $log
        $tail = $text.Substring([math]::Max(0, $text.Length - 4000))
        Log "$key turn ended ($ended)"

        if (Test-HandoffPermissionPrompt $tail) {
            Log "BLOCKED: $key is waiting for a permission answer a background session cannot give."
            Log "  Read it with 'claude attach $bgId'; the last lines are in $log"
            Update-State $key @{ status = "blocked"; last_error = "permission prompt"; bg_id = $bgId }
            return $false
        }
        $f = Classify-HandoffFailure $tail
        if ($f.kind -ne "other" -or $ended -eq "timeout") {
            $retries++
            Update-State $key @{ last_error = $f.kind; retries = $retries; failure_kind = $f.kind }
            if ($f.kind -eq "auth") {
                Log "AUTHENTICATION FAILED for $key — run 'claude login', then re-run; nothing is lost"
                Update-State $key @{ status = "auth-failed" }; return $false
            }
            if ($retries -gt $cfg.maxRetries) { Log "giving up on $key after $retries retries"; Update-State $key @{ status = "failed" }; return $false }
            # A turn has ended, so exactly one live session per handoff is kept:
            # the finished one is stopped before any resume, otherwise every
            # retry would leave another background session holding the same
            # conversation.
            Invoke-Launcher "stop" @{ id = $bgId } | Out-Null
            if ($ended -eq "timeout") { Log "$key ran past $($cfg.maxSessionHours) h in one turn; stopped it, resuming" }
            else { Log "$($f.kind) failure; waiting $([int]($f.wait/60)) min before resuming"; Start-Sleep -Seconds $f.wait }
            continue
        }
        if ($vars["doneNote"] -and (Test-Path $doneNote)) { Log "DONE note present for $key"; Update-State $key @{ finished_by = "turn-end" }; break }
        if (-not $vars["doneNote"]) { Log "no doneNote configured; treating a clean stop as done"; break }

        $continues++
        Update-State $key @{ continues = $continues }
        if ($continues -gt $cfg.maxContinues) { Log "$key stopped $continues times without a DONE note; proceeding to the guards anyway"; break }
        Log "$key stopped without its DONE note; stopping session $bgId and resuming in 2 min ($continues/$($cfg.maxContinues))"
        Invoke-Launcher "stop" @{ id = $bgId } | Out-Null
        Start-Sleep -Seconds 120
    }

    $guard = Build-HandoffGuardCommand $cfg $vars
    if ($guard) {
        $guardLog = Join-Path $stateDir "session-$key-$stamp-guards.txt"
        Push-Location $wt
        try {
            # Redirected to a file, never piped through grep/tail: a piped
            # long-running command buffers, and a traceback is lost.
            & $guard.command @($guard.args) 2>&1 | Out-File -Encoding utf8 $guardLog
            $green = ($LASTEXITCODE -eq 0)
        }
        finally { Pop-Location }
        Log "guards $(if ($green) { 'GREEN' } else { 'RED' }): $guardLog"
        if (-not $green) { Update-State $key @{ status = "guards-red" }; Log "lane stops: $branch is red; read the guard log and the DONE note"; return $false }
    }
    else { Log "no guards configured; skipping straight to the merge decision" }

    if ($NoMerge -or $cfg.ContainsKey("noMerge") -and $cfg.noMerge) {
        Update-State $key @{ status = "done-unmerged" }; Log "no-merge: $branch left for review"; return $true
    }
    # The result is taken from Invoke-WithLock's RETURN VALUE, never assigned to
    # an outer variable inside the scriptblock: such an assignment writes a
    # DIFFERENT variable from the one read afterwards, and that bug reported every
    # successful merge as a conflict and stopped its lane.
    $merged = Invoke-WithLock {
        git -C $repo merge --no-ff $branch -m "merge $branch (session $key, unattended run $stamp)" 2>&1 | Out-File -Append -Encoding utf8 $runnerLog
        $ok = ($LASTEXITCODE -eq 0)
        if (-not $ok) { git -C $repo merge --abort 2>$null }
        $ok
    }
    if (-not $merged) { Update-State $key @{ status = "merge-conflict" }; Log "lane stops: merging $branch into $($cfg.baseBranch) conflicted; resolve by hand"; return $false }
    $mergedSha = Get-HandoffText (git -C $repo rev-parse HEAD 2>$null)
    $refusals = 0
    if (Test-Path $doneNote) { $refusals = Get-HandoffRefusalCount (Get-Content $doneNote -Raw) }
    Update-State $key @{ status = "merged"; merged_into = $mergedSha; refusals = $refusals }
    Log "merged $branch into $($cfg.baseBranch) ($mergedSha)"
    # The session is done and its process still holds the worktree folder;
    # stopping it is what lets the operator remove the worktree later.
    if ($cfg.stopAfterMerge -and $bgId) { Invoke-Launcher "stop" @{ id = $bgId } | Out-Null; Log "stopped finished session $bgId" }
    if ($cfg.removeWorktreeAfterMerge) { Remove-Worktree $wt $branch; Log "removed worktree $wt and branch $branch" }
    return $true
}

function Preflight {
    $problems = @()
    if (-not (Get-Command $cfg.launcher.command -ErrorAction SilentlyContinue)) { $problems += "launcher '$($cfg.launcher.command)' not on PATH" }
    elseif (-not $DryRun) {
        # A one-word headless call: the cheapest proof that the CLI's own login
        # is alive. An expired OAuth session fails every session instantly,
        # which is not something to discover at 03:00.
        $probe = Join-Path $stateDir "preflight-auth.json"
        Push-Location $repo
        try { Invoke-Launcher "probe" @{ prompt = "Reply with exactly the word OK."; probeModel = $cfg.launcher.probeModel } | Out-File -Encoding utf8 $probe }
        finally { Pop-Location }
        $r = Parse-Result $probe
        if ($r.is_error) { $problems += "launcher probe failed: $($r.result) - check the agent is authenticated (e.g. 'claude login')" }
        else { Log "preflight: launcher answered (session $($r.session_id))" }
    }
    if (-not (Test-Path $repo)) { $problems += "repo does not exist: $repo" }
    foreach ($p in @($cfg.requirePaths)) {
        if (-not $p) { continue }
        $full = if ([System.IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $repo $p }
        if (-not (Test-Path $full)) { $problems += "required path missing: $full" }
    }
    $branch = git -C $repo rev-parse --abbrev-ref HEAD
    if ($branch -ne $cfg.baseBranch) { $problems += "main checkout is on '$branch', not $($cfg.baseBranch)" }
    if (git -C $repo status --porcelain) { Log "warning: the main checkout has uncommitted changes; sessions fork from $($cfg.baseBranch)'s HEAD, not from them" }
    # Secrets stay in the main checkout and are passed to children as env, never
    # copied into a worktree.
    $localSettings = Join-Path $repo $cfg.envFrom
    if (Test-Path $localSettings) {
        $local = Get-Content $localSettings -Raw | ConvertFrom-Json
        if ($local.PSObject.Properties.Name -contains "env" -and $local.env) {
            foreach ($p in $local.env.PSObject.Properties) { Set-Item -Path "env:$($p.Name)" -Value $p.Value }
        }
    }
    if ($problems) { throw ("preflight failed: " + ($problems -join "; ")) }
}

# ---------------------------------------------------------------------------
if ($Validate) {
    Write-Host "config OK: $($cfg.configPath)"
    Write-Host "  repo:      $repo"
    Write-Host "  base:      $($cfg.baseBranch)   branches: $($cfg.branchPrefix)/<name>"
    Write-Host "  worktrees: $($cfg.worktreeParent)\$($cfg.worktreePrefix)-<name>"
    Write-Host "  sessions:  $(($cfg.sessions.Keys | Sort-Object) -join ', ')"
    Write-Host "  lanes:     $(($cfg.lanes | ForEach-Object { $_ -join ',' }) -join '  |  ')"
    foreach ($k in ($cfg.sessions.Keys | Sort-Object)) {
        $dd = @($cfg.sessions[$k]["dependsOn"])
        if ($dd.Count) { Write-Host "  dependsOn: $k waits for $($dd -join ', ')" }
        $rr = @($cfg.sessions[$k]["resources"])
        if ($rr.Count) { Write-Host "  resources: $k holds $($rr -join ', ')" }
        if ($cfg.sessions[$k]["guardsOnly"]) { Write-Host "  guardsOnly: $k launches no agent" }
    }
    Write-Host "  queue:     $queueDir   load: $loadFile"
    Write-Host "  guards:    $(if (Build-HandoffGuardCommand $cfg @{}) { 'configured' } else { 'none' })"
    Write-Host "  subagents: $(if (Build-HandoffSubagentPolicy $cfg) { 'policy configured' } else { 'none' })"
    # Surfaced because a repo driving a different agent has no other way to
    # confirm the swap took before committing a night to it.
    $onPath = if (Get-Command $cfg.launcher.command -ErrorAction SilentlyContinue) { "on PATH" } else { "NOT ON PATH" }
    Write-Host "  launcher:  $($cfg.launcher.command) ($onPath)"
    exit 0
}

if ($Cleanup) {
    # Everything a finished day leaves behind: the done sessions' processes
    # (still holding their worktree folders), the worktrees, the branches, the
    # Serena rows. Only MERGED sessions are touched; a lane left for review keeps
    # its worktree.
    $state = Read-HandoffState $stateFile
    foreach ($k in @($state.Keys | Sort-Object)) {
        $e = $state[$k]
        if ($e -isnot [hashtable] -or -not $e.ContainsKey("status") -or $e["status"] -ne "merged") { continue }
        if ($e.ContainsKey("bg_id") -and $e["bg_id"]) { try { Invoke-Launcher "stop" @{ id = $e["bg_id"] } | Out-Null } catch { } }
        $wt = if ($e.ContainsKey("worktree")) { [string]$e["worktree"] } else { "" }
        $br = if ($e.ContainsKey("branch")) { [string]$e["branch"] } else { "" }
        if ($wt -and $br) { Remove-Worktree $wt $br; Log "cleanup: $k - removed $wt and $br" }
        Update-State $k @{ cleaned = (Get-Date -Format "s") }
    }
    Log "cleanup finished"
    exit 0
}

if ($EmitBriefs) {
    # Render every brief WITHOUT launching anything, so one config serves both an
    # unattended run and a human pasting each brief into an interactive session.
    # Same code path as a real launch — a copy-pasted brief that differs from the
    # launched one is worse than no brief at all.
    $md = Export-HandoffBriefs $cfg
    if ($OutFile) {
        $dir = Split-Path $OutFile -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $md | Set-Content -Path $OutFile -Encoding utf8
        Write-Host "wrote $((($md -split "`n").Count)) lines to $OutFile"
    }
    else { Write-Output $md }
    exit 0
}

if ($WaitUntil) {
    # Quotes survive Start-Process (it joins the argument array with spaces and
    # does not quote), and an unparseable value must not kill the runner: a
    # follow-up run was once scheduled twice and never ran, because
    # `-WaitUntil 2026-09-04 09:45` arrived as two arguments and ParseExact threw
    # under ErrorActionPreference Stop.
    $waitAt = $null
    try { $waitAt = [datetime]::ParseExact($WaitUntil.Trim('"', " "), "yyyy-MM-dd HH:mm", $null) }
    catch { Log "could not parse -WaitUntil '$WaitUntil' (expected 'yyyy-MM-dd HH:mm'); starting now instead" }
    if ($waitAt) {
        $delay = ($waitAt - (Get-Date)).TotalSeconds
        if ($delay -gt 0) { Log "waiting until $($waitAt.ToString('yyyy-MM-dd HH:mm')) ($([int]($delay/60)) min)"; Start-Sleep -Seconds ([int]$delay) }
    }
}

Preflight

# -Sessions collapses everything to one lane; -Lanes overrides the config's.
# Built with an explicit loop and `+= ,`: assigning an if/else EXPRESSION to a
# variable sends its value through the output stream, which unrolls one array
# level — so a single lane of ["X","Y"] arrived here as two lanes of one, and
# every sequential lane silently ran in parallel.
$runLanes = @()
if ($Sessions.Count -gt 0) {
    $runLanes += , @($Sessions | ForEach-Object { $_ -split "," } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
elseif ($Lanes.Count -gt 0) {
    foreach ($l in $Lanes) { $runLanes += , @($l -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
}
else {
    foreach ($l in $cfg.lanes) { $runLanes += , @($l) }
}

if ($FollowUp) {
    $fus = if ($FollowUpSessions.Count) { $FollowUpSessions } else { @($runLanes[0][0]) }
    $childArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath,
        "-Config", $cfg.configPath, "-Sessions", ($fus -join ","), "-Fresh",
        "-WaitUntil", $FollowUp, "-LaneName", "followup")
    if ($NoMerge) { $childArgs += "-NoMerge" }
    Start-Process -FilePath $shell -ArgumentList $childArgs -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $stateDir "lane-followup.out.log") `
        -RedirectStandardError (Join-Path $stateDir "lane-followup.err.log") | Out-Null
    Log "follow-up run of $($fus -join ',') scheduled for $FollowUp (lane-followup.out.log)"
}

if ($runLanes.Count -le 1) {
    if (-not $LaneName) { $LaneName = ($runLanes[0] -join ",") }
    $isFollowUpRun = [bool]$Fresh -and [bool]$WaitUntil
    foreach ($s in $runLanes[0]) {
        if (-not $cfg.sessions.ContainsKey($s)) { Log "unknown session '$s'; skipping"; continue }
        try {
            if (-not (Run-Session $s $isFollowUpRun)) { Log "lane [$LaneName] stopped at session $s"; break }
        }
        catch {
            Log "lane [$LaneName] crashed at session ${s}: $($_.Exception.Message)"
            Update-State $s @{ status = "crashed"; last_error = $_.Exception.Message }
            break
        }
    }
    Log "lane [$LaneName] finished"
}
else {
    # Each lane in its own process so the sessions run concurrently; this script
    # re-invokes itself with -Sessions for one lane at a time.
    $procs = @(); $n = 0
    foreach ($lane in $runLanes) {
        $n++
        # One comma-joined value: passed as separate tokens, PowerShell binds
        # only the first to -Sessions and the lane silently shrinks to one
        # session.
        $childArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath,
            "-Config", $cfg.configPath, "-Sessions", ($lane -join ","), "-LaneName", "lane$n")
        if ($NoMerge) { $childArgs += "-NoMerge" }
        if ($DryRun) { $childArgs += "-DryRun" }
        if ($Fresh) { $childArgs += "-Fresh" }
        Log "lane [$($lane -join ',')] starting as lane$n"
        $procs += Start-Process -FilePath $shell -ArgumentList $childArgs -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $stateDir "lane$n.out.log") `
            -RedirectStandardError (Join-Path $stateDir "lane$n.err.log")
        Start-Sleep -Seconds 30
    }
    # While lanes run, the queue directory is the operator's way in: a
    # lane-<name>.json ({"sessions": ["F9"]}) starts another lane child, which
    # re-reads the config - so a session added to the config after this runner
    # started is launchable without a second runner over the same state file.
    while ($true) {
        foreach ($qf in @(Get-ChildItem $queueDir -Filter "lane-*.json" -ErrorAction SilentlyContinue)) {
            try {
                $spec = ConvertTo-HandoffHash (Get-Content $qf.FullName -Raw | ConvertFrom-Json)
                $sessions = @(@($spec["sessions"]) | Where-Object { $_ })
                if (-not $sessions.Count) { throw "no sessions listed" }
                $n++
                $childArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath,
                    "-Config", $cfg.configPath, "-Sessions", ($sessions -join ","), "-LaneName", "lane$n")
                if ($NoMerge) { $childArgs += "-NoMerge" }
                Log "lane [$($sessions -join ',')] queued by the operator ($($qf.Name)); starting as lane$n"
                $procs += Start-Process -FilePath $shell -ArgumentList $childArgs -PassThru -WindowStyle Hidden `
                    -RedirectStandardOutput (Join-Path $stateDir "lane$n.out.log") `
                    -RedirectStandardError (Join-Path $stateDir "lane$n.err.log")
                Move-Item -Force $qf.FullName ($qf.FullName -replace '\.json$', '.started')
            }
            catch {
                Log "queue file $($qf.Name) ignored: $($_.Exception.Message)"
                Move-Item -Force $qf.FullName ($qf.FullName -replace '\.json$', '.rejected') -ErrorAction SilentlyContinue
            }
        }
        $alive = @($procs | Where-Object { $_ -and -not $_.HasExited })
        if (-not $alive.Count) { break }
        Start-Sleep -Seconds $cfg.pollSeconds
    }
    Log "all lanes finished; state: $stateFile"
}

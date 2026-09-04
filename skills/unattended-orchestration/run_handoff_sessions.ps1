<#
.SYNOPSIS
Run a set of Claude Code session handoffs unattended and overnight: headless
background sessions in their own git worktrees, in parallel lanes, surviving the
usage limit, API outages and early stops.

.DESCRIPTION
Generalised from basic-analysis/scripts/management/run_handoff_sessions.ps1
(2026-09-04). Everything repository-specific now lives in a JSON config; this
script contains only the orchestration. See SKILL.md for the model and
handoff.config.example.json for an annotated config.

For each session, in its lane:
  1. a worktree <worktreeParent>/<worktreePrefix>-<name> on branch
     <branchPrefix>/<name> is created from the CURRENT base branch (pruned
     first, so a deleted directory is recreated), with any `linkDirs` junctioned
     to the main checkout's copies;
  2. the session starts as a BACKGROUND session (`claude --bg --remote-control
     <name>`) with a self-contained brief on the model the config assigns, so it
     is listed in the agents view and can be followed live — `claude attach <id>`
     joins it, `claude logs <id>` prints its output. The runner polls
     `claude agents --json` until the session leaves the "working" state, then
     reads its log: on a usage limit ("usage limit reached|<epoch>") it sleeps
     until that reset (else 30 min) and RESUMES the same session; on an API
     outage it waits 5 min and resumes; when the session stops without writing
     its DONE note it is resumed with a nudge, up to -MaxContinues times; a
     single turn running past -MaxSessionHours is stopped and resumed;
  3. the config's guard command runs in the worktree; if it passes and -NoMerge
     is not set, the branch is merged into the base branch (--no-ff, under a
     global mutex so lanes never merge at once); a red guard or a merge conflict
     stops THAT lane only.

State lives in <stateDir>/state.json (one entry per session: status, session id,
attempts, last error); a re-run skips sessions already merged and resumes ones
left running. Everything is logged to <stateDir>/runner.log.

-WaitUntil "yyyy-MM-dd HH:mm" sleeps before starting. -FollowUp
"yyyy-MM-dd HH:mm" additionally spawns a detached child that waits until then
and runs -FollowUpSessions fresh, so one invocation covers a night and a morning.

Keep the machine awake (no sleep/hibernate); the runner cannot change power
settings.

Permissions: headless mode cannot answer prompts, so the config's `allowedTools`
are pre-allowed. Repository hooks still run on every call — the hook, not the
prompt, is the guard.

.EXAMPLE
pwsh -File run_handoff_sessions.ps1 -Config .claude/handoff.config.json -Validate
pwsh -File run_handoff_sessions.ps1 -Config .claude/handoff.config.json -DryRun
pwsh -File run_handoff_sessions.ps1 -Config .claude/handoff.config.json -Sessions E
pwsh -File run_handoff_sessions.ps1 -Config .claude/handoff.config.json -FollowUp "2026-09-05 09:45" -FollowUpSessions E
#>
param(
    [string]$Config = "",
    [string[]]$Sessions = @(),
    [string[]]$Lanes = @(),
    [switch]$NoMerge,
    [switch]$DryRun,
    [switch]$Fresh,
    [switch]$Validate,
    [string]$WaitUntil = "",
    [string]$FollowUp = "",
    [string[]]$FollowUpSessions = @(),
    [int]$MaxContinues = 0,
    [int]$MaxRetries = 0,
    [int]$MaxSessionHours = 0,
    [string]$LaneName = ""
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "HandoffCore.psm1") -Force -DisableNameChecking

# --------------------------------------------------------------------------
# Config discovery: explicit -Config, else the conventional locations. Being
# able to run with no arguments from a configured repo is what makes this
# reusable rather than a script every repo re-parameterises by hand.
# --------------------------------------------------------------------------
if (-not $Config) {
    foreach ($c in @(".claude/handoff.config.json", "handoff.config.json", ".handoff.json")) {
        if (Test-Path $c) { $Config = $c; break }
    }
}
if (-not $Config) { throw "no config given and none found at .claude/handoff.config.json, handoff.config.json or .handoff.json" }
$cfg = Read-HandoffConfig $Config

# CLI overrides beat config; config beats the module defaults.
if ($MaxContinues -gt 0) { $cfg.maxContinues = $MaxContinues }
if ($MaxRetries -gt 0) { $cfg.maxRetries = $MaxRetries }
if ($MaxSessionHours -gt 0) { $cfg.maxSessionHours = $MaxSessionHours }

$repo = $cfg.repo
$stateDir = if ([System.IO.Path]::IsPathRooted($cfg.stateDir)) { $cfg.stateDir } else { Join-Path $repo $cfg.stateDir }
$stateFile = Join-Path $stateDir "state.json"
$runnerLog = Join-Path $stateDir "runner.log"
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

function Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$LaneName] $msg"
    Write-Host $line
    Add-Content -Path $runnerLog -Value $line -Encoding utf8
}

function With-Mutex([scriptblock]$body) {
    $m = New-Object System.Threading.Mutex($false, $cfg.mutexName)
    [void]$m.WaitOne()
    try { & $body } finally { $m.ReleaseMutex(); $m.Dispose() }
}

function Update-State([string]$key, [hashtable]$fields) {
    With-Mutex {
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

function Get-SessionVars([string]$s, [hashtable]$info, [string]$wt, [string]$branch, [string]$key) {
    $vars = @{
        session = $s; key = $key; sessionName = $info.name; model = $info.model
        worktree = $wt; branch = $branch; repo = $repo; baseBranch = $cfg.baseBranch
        stateDir = $stateDir
    }
    # Free-form passthrough so a repo can hand its brief an interpreter path, a
    # plan directory, anything — without this script knowing what those are.
    if ($cfg.ContainsKey("vars") -and $cfg.vars) {
        foreach ($k in $cfg.vars.Keys) { $vars[$k] = Expand-HandoffTemplate ([string]$cfg.vars[$k]) $vars }
    }
    $vars["planDir"] = if ($vars.ContainsKey("planDir")) { $vars["planDir"] } else { "" }
    $vars["doneNote"] = Expand-HandoffTemplate ([string]$cfg.doneNote) $vars
    return $vars
}

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
            New-Item -ItemType Junction -Path $link -Target $target -ErrorAction SilentlyContinue | Out-Null
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

function Build-Brief([hashtable]$info, [hashtable]$vars) {
    $body = Resolve-HandoffBrief $cfg $info
    $vars = $vars.Clone()
    $vars["brief"] = Expand-HandoffTemplate $body $vars
    if ($cfg.ContainsKey("briefTemplate") -and $cfg.briefTemplate) {
        $tpl = if ($cfg.ContainsKey("briefTemplateFile") -and $cfg.briefTemplateFile) {
            Get-Content (Join-Path $repo $cfg.briefTemplateFile) -Raw
        } else { [string]$cfg.briefTemplate }
        return Expand-HandoffTemplate $tpl $vars
    }
    return $vars["brief"]
}

function Start-Bg([string]$wt, [string[]]$argv, [string]$log) {
    # `claude --bg` returns at once and prints the short id that `claude agents`,
    # `attach`, `logs` and `stop` take. Background sessions are listed in the
    # agents view, so the operator can follow and even join them — which a `-p`
    # print session does not allow.
    Push-Location $wt
    try {
        $out = (& claude @argv 2>&1 | Out-String)
        $out | Out-File -Encoding utf8 $log
    }
    finally { Pop-Location }
    if ($out -match "backgrounded[^\r\n]*?([0-9a-f]{8})") { return $Matches[1] }
    Log "could not read a background id from: $(($out -replace '\s+', ' ').Trim())"
    return $null
}

function Get-BgEntry([string]$id) {
    try {
        $arr = (& claude agents --json 2>$null | Out-String | ConvertFrom-Json)
        return ($arr | Where-Object { $_.id -eq $id } | Select-Object -First 1)
    }
    catch { return $null }
}

function Wait-Bg([string]$id, [datetime]$deadline) {
    # "working" while the session is in a turn; anything else (idle, done, gone)
    # means the turn ended and the runner may look at what it produced.
    $missing = 0
    while ((Get-Date) -lt $deadline) {
        $e = Get-BgEntry $id
        if (-not $e) {
            $missing++
            # Two consecutive absences, so ONE failed `claude agents` call is not
            # read as a finished session.
            if ($missing -ge 2) { return "gone" }
        }
        else {
            $missing = 0
            if ($e.state -and $e.state -ne "working") { return [string]$e.state }
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
    $wt = Join-Path $cfg.worktreeParent "$($cfg.worktreePrefix)-$($info.name)"
    $branch = "$($cfg.branchPrefix)/$($info.name)"
    $key = if ($isFollowUpRun) { "$s-followup" } else { $s }
    $vars = Get-SessionVars $s $info $wt $branch $key

    $state = Read-HandoffState $stateFile
    if ($state.ContainsKey($key) -and $state[$key]["status"] -eq "merged" -and -not $Fresh) {
        Log "session $key already merged; skipping"; return $true
    }
    Log "=== session $key ($($info.name)) on $branch in $wt, model $($info.model)"
    if ($DryRun) { Log "dry run: would create $wt and run claude there"; return $true }

    Ensure-Worktree $wt $branch $vars
    Update-State $key @{ status = "running"; worktree = $wt; branch = $branch; model = $info.model }

    $doneNote = Join-Path $wt $vars["doneNote"]
    $sessionId = $null
    if (-not $Fresh -and $state.ContainsKey($key) -and $state[$key]["session_id"]) { $sessionId = $state[$key]["session_id"] }
    $continues = 0; $retries = 0
    $brief = Build-Brief $info $vars
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"

    while ($true) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $log = Join-Path $stateDir "session-$key-$stamp.log"
        # ARGUMENT ORDER MATTERS: `--allowedTools <tools...>` is variadic and
        # swallows everything up to the next flag, so a prompt placed after it
        # becomes another "tool name" and the session starts with NO task. The
        # tool list therefore comes first and the prompt last, after a flag that
        # takes exactly one value.
        $common = @("--allowedTools") + @($cfg.allowedTools) + @("--permission-mode", $cfg.permissionMode)
        if ($sessionId) {
            $argv = @("--bg", "--resume", $sessionId) + $common + @(
                "Continue the handoff from where you stopped; nothing you committed is lost. If the DONE note is not written yet, keep working until it is, then stop.")
            Log "resuming $key (claude session $sessionId)"
        }
        else {
            $argv = @("--bg", "--remote-control", "handoff-$key") + $common + @("--model", $info.model, $brief)
            Log "starting $key as a background session named handoff-$key"
        }
        $bgId = Start-Bg $wt $argv $log
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
        Log "$key is background session $bgId (follow it: 'claude attach $bgId', 'claude logs $bgId')"

        $ended = Wait-Bg $bgId (Get-Date).AddHours($cfg.maxSessionHours)
        $text = try { (& claude logs $bgId 2>&1 | Out-String) } catch { "" }
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
            & claude stop $bgId 2>&1 | Out-Null
            if ($ended -eq "timeout") { Log "$key ran past $($cfg.maxSessionHours) h in one turn; stopped it, resuming" }
            else { Log "$($f.kind) failure; waiting $([int]($f.wait/60)) min before resuming"; Start-Sleep -Seconds $f.wait }
            continue
        }
        if ($vars["doneNote"] -and (Test-Path $doneNote)) { Log "DONE note present for $key"; break }
        if (-not $vars["doneNote"]) { Log "no doneNote configured; treating a clean stop as done"; break }

        $continues++
        Update-State $key @{ continues = $continues }
        if ($continues -gt $cfg.maxContinues) { Log "$key stopped $continues times without a DONE note; proceeding to the guards anyway"; break }
        Log "$key stopped without its DONE note; stopping session $bgId and resuming in 2 min ($continues/$($cfg.maxContinues))"
        & claude stop $bgId 2>&1 | Out-Null
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
    # The mutex is inlined rather than taken through With-Mutex: a `$script:`
    # assignment inside that scriptblock writes a DIFFERENT variable from the
    # function-scoped one read afterwards, so every successful merge would have
    # been reported as a conflict and stopped its lane.
    $merged = $false
    $m = New-Object System.Threading.Mutex($false, $cfg.mutexName)
    [void]$m.WaitOne()
    try {
        git -C $repo merge --no-ff $branch -m "merge $branch (session $key, unattended run $stamp)" 2>&1 | Out-File -Append -Encoding utf8 $runnerLog
        $merged = ($LASTEXITCODE -eq 0)
        if (-not $merged) { git -C $repo merge --abort 2>$null }
    }
    finally { $m.ReleaseMutex(); $m.Dispose() }
    if (-not $merged) { Update-State $key @{ status = "merge-conflict" }; Log "lane stops: merging $branch into $($cfg.baseBranch) conflicted; resolve by hand"; return $false }
    Update-State $key @{ status = "merged" }
    Log "merged $branch into $($cfg.baseBranch)"
    return $true
}

function Preflight {
    $problems = @()
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { $problems += "claude CLI not on PATH" }
    elseif (-not $DryRun) {
        # A one-word headless call: the cheapest proof that the CLI's own login
        # is alive. An expired OAuth session fails every session instantly,
        # which is not something to discover at 03:00.
        $probe = Join-Path $stateDir "preflight-auth.json"
        Push-Location $repo
        try { & claude -p "Reply with exactly the word OK." --model sonnet --output-format json 2>&1 | Out-File -Encoding utf8 $probe }
        finally { Pop-Location }
        $r = Parse-Result $probe
        if ($r.is_error) { $problems += "claude headless call failed: $($r.result) — run 'claude login' in a terminal first" }
        else { Log "preflight: headless claude answered (session $($r.session_id))" }
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
    Write-Host "  guards:    $(if (Build-HandoffGuardCommand $cfg @{}) { 'configured' } else { 'none' })"
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
    $procs | Wait-Process
    Log "all lanes finished; state: $stateFile"
}

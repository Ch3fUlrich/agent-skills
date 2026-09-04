<#
HandoffCore — the pure, testable half of the unattended session runner.

Everything here is a function of its arguments: no git, no `claude`, no clock
beyond the one the caller supplies. That split exists so the parts that decide
*what to do on failure* can be tested without an overnight run — the runner's
recovery logic used to be reachable only by actually hitting a usage limit at
03:00, which is not a place to discover a bad regex.

The impure half (worktrees, background sessions, merges) lives in
run_handoff_sessions.ps1. See SKILL.md for the model and the config contract.
#>

Set-StrictMode -Version Latest

# --------------------------------------------------------------------------
# Defaults. Anything a repository is likely to share sits here; anything a
# repository must decide for itself is validated as required in Read-HandoffConfig.
# --------------------------------------------------------------------------
$script:HandoffDefaults = @{
    baseBranch     = "main"
    branchPrefix   = "handoff"
    stateDir       = "output/sessions"
    permissionMode = "auto"
    maxContinues   = 8
    maxRetries     = 40
    maxSessionHours = 6
    pollSeconds    = 30
    linkDirs       = @()
    allowedTools   = @("Bash", "Edit", "Write", "Read", "Glob", "Grep", "Agent", "ToolSearch", "Skill")
    guards         = $null
    postWorktree   = $null
    envFrom        = ".claude/settings.local.json"
    doneNote       = "{{planDir}}/session-{{session}}-DONE.md"
}

function ConvertTo-HandoffHash {
    <#  PSCustomObject -> nested hashtable, arrays preserved.

        Windows PowerShell 5.1's ConvertFrom-Json has no -AsHashtable, and a
        state file the runner cannot read back loses every session id — and with
        it every resume. Converting explicitly keeps 5.1 and 7 on one path.  #>
    param($obj)
    if ($null -eq $obj) { return $null }
    if ($obj -is [hashtable]) { return $obj }
    if ($obj -is [string]) { return $obj }
    if ($obj -is [System.Collections.IEnumerable] -and $obj -isnot [string]) {
        # foreach + Add, never `| ForEach-Object`: the pipeline UNROLLS a nested
        # array, so [["E","A"],["D","B"]] came back as ["E","A","D","B"] and every
        # multi-session lane silently became one lane per session — turning
        # "run E then A in sequence" into "run E and A at once", which is the
        # exact store contention lanes exist to prevent.
        # The leading comma on the return is the other half: without it, a
        # single-lane array is unrolled away by the output stream.
        $list = New-Object System.Collections.ArrayList
        foreach ($item in $obj) { [void]$list.Add((ConvertTo-HandoffHash $item)) }
        return , $list.ToArray()
    }
    if ($obj -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-HandoffHash $p.Value }
        return $h
    }
    return $obj
}

function Expand-HandoffTemplate {
    <#  Replace {{key}} with $vars[key], in ONE pass.

        Single-pass matters twice: a value that itself contains braces must not
        be re-expanded, and an unknown placeholder must survive verbatim rather
        than collapse to "". An emptied placeholder produces a brief that reads
        fine and silently omits the task.  #>
    param([string]$Template, [hashtable]$Vars)
    if (-not $Template) { return $Template }
    $evaluator = {
        param($m)
        $key = $m.Groups[1].Value
        if ($Vars -and $Vars.ContainsKey($key)) { return [string]$Vars[$key] }
        return $m.Value
    }
    return [regex]::Replace($Template, '\{\{(\w+)\}\}', $evaluator)
}

function Classify-HandoffFailure {
    <#  -> @{ kind = "auth"|"limit"|"transient"|"other"; wait = seconds }

        Order is load-bearing. Auth is tested first because it is the one kind
        that cannot be waited out: an expired OAuth session fails every launch
        instantly, and retrying it burns the whole night. Everything else is a
        wait, and the epoch form of the usage limit is preferred over the flat
        30 minutes because Claude tells you exactly when it resets.  #>
    param([string]$Text)
    $t = if ($Text) { $Text.ToLower() } else { "" }

    if ($t -match "failed to authenticate|oauth|not logged in|please run /login|claude login|invalid api key|authentication") {
        return @{ kind = "auth"; wait = 0 }
    }
    if ($t -match "usage limit reached\|(\d{9,11})") {
        $reset = [DateTimeOffset]::FromUnixTimeSeconds([long]$Matches[1]).LocalDateTime
        $wait = [int]([math]::Max(60, ($reset - (Get-Date)).TotalSeconds + 90))
        return @{ kind = "limit"; wait = [int][math]::Min($wait, 6 * 3600) }
    }
    if ($t -match "usage limit|rate limit|limit reached|too many requests|429") {
        return @{ kind = "limit"; wait = 1800 }
    }
    if ($t -match "overloaded|529|500 internal|internal server error|econnreset|etimedout|enotfound|socket hang up|fetch failed|network|timed out|503|502") {
        return @{ kind = "transient"; wait = 300 }
    }
    return @{ kind = "other"; wait = 120 }
}

function Test-HandoffPermissionPrompt {
    <#  A background session cannot answer a prompt; it sits `blocked` forever.
        Detecting it turns a silent all-night stall into a state the operator
        can see in the state file the next morning.  #>
    param([string]$Text)
    if (-not $Text) { return $false }
    return [bool]($Text -match "(?i)do you want to proceed|do you trust|allow this|\[y/n\]|permission required")
}

function Read-HandoffState {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @{} }
    try {
        $h = ConvertTo-HandoffHash (Get-Content $Path -Raw | ConvertFrom-Json)
        if ($h -is [hashtable]) { return $h }
        return @{}
    }
    catch { return @{} }   # a corrupt state file must not stop the run; it restarts from scratch
}

function Write-HandoffState {
    param([string]$Path, [hashtable]$State)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $State | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding utf8
}

function Resolve-HandoffBrief {
    <#  A session's brief is either inline (`brief`) or a file (`briefFile`,
        relative to the config's briefRoot, else the repo). Inline wins.  #>
    param([hashtable]$Config, [hashtable]$Session)
    if ($Session.ContainsKey("brief") -and $Session["brief"]) { return [string]$Session["brief"] }
    if ($Session.ContainsKey("briefFile") -and $Session["briefFile"]) {
        $root = if ($Config.ContainsKey("briefRoot") -and $Config["briefRoot"]) { $Config["briefRoot"] } else { $Config["repo"] }
        $p = if ([System.IO.Path]::IsPathRooted($Session["briefFile"])) { $Session["briefFile"] } else { Join-Path $root $Session["briefFile"] }
        if (-not (Test-Path $p)) { throw "briefFile not found: $p" }
        return (Get-Content $p -Raw)
    }
    throw "session has neither 'brief' nor 'briefFile'"
}

function Build-HandoffGuardCommand {
    <#  -> @{ command; args } or $null when the repo declares no guards.

        Guards are deliberately OPT-IN and fully generic: pytest, npm test,
        cargo, a shell script. The previous runner hardcoded a pytest invocation
        and a venv path, which is exactly the part no other repository can use.
        `{{guards}}` in args expands in place to the `paths` list.  #>
    param([hashtable]$Config, [hashtable]$Vars)
    if (-not $Config.ContainsKey("guards") -or -not $Config["guards"]) { return $null }
    $g = $Config["guards"]
    if (-not $g.ContainsKey("command") -or -not $g["command"]) { throw "guards.command is required when guards are declared" }
    $paths = if ($g.ContainsKey("paths") -and $g["paths"]) { @($g["paths"]) } else { @() }
    $argv = @()
    foreach ($a in @($g["args"])) {
        if ($null -eq $a) { continue }
        if ([string]$a -eq "{{guards}}") { $argv += $paths; continue }
        $argv += (Expand-HandoffTemplate ([string]$a) $Vars)
    }
    return @{ command = (Expand-HandoffTemplate ([string]$g["command"]) $Vars); args = $argv }
}

function Read-HandoffConfig {
    <#  Load, default and VALIDATE the config. Validation is not politeness: a
        lane naming a session that does not exist used to fail at 03:00, four
        hours into the run, as an unhandled throw inside a detached child whose
        stdout nobody was reading.  #>
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "handoff config not found: $Path" }
    try { $raw = ConvertTo-HandoffHash (Get-Content $Path -Raw | ConvertFrom-Json) }
    catch { throw "handoff config is not valid JSON: $Path — $($_.Exception.Message)" }
    if ($raw -isnot [hashtable]) { throw "handoff config must be a JSON object: $Path" }

    $cfg = @{}
    foreach ($k in $script:HandoffDefaults.Keys) { $cfg[$k] = $script:HandoffDefaults[$k] }
    foreach ($k in $raw.Keys) { $cfg[$k] = $raw[$k] }

    if (-not $cfg.ContainsKey("repo") -or -not $cfg["repo"]) { throw "config must set 'repo' (absolute path to the main checkout)" }
    $cfg["configPath"] = (Resolve-Path $Path).Path

    if (-not $cfg.ContainsKey("sessions") -or -not $cfg["sessions"] -or $cfg["sessions"].Keys.Count -eq 0) {
        throw "config must define at least one entry under 'sessions'"
    }
    foreach ($key in @($cfg["sessions"].Keys)) {
        $s = $cfg["sessions"][$key]
        if ($s -isnot [hashtable]) { throw "session '$key' must be an object" }
        if (-not $s.ContainsKey("model") -or -not $s["model"]) { throw "session '$key' must set 'model'" }
        if (-not $s.ContainsKey("name") -or -not $s["name"]) { $s["name"] = $key.ToLower() }
        if (-not ($s.ContainsKey("brief") -and $s["brief"]) -and -not ($s.ContainsKey("briefFile") -and $s["briefFile"])) {
            throw "session '$key' must set either 'brief' or 'briefFile'"
        }
    }

    # Lanes default to one session per lane: maximum parallelism, which is the
    # right default only because a repo that needs ordering will say so.
    if (-not $cfg.ContainsKey("lanes") -or -not $cfg["lanes"] -or @($cfg["lanes"]).Count -eq 0) {
        $cfg["lanes"] = @(@($cfg["sessions"].Keys | Sort-Object) | ForEach-Object { , @($_) })
    }
    $lanes = @()
    foreach ($lane in @($cfg["lanes"])) {
        $items = if ($lane -is [string]) { $lane -split "," } else { @($lane) }
        $clean = @()
        foreach ($i in $items) {
            $n = ([string]$i).Trim()
            if (-not $n) { continue }
            if (-not $cfg["sessions"].ContainsKey($n)) {
                throw "lane references unknown session '$n' (known: $(($cfg['sessions'].Keys | Sort-Object) -join ', '))"
            }
            $clean += $n
        }
        if ($clean.Count) { $lanes += , $clean }
    }
    if (-not $lanes.Count) { throw "config resolved to zero runnable lanes" }
    $cfg["lanes"] = $lanes

    # Derived defaults that need `repo` to exist first.
    if (-not $cfg.ContainsKey("worktreeParent") -or -not $cfg["worktreeParent"]) {
        $cfg["worktreeParent"] = (Split-Path $cfg["repo"] -Parent)
    }
    if (-not $cfg.ContainsKey("worktreePrefix") -or -not $cfg["worktreePrefix"]) {
        $cfg["worktreePrefix"] = (Split-Path $cfg["repo"] -Leaf)
    }
    if (-not $cfg.ContainsKey("mutexName") -or -not $cfg["mutexName"]) {
        $cfg["mutexName"] = "Global\handoff-$($cfg['worktreePrefix'])"
    }
    return $cfg
}

Export-ModuleMember -Function ConvertTo-HandoffHash, Expand-HandoffTemplate, Classify-HandoffFailure,
Test-HandoffPermissionPrompt, Read-HandoffState, Write-HandoffState, Resolve-HandoffBrief,
Build-HandoffGuardCommand, Read-HandoffConfig

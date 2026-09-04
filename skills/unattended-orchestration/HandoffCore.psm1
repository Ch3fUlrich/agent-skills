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

    # The session tool, as a swappable ADAPTER rather than a hardcoded binary.
    # Defaults describe Claude Code, so a copied skill works unedited; a repo
    # driving a different agent replaces only the keys it needs.
    #
    # {{tools}}  expands IN PLACE to: <allowedToolsFlag> <allowedTools...> <permissionModeFlag> <permissionMode>
    # {{prompt}} is substituted as exactly ONE argument, never re-expanded and never split.
    #
    # ORDER IS LOAD-BEARING in `start`: --allowedTools is variadic and swallows
    # everything up to the next flag, so a prompt placed after it becomes another
    # "tool name" and the session starts with NO task. {{tools}} therefore comes
    # first and {{prompt}} last, after a flag that takes exactly one value.
    launcher       = @{
        command            = "claude"
        start              = @("--bg", "--remote-control", "{{rcName}}", "{{tools}}", "--model", "{{model}}", "{{prompt}}")
        resume             = @("--bg", "--resume", "{{sessionId}}", "{{tools}}", "{{prompt}}")
        list               = @("agents", "--json")
        logs               = @("logs", "{{id}}")
        stop               = @("stop", "{{id}}")
        probe              = @("-p", "{{prompt}}", "--model", "{{probeModel}}", "--output-format", "json")
        allowedToolsFlag   = "--allowedTools"
        permissionModeFlag = "--permission-mode"
        idPattern          = "backgrounded[^\r\n]*?([0-9a-f]{8})"
        workingState       = "working"
        probeModel         = "sonnet"
    }
}

function Get-HandoffLinkType {
    <#  Junction on Windows, SymbolicLink everywhere else.

        `New-Item -ItemType Junction` simply does not exist off Windows, and the
        shared-artifact feature (linkDirs) is the only thing standing between a
        worktree and a regenerated multi-hundred-MB graph. Note $IsWindows is
        undefined on Windows PowerShell 5.1, where absence itself means Windows. #>
    $isWin = $true
    $v = Get-Variable -Name IsWindows -ErrorAction SilentlyContinue
    if ($v) { $isWin = [bool]$v.Value }
    if ($isWin) { return "Junction" } else { return "SymbolicLink" }
}

function Resolve-HandoffRepoRoot {
    <#  The git top-level containing $Path, or $null.

        This is what lets the skill be COPIED into an unknown repository and run
        there: the config need not name the checkout, so it carries no absolute
        path belonging to whoever generated it.  #>
    param([string]$Path = ".")
    $p = if (Test-Path $Path) { (Resolve-Path $Path).Path } else { $Path }
    $out = & git -C $p rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) {
        return ([string]$out).Trim().Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    }
    return $null
}

function Build-HandoffLaunchArgs {
    <#  Render one launcher action's argument vector.

        Kept pure and separate from the runner so the argument ORDER — the part
        that silently produces a session with no task when it is wrong — is
        covered by assertions rather than by an overnight run.  #>
    param([hashtable]$Config, [string]$Action, [hashtable]$Vars)
    $l = $Config["launcher"]
    if (-not $l -or -not $l.ContainsKey($Action) -or -not $l[$Action]) {
        $known = if ($l) { ($l.Keys | Where-Object { $l[$_] -is [array] } | Sort-Object) -join ", " } else { "none" }
        throw "launcher defines no '$Action' action (defined: $known)"
    }
    $argv = @()
    foreach ($a in @($l[$Action])) {
        if ($null -eq $a) { continue }
        $s = [string]$a
        if ($s -eq "{{tools}}") {
            $tools = @($Config["allowedTools"]) | Where-Object { $_ }
            if ($tools.Count -and $l.ContainsKey("allowedToolsFlag") -and $l["allowedToolsFlag"]) {
                $argv += $l["allowedToolsFlag"]; $argv += $tools
            }
            if ($Config["permissionMode"] -and $l.ContainsKey("permissionModeFlag") -and $l["permissionModeFlag"]) {
                $argv += $l["permissionModeFlag"]; $argv += [string]$Config["permissionMode"]
            }
            continue
        }
        if ($s -eq "{{prompt}}") {
            # Appended raw: expanding it could re-substitute braces the brief
            # legitimately contains, and it must stay ONE argument.
            $argv += [string]$Vars["prompt"]
            continue
        }
        $argv += (Expand-HandoffTemplate $s $Vars)
    }
    return , $argv
}

function New-HandoffConfigScaffold {
    <#  Write a minimal, runnable config for the repository it is invoked in.

        Deliberately omits `repo`: the runner detects it, so the generated file
        contains no path belonging to the machine that generated it and can be
        committed and shared unchanged.  #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$RepoRoot,
        [string]$BaseBranch = "main",
        [switch]$Force
    )
    if ((Test-Path $Path) -and -not $Force) {
        throw "a handoff config already exists at $Path — pass -Force to overwrite it"
    }
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    $scaffold = [ordered]@{
        '$comment'     = @(
            "Generated by run_handoff_sessions.ps1 -Init. Edit the sessions, then:",
            "  -Validate    check it     -EmitBriefs  read the briefs",
            "  -DryRun      rehearse it  (no flag)    run it",
            "",
            "'repo' is intentionally absent: the runner detects the git root, so this",
            "file carries no machine-specific path and can be committed as-is.",
            "NO SECRETS HERE - tokens are read from envFrom at preflight."
        )
        baseBranch     = $BaseBranch
        branchPrefix   = "handoff"
        stateDir       = "output/sessions"
        subagents      = [ordered]@{
            maxConcurrent = 2
            tiers         = [ordered]@{ mechanical = "sonnet"; judgement = "opus" }
            leafRule      = $true
        }
        sessions       = [ordered]@{
            example = [ordered]@{
                name  = "example"
                model = "sonnet"
                brief = "Replace this with the actual task. State what done means, concretely enough that another agent could check it."
            }
        }
        briefTemplate  = "You are session {{session}} ({{sessionName}}). Your working directory is {{worktree}}, a git worktree on branch {{branch}}; the main checkout is {{repo}} and you never edit it.`n`n{{brief}}`n`n{{subagentPolicy}}`n`nCommit small and often on {{branch}}, staging explicit paths only; never merge into {{baseBranch}} yourself. If a permission prompt blocks a command, record it and carry on with everything that does not depend on it. When done, write {{doneNote}} saying what landed, what remains and what blocked you, commit it, and stop."
        doneNote       = "{{stateDir}}/DONE-{{session}}.md"
        allowedTools   = @("Bash", "Edit", "Write", "Read", "Glob", "Grep", "Agent", "ToolSearch", "Skill")
        permissionMode = "auto"
    }
    ($scaffold | ConvertTo-Json -Depth 8) | Set-Content -Path $Path -Encoding utf8
    return $Path
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

function Build-HandoffSubagentPolicy {
    <#  The paragraph that tells a session HOW to use subagents, rendered from
        config so the policy is stated once and reaches every brief identically.

        Opt-in: with no `subagents` block this returns "" and briefs say nothing
        about subagents, because a session told to delegate with no cap and no
        tier assignment delegates badly. The leaf rule (subagents do not spawn
        subagents) mirrors `swarm-orchestration`; without it a wave of agents
        fans out geometrically and the budget is gone before the work is.  #>
    param([hashtable]$Config)
    if (-not $Config.ContainsKey("subagents") -or -not $Config["subagents"]) { return "" }
    $s = $Config["subagents"]
    $cap = if ($s.ContainsKey("maxConcurrent") -and $s["maxConcurrent"]) { [int]$s["maxConcurrent"] } else { 2 }
    $tiers = if ($s.ContainsKey("tiers") -and $s["tiers"]) { $s["tiers"] } else { @{} }
    $mech = if ($tiers.ContainsKey("mechanical")) { $tiers["mechanical"] } else { "sonnet" }
    $judge = if ($tiers.ContainsKey("judgement")) { $tiers["judgement"] } else { "opus" }
    $parts = @(
        "Orchestrate this work with subagents rather than doing it all in your own context:",
        "spawn $mech subagents for mechanical, closed-file work (mechanical edits, test scaffolding,",
        "renames, doc sweeps) and $judge subagents for judgement (design calls, ambiguous",
        "requirements, review), at most $cap at a time."
    )
    if (-not $s.ContainsKey("leafRule") -or $s["leafRule"]) {
        $parts += "Subagents are leaves: they do NOT spawn further subagents."
    }
    $parts += "Give each one a self-contained task and an explicit return contract; never delegate a vague task."
    return ($parts -join " ")
}

function Get-HandoffSessionVars {
    <#  Every placeholder a brief, guard or hook can reference, for one session.
        Pure so that -EmitBriefs renders exactly what a real run would launch —
        a copy-pasted brief that differs from the launched one is worse than no
        brief at all.  #>
    param([hashtable]$Config, [string]$SessionKey, [bool]$IsFollowUp = $false)
    if (-not $Config["sessions"].ContainsKey($SessionKey)) { throw "unknown session '$SessionKey'" }
    $info = $Config["sessions"][$SessionKey]
    $key = if ($IsFollowUp) { "$SessionKey-followup" } else { $SessionKey }
    $stateDir = if ([System.IO.Path]::IsPathRooted($Config["stateDir"])) { $Config["stateDir"] }
                else { Join-Path $Config["repo"] $Config["stateDir"] }

    $vars = @{
        session        = $SessionKey
        key            = $key
        sessionName    = $info["name"]
        model          = $info["model"]
        worktree       = (Join-Path $Config["worktreeParent"] "$($Config['worktreePrefix'])-$($info['name'])")
        branch         = "$($Config['branchPrefix'])/$($info['name'])"
        repo           = $Config["repo"]
        baseBranch     = $Config["baseBranch"]
        worktreePrefix = $Config["worktreePrefix"]
        stateDir       = $stateDir
        rcName         = "handoff-$key"
        planDir        = ""
    }
    # Config passthrough may reference the built-ins above, so it is expanded after them.
    if ($Config.ContainsKey("vars") -and $Config["vars"]) {
        foreach ($k in $Config["vars"].Keys) { $vars[$k] = Expand-HandoffTemplate ([string]$Config["vars"][$k]) $vars }
    }
    $vars["subagentPolicy"] = Build-HandoffSubagentPolicy $Config
    $vars["doneNote"] = Expand-HandoffTemplate ([string]$Config["doneNote"]) $vars
    return $vars
}

function Build-HandoffBrief {
    <#  Session body (inline or file) expanded, then wrapped in the shared
        briefTemplate. The template is the DRY seam: rules every session obeys
        are written once, and each session file carries only its own task.  #>
    param([hashtable]$Config, [string]$SessionKey, [hashtable]$Vars)
    $info = $Config["sessions"][$SessionKey]
    $v = $Vars.Clone()
    $v["brief"] = Expand-HandoffTemplate (Resolve-HandoffBrief $Config $info) $v
    if ($Config.ContainsKey("briefTemplate") -and $Config["briefTemplate"]) {
        $tpl = if ($Config.ContainsKey("briefTemplateFile") -and $Config["briefTemplateFile"]) {
            Get-Content (Join-Path $Config["repo"] $Config["briefTemplateFile"]) -Raw
        } else { [string]$Config["briefTemplate"] }
        return Expand-HandoffTemplate $tpl $v
    }
    return $v["brief"]
}

function Export-HandoffBriefs {
    <#  Render every session as copy-pasteable markdown, in lane order, WITHOUT
        launching anything.

        This is what makes one config serve two workflows: an unattended run, and
        a human pasting each brief into an interactive session by hand. Because
        both go through Build-HandoffBrief, the pasted text is byte-identical to
        what the runner would have launched.  #>
    param([hashtable]$Config)
    $out = New-Object System.Text.StringBuilder
    [void]$out.AppendLine("# Handoff briefs — $($Config['worktreePrefix'])")
    [void]$out.AppendLine()
    [void]$out.AppendLine("Generated from ``$($Config['configPath'])``. Lanes run in parallel; sessions inside a lane run in sequence.")
    [void]$out.AppendLine()
    $laneNo = 0
    foreach ($lane in $Config["lanes"]) {
        $laneNo++
        [void]$out.AppendLine("## Lane $laneNo — $($lane -join ' then ')")
        [void]$out.AppendLine()
        foreach ($s in $lane) {
            $v = Get-HandoffSessionVars $Config $s $false
            $brief = Build-HandoffBrief $Config $s $v
            [void]$out.AppendLine("### Session $s — $($v['sessionName'])")
            [void]$out.AppendLine()
            [void]$out.AppendLine("| | |")
            [void]$out.AppendLine("|---|---|")
            [void]$out.AppendLine("| Model | ``$($v['model'])`` |")
            [void]$out.AppendLine("| Branch | ``$($v['branch'])`` |")
            [void]$out.AppendLine("| Worktree | ``$($v['worktree'])`` |")
            [void]$out.AppendLine("| Remote control | ``$($v['rcName'])`` — join with ``claude attach $($v['rcName'])`` |")
            if ($v["doneNote"]) { [void]$out.AppendLine("| Done note | ``$($v['doneNote'])`` |") }
            [void]$out.AppendLine()
            [void]$out.AppendLine('```text')
            [void]$out.AppendLine($brief.Trim())
            [void]$out.AppendLine('```')
            [void]$out.AppendLine()
        }
    }
    return $out.ToString()
}

function Read-HandoffConfig {
    <#  Load, default and VALIDATE the config. Validation is not politeness: a
        lane naming a session that does not exist used to fail at 03:00, four
        hours into the run, as an unhandled throw inside a detached child whose
        stdout nobody was reading.  #>
    param([string]$Path, [string]$DefaultRepo = "")
    if (-not (Test-Path $Path)) { throw "handoff config not found: $Path" }
    try { $raw = ConvertTo-HandoffHash (Get-Content $Path -Raw | ConvertFrom-Json) }
    catch { throw "handoff config is not valid JSON: $Path — $($_.Exception.Message)" }
    if ($raw -isnot [hashtable]) { throw "handoff config must be a JSON object: $Path" }

    $cfg = @{}
    foreach ($k in $script:HandoffDefaults.Keys) { $cfg[$k] = $script:HandoffDefaults[$k] }
    foreach ($k in $raw.Keys) { $cfg[$k] = $raw[$k] }

    # The launcher merges KEY BY KEY, unlike everything else: a repo overriding
    # just `command` must not silently lose `list`/`logs`/`stop` and leave the
    # runner unable to poll the sessions it started.
    if ($raw.ContainsKey("launcher") -and $raw["launcher"] -is [hashtable]) {
        $merged = @{}
        foreach ($k in $script:HandoffDefaults["launcher"].Keys) { $merged[$k] = $script:HandoffDefaults["launcher"][$k] }
        foreach ($k in $raw["launcher"].Keys) { $merged[$k] = $raw["launcher"][$k] }
        $cfg["launcher"] = $merged
    }

    # `repo` is optional so a copied config carries no machine-specific path.
    if (-not $cfg.ContainsKey("repo") -or -not $cfg["repo"]) {
        if ($DefaultRepo) { $cfg["repo"] = $DefaultRepo }
        else { throw "config does not set 'repo' and no git repository was detected — run from inside a checkout, or set 'repo' explicitly" }
    }
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
Build-HandoffGuardCommand, Read-HandoffConfig, Build-HandoffSubagentPolicy,
Get-HandoffSessionVars, Build-HandoffBrief, Export-HandoffBriefs,
Get-HandoffLinkType, Resolve-HandoffRepoRoot, Build-HandoffLaunchArgs, New-HandoffConfigScaffold

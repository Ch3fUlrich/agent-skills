<#
.SYNOPSIS
    Verify that every repo serves its OWN graphify graph (Windows mirror of
    linux/check-graphify-scope.sh — keep the two in sync).

.DESCRIPTION
    Graphify is REPO-BOUND: the server resolves graphify-out/graph.json
    relative to its bind mount, so one server serves exactly one repo. Three
    gates must all be open, and NONE of them errors when shut:

      1. project-scoped server in <repo>\.mcp.json mounting THAT repo
           missed -> another repo's graph answers for yours, silently
      2. approval in <repo>\.claude\settings.local.json enabledMcpjsonServers
           missed -> tool simply absent; no prompt, no error
      3. a built graph at <repo>\graphify-out\graph.json
           missed -> server starts and serves nothing

    Also catches graphify-docker/omnigraph in USER scope (~/.claude.json):
    one global entry serves one repo's data to every repo (the 2026-07-19 bug).

    WINDOWS-SPECIFIC GATE — the mount path. The committed .mcp.json files use
    "${CODE_ROOT:-/home/s/code}/<repo>:/repo". That POSIX default is correct on
    Linux and WRONG here, so CODE_ROOT must be set to your Windows code root
    (e.g. C:/Users/you/code) or docker mounts a path that does not exist and
    the server serves an empty graph. This script flags that explicitly.

    NOT CHECKED HERE — file ownership. On Docker Desktop bind mounts, files
    the container creates surface as the host user, so the root-owned
    graphify-out problem the Linux checker repairs does not arise. If your
    repos live on a WSL filesystem (\\wsl$\... or /home/... inside WSL), run
    the .sh version from inside WSL instead — there it does apply.

.PARAMETER CodeRoot
    Directory whose immediate subdirectories are the repos to check.
    Defaults to $env:CODE_ROOT, else $HOME\code.

.PARAMETER Fix
    Apply the one safe repair: approve graphify-docker in the repo's untracked
    .claude\settings.local.json. Never edits tracked files and never builds a
    graph (that is a real extraction run).

.EXAMPLE
    .\check-graphify-scope.ps1
.EXAMPLE
    .\check-graphify-scope.ps1 -CodeRoot C:\Users\me\code -Fix
#>
[CmdletBinding()]
param(
    [string]$CodeRoot = $(if ($env:CODE_ROOT) { $env:CODE_ROOT } else { Join-Path $HOME 'code' }),
    [switch]$Fix
)

$ErrorActionPreference = 'Stop'
$problems = 0

function Write-Gate {
    param([string]$State, [string]$Text)
    switch ($State) {
        'ok'   { Write-Host "  v $Text" -ForegroundColor Green }
        'bad'  { Write-Host "  X $Text" -ForegroundColor Red }
        'warn' { Write-Host "  ~ $Text" -ForegroundColor Yellow }
        'hint' { Write-Host "    $Text" -ForegroundColor DarkGray }
    }
}

# Expand ${VAR} / ${VAR:-default} the way Claude Code does, so the mount we
# test is the mount docker will actually receive.
function Expand-McpVars {
    param([string]$Value)
    $re = [regex]'\$\{([A-Za-z_]\w*)(?::-([^}]*))?\}'
    return $re.Replace($Value, {
        param($m)
        $envVal = [Environment]::GetEnvironmentVariable($m.Groups[1].Value)
        if ($envVal) { return $envVal }
        return $m.Groups[2].Value
    })
}

function Normalize-Path {
    param([string]$P)
    if (-not $P) { return '' }
    return ($P -replace '\\', '/').TrimEnd('/').ToLowerInvariant()
}

Write-Host '======================================================================' -ForegroundColor Cyan
Write-Host "  Graphify - scope check   (code root: $CodeRoot)" -ForegroundColor Cyan
Write-Host '======================================================================' -ForegroundColor Cyan

# ---------------------------------------------------------------- user scope
# Repo-bound servers must never live here: a single global entry answers for
# every repo, which is exactly the failure this check exists to prevent.
Write-Host ''
Write-Host 'USER SCOPE  ~/.claude.json'
$userCfgPath = Join-Path $HOME '.claude.json'
$leaked = @()
if (Test-Path $userCfgPath) {
    try {
        $userCfg = Get-Content $userCfgPath -Raw | ConvertFrom-Json
        if ($userCfg.PSObject.Properties.Name -contains 'mcpServers' -and $userCfg.mcpServers) {
            $names = @($userCfg.mcpServers.PSObject.Properties.Name)
            $leaked = @($names | Where-Object { $_ -in @('graphify-docker', 'graphify', 'omnigraph') })
        }
    } catch {
        Write-Gate warn "could not parse $userCfgPath : $($_.Exception.Message)"
    }
}
if ($leaked.Count -gt 0) {
    Write-Gate bad "repo-bound server(s) in user scope: $($leaked -join ', ')"
    Write-Gate hint "Serves ONE repo's data to EVERY repo. Remove with:"
    foreach ($s in $leaked) { Write-Gate hint "claude mcp remove -s user $s" }
    $problems++
} else {
    Write-Gate ok 'clean - no repo-bound servers in user scope'
}

# ------------------------------------------------------------------ per repo
if (-not (Test-Path $CodeRoot)) {
    Write-Host ''
    Write-Host "X CodeRoot not found: $CodeRoot" -ForegroundColor Red
    exit 1
}

foreach ($repoDir in Get-ChildItem -Path $CodeRoot -Directory) {
    $repo = $repoDir.FullName
    $name = $repoDir.Name
    if (-not (Test-Path (Join-Path $repo '.git'))) { continue }

    $mcpPath      = Join-Path $repo '.mcp.json'
    $graphPath    = Join-Path $repo 'graphify-out\graph.json'
    $graphOutDir  = Join-Path $repo 'graphify-out'
    $settingsPath = Join-Path $repo '.claude\settings.local.json'

    # "Participating" = declares a graphify server or has a graph. A repo with
    # neither simply does not use graphify; silence is correct there.
    $declares = (Test-Path $mcpPath) -and ((Get-Content $mcpPath -Raw) -match 'graphify')
    if (-not $declares -and -not (Test-Path $graphOutDir)) { continue }

    Write-Host ''
    Write-Host $name -ForegroundColor Cyan -NoNewline
    Write-Host "  $repo" -ForegroundColor DarkGray

    # -- gate 1: project-scoped server mounting THIS repo --------------------
    $srv = $null
    if (Test-Path $mcpPath) {
        try {
            $mcp = Get-Content $mcpPath -Raw | ConvertFrom-Json
            if ($mcp.mcpServers -and ($mcp.mcpServers.PSObject.Properties.Name -contains 'graphify-docker')) {
                $srv = $mcp.mcpServers.'graphify-docker'
            }
        } catch {
            Write-Gate bad "gate 1  .mcp.json is not valid JSON: $($_.Exception.Message)"
            $problems++
        }
    }
    if (-not $srv) {
        Write-Gate bad "gate 1  no graphify-docker in $name\.mcp.json"
        Write-Gate hint "Another repo's graph may answer for this one. See"
        Write-Gate hint 'skills/mcp-servers-setup/SKILL.md -> Graphify -> Per-repo setup'
        $problems++
    } else {
        $rawMount = @($srv.args | Where-Object { $_ -like '*:/repo' }) | Select-Object -First 1
        $rawHost  = ''
        if ($rawMount) { $rawHost = ($rawMount -replace ':/repo$', '') }
        $expanded = Expand-McpVars $rawHost

        if ((Normalize-Path $expanded) -eq (Normalize-Path $repo)) {
            Write-Gate ok 'gate 1  project-scoped server mounts this repo'
        } elseif ($expanded -match '^/' ) {
            # A POSIX path on Windows: the committed default, with CODE_ROOT unset.
            Write-Gate bad "gate 1  mount is a POSIX path and cannot exist here: $expanded"
            Write-Gate hint 'The .mcp.json default targets Linux. Set CODE_ROOT to your'
            Write-Gate hint "Windows code root, e.g.  setx CODE_ROOT `"$($CodeRoot -replace '\\','/')`""
            Write-Gate hint 'then restart Claude Code so the new value is picked up.'
            $problems++
        } else {
            Write-Gate bad "gate 1  mounts the WRONG path: $expanded"
            Write-Gate hint "It will serve that repo's graph, not this one."
            $problems++
        }
    }

    # -- gate 2: approved in untracked local settings ------------------------
    $approved = 'NO'
    if (Test-Path $settingsPath) {
        try {
            $st = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if ($st.PSObject.Properties.Name -contains 'enableAllProjectMcpServers' -and $st.enableAllProjectMcpServers -eq $true) {
                $approved = 'ALL'
            } elseif ($st.PSObject.Properties.Name -contains 'enabledMcpjsonServers' -and
                      (@($st.enabledMcpjsonServers) -contains 'graphify-docker')) {
                $approved = 'YES'
            }
        } catch { $approved = 'NO' }
    }

    if ($approved -eq 'YES' -or $approved -eq 'ALL') {
        Write-Gate ok 'gate 2  approved in local settings'
    } elseif ($Fix) {
        $claudeDir = Join-Path $repo '.claude'
        if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir | Out-Null }
        $obj = $null
        if (Test-Path $settingsPath) {
            try { $obj = Get-Content $settingsPath -Raw | ConvertFrom-Json } catch { $obj = $null }
        }
        if (-not $obj) { $obj = [pscustomobject]@{} }
        $list = @()
        if ($obj.PSObject.Properties.Name -contains 'enabledMcpjsonServers') {
            $list = @($obj.enabledMcpjsonServers)
        }
        if ($list -notcontains 'graphify-docker') { $list += 'graphify-docker' }
        if ($obj.PSObject.Properties.Name -contains 'enabledMcpjsonServers') {
            $obj.enabledMcpjsonServers = $list
        } else {
            $obj | Add-Member -NotePropertyName enabledMcpjsonServers -NotePropertyValue $list
        }
        ($obj | ConvertTo-Json -Depth 20) + "`n" | Set-Content -Path $settingsPath -Encoding UTF8 -NoNewline
        Write-Gate warn 'gate 2  FIXED - approved graphify-docker in local settings'
    } else {
        Write-Gate bad 'gate 2  not approved -> the tool will be silently ABSENT'
        Write-Gate hint "Add to $name\.claude\settings.local.json (untracked):"
        Write-Gate hint '  { "enabledMcpjsonServers": ["graphify-docker"] }   (or -Fix)'
        $problems++
    }

    # -- gate 3: a graph exists ---------------------------------------------
    if (Test-Path $graphPath) {
        $age = [int]((Get-Date) - (Get-Item $graphPath).LastWriteTime).TotalDays
        if ($age -gt 14) {
            Write-Gate warn "gate 3  graph exists but is ${age}d old - consider rebuilding"
        } else {
            Write-Gate ok "gate 3  graph present (${age}d old)"
        }
    } else {
        Write-Gate bad 'gate 3  no graphify-out\graph.json - server would serve nothing'
        Write-Gate hint "cd $repo; docker run --rm -v `"`$(`$PWD.Path):/repo`" -w /repo ``"
        Write-Gate hint '  --entrypoint python graphify-mcp:latest -m graphify update .'
        $problems++
    }
}

Write-Host ''
Write-Host '----------------------------------------------------------------------' -ForegroundColor Cyan
if ($problems -eq 0) {
    Write-Host '  All gates open - every participating repo serves its own graph.' -ForegroundColor Green
} else {
    Write-Host "  $problems problem(s) found - see the fixes above (or re-run with -Fix)." -ForegroundColor Red
}
Write-Host '======================================================================' -ForegroundColor Cyan

if ($problems -eq 0) { exit 0 } else { exit 1 }

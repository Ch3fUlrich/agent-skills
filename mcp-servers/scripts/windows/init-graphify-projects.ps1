<#
.SYNOPSIS
    Build Graphify knowledge graphs for one or more repositories (Windows).

.DESCRIPTION
    Runs Graphify against a repository, writes graphify-out/graph.json, and
    optionally installs the post-commit hooks that keep the graph fresh.

    Graphify is used as a project graph layer, not as a Serena replacement.
    Serena still handles symbol-level navigation; Graphify handles graph-level
    queries across code and docs.

.PARAMETER Path
    A single repository to initialize. Defaults to the current directory.

.PARAMETER CodeRoot
    If set, batch-initializes every git repository directly under this folder.

.PARAMETER Force
    Rebuild the graph even if graphify-out/graph.json already exists.

.PARAMETER InstallHooks
    Install Graphify's git hooks after a successful build.

.PARAMETER Backend
    Graphify backend for extraction. Defaults to ollama so the stack stays
    local and does not require an external API key.

.EXAMPLE
    .\init-graphify-projects.ps1
    Initialize the repository in the current directory.

.EXAMPLE
    .\init-graphify-projects.ps1 -CodeRoot C:\Users\me\Documents\Code
    Initialize every git repo directly under the given folder.
#>
[CmdletBinding()]
param(
    [string]$Path = (Get-Location).Path,
    [string]$CodeRoot,
    [switch]$Force,
    [switch]$InstallHooks = $true,
    [string]$Backend = 'ollama'
)

$ErrorActionPreference = 'Stop'
$GraphifyOut = 'graphify-out\graph.json'

function Invoke-Graphify {
    param(
        [string]$RepoPath,
        [string]$RepoName
    )

    $graphPath = Join-Path $RepoPath $GraphifyOut
    if ((Test-Path $graphPath) -and (-not $Force)) {
        Write-Host "  - $RepoName : graph already exists (use -Force to rebuild)" -ForegroundColor DarkGray
        return [pscustomobject]@{ Repo = $RepoName; Status = 'skipped'; Path = $graphPath }
    }

    Write-Host "  - $RepoName : building graph with backend '$Backend'" -ForegroundColor Green
    Push-Location $RepoPath
    try {
        $extractArgs = @(
            'run', '--with', 'graphifyy', 'graphify',
            'extract', '.', '--backend', $Backend, '--no-viz', '--force'
        )
        & uv @extractArgs
        if ($LASTEXITCODE -ne 0) {
            throw "graphify extract failed with exit code $LASTEXITCODE"
        }

        if ($InstallHooks) {
            $hookArgs = @('run', '--with', 'graphifyy', 'graphify', 'hook', 'install')
            & uv @hookArgs
            if ($LASTEXITCODE -ne 0) {
                throw "graphify hook install failed with exit code $LASTEXITCODE"
            }
        }

        if (-not (Test-Path $graphPath)) {
            throw "expected graph not found at $graphPath"
        }

        Write-Host "    v graphify-out\graph.json ready" -ForegroundColor Green
        return [pscustomobject]@{ Repo = $RepoName; Status = 'built'; Path = $graphPath }
    } finally {
        Pop-Location
    }
}

Write-Host '======================================================================' -ForegroundColor Cyan
Write-Host '  Graphify - Initialize Repository Graphs (Windows)' -ForegroundColor Cyan
Write-Host '======================================================================' -ForegroundColor Cyan

if ($Backend -eq 'ollama') {
    try {
        Invoke-WebRequest -Uri 'http://localhost:11434/api/tags' -UseBasicParsing -TimeoutSec 3 | Out-Null
    } catch {
        Write-Host "X Ollama is not responding on :11434. Start it before building local graphs." -ForegroundColor Red
        exit 1
    }
}

$targets = @()
if ($CodeRoot) {
    if (-not (Test-Path $CodeRoot)) { Write-Host "X CodeRoot not found: $CodeRoot" -ForegroundColor Red; exit 1 }
    $targets = @(Get-ChildItem -Path $CodeRoot -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName '.git') } |
        ForEach-Object { $_.FullName })
    Write-Host "Batch mode: $($targets.Count) git repo(s) under $CodeRoot`n"
} else {
    $resolved = (Resolve-Path $Path).Path
    $targets = @($resolved)
    Write-Host "Single repo: $resolved`n"
}

$results = foreach ($target in $targets) {
    Invoke-Graphify -RepoPath $target -RepoName (Split-Path $target -Leaf)
}

$built = @($results | Where-Object { $_.Status -eq 'built' }).Count
$skipped = @($results | Where-Object { $_.Status -eq 'skipped' }).Count

Write-Host "`n----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "  built=$built  skipped=$skipped" -ForegroundColor Cyan
Write-Host '======================================================================' -ForegroundColor Cyan
# MCP Server Stack — Serena Project Initialization Script (Windows)
# ============================================================================
# Pre-creates and indexes Serena projects for all git repositories under
# the Code root directory. This prevents repeated language server downloads
# on first code navigation in each repo.
#
# Run this once after setup. Serena will detect and use these indices
# automatically via --project-from-cwd.
#
# Usage: .\windows\init-serena-projects.ps1
# ============================================================================

$ErrorActionPreference = "Continue"
$CodeRoot = "C:\Users\mauls\Documents\Code"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  Serena — Initialize All Project Indices                             " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

# Find all git repos under Code root
$Repos = Get-ChildItem -Path $CodeRoot -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName ".git")
}

Write-Host "Found $($Repos.Count) git repositories:" -ForegroundColor White
$Repos | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
Write-Host ""

$Count = 0
$Skipped = 0
$Errors = 0

foreach ($Repo in $Repos) {
    $ProjectDir = $Repo.FullName
    $ProjectName = $Repo.Name
    
    Write-Host "[$($Count + 1)/$($Repos.Count)] $ProjectName..." -ForegroundColor Yellow
    
    # Check if already indexed
    $SerenaDir = Join-Path $ProjectDir ".serena"
    $IndexFile = Join-Path $SerenaDir "project.json"
    
    if (Test-Path $IndexFile) {
        Write-Host "  Already indexed. Updating..." -ForegroundColor Gray
        try {
            serena project index "$ProjectDir" 2>&1 | Out-Null
            Write-Host "  v Updated" -ForegroundColor Green
            $Skipped++
        } catch {
            Write-Host "  Re-creating..." -ForegroundColor Yellow
            try {
                serena project create "$ProjectDir" --index 2>&1 | Out-Null
                Write-Host "  v Created + indexed" -ForegroundColor Green
                $Count++
            } catch {
                Write-Host "  X Error: $_" -ForegroundColor Red
                $Errors++
            }
        }
    } else {
        try {
            serena project create "$ProjectDir" --index 2>&1 | Out-Null
            Write-Host "  v Created + indexed" -ForegroundColor Green
            $Count++
        } catch {
            Write-Host "  X Error: $_" -ForegroundColor Red
            $Errors++
        }
    }
}

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  Complete: $Count new, $Skipped updated, $Errors errors                " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Serena will now auto-detect the correct project for each repo" -ForegroundColor Gray
Write-Host "using --project-from-cwd. Language servers are pre-downloaded." -ForegroundColor Gray
Write-Host ""
Write-Host "To re-index a specific repo later:" -ForegroundColor Gray
Write-Host "  serena project index --project C:\Users\mauls\Documents\Code\<repo>" -ForegroundColor Gray

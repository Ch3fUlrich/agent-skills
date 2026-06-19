# MCP Server Stack - Serena Project Initialization (Windows)
# Auto-answers "N" to language prompts, uses project.yml for detection
$ErrorActionPreference = "Continue"
$CodeRoot = "C:\Users\mauls\Documents\Code"
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  Serena - Initialize Project Indices" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
$Repos = Get-ChildItem -Path $CodeRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".git") }
Write-Host "Found $($Repos.Count) repos"
$Count = 0; $Skipped = 0; $Errors = 0
foreach ($Repo in $Repos) {
    $ProjectDir = $Repo.FullName
    $ProjectName = $Repo.Name
    Write-Host "[$($Count + $Skipped + $Errors + 1)/$($Repos.Count)] $ProjectName..." -ForegroundColor Yellow
    $IndexFile = "$ProjectDir\.serena\project.yml"
    if (Test-Path $IndexFile) {
        Write-Host "  Already indexed" -ForegroundColor Gray
        $Skipped++
    } else {
        try {
            ("N`n" * 10) | serena project create "$ProjectDir" --index 2>&1 | Out-Null
            Write-Host "  v Created + indexed" -ForegroundColor Green
            $Count++
        } catch {
            Write-Host "  X Error: $_" -ForegroundColor Red
            $Errors++
        }
    }
}
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  Complete: $Count new, $Skipped skipped, $Errors errors" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
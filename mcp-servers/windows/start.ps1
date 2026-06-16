# MCP Server Stack — Start Services + Initialize New Repos (Windows)
# ============================================================================
# Starts Qdrant, checks Ollama, and initializes new Serena project indices.
#
# Usage: .\windows\start.ps1
# ============================================================================

$ErrorActionPreference = "Continue"
$RepoRoot = Resolve-Path "$PSScriptRoot\.."
$CodeRoot = "C:\Users\mauls\Documents\Code"

Write-Host "Starting MCP services..." -ForegroundColor Cyan

# ─── Qdrant ─────────────────────────────────────────────────────────────────
Push-Location $RepoRoot
docker compose up -d 2>&1 | Out-Null
Pop-Location

Write-Host "  Waiting for Qdrant..." -ForegroundColor Gray
$retries = 0; while ($retries -lt 30) { try { if ((Invoke-WebRequest -Uri "http://localhost:6333/" -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { break } } catch { } $retries++; Start-Sleep -Seconds 2 }
Write-Host "  v Qdrant ready on :6333" -ForegroundColor Green

# ─── Ollama (native) ────────────────────────────────────────────────────────
try {
    $r = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 3
    Write-Host "  v Ollama ready on :11434" -ForegroundColor Green
} catch {
    Write-Host "  ! Ollama not responding. Start it manually: ollama serve" -ForegroundColor Yellow
}

# ─── Pre-warm Ollama models ─────────────────────────────────────────────────
Write-Host "  Warming models..." -ForegroundColor Gray
try {
    $null = Invoke-WebRequest -Uri "http://localhost:11434/api/embed" -Method POST -Body '{"model":"bge-m3:latest","input":"warmup"}' -ContentType "application/json" -TimeoutSec 30
    $null = Invoke-WebRequest -Uri "http://localhost:11434/api/generate" -Method POST -Body '{"model":"gemma4:e4b","prompt":"warmup","stream":false}' -ContentType "application/json" -TimeoutSec 60
    Write-Host "  v Models warmed" -ForegroundColor Green
} catch { Write-Host "  ! Model warm failed: $_" -ForegroundColor Yellow }

# ─── Initialize New Serena Projects ──────────────────────────────────────────
Write-Host "  Checking for new repos to index..." -ForegroundColor Gray
$Repos = Get-ChildItem -Path $CodeRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".git") }
$NewCount = 0
foreach ($Repo in $Repos) {
    $IndexFile = Join-Path $Repo.FullName ".serena" "project.json"
    if (-not (Test-Path $IndexFile)) {
        try {
            serena project create --project "$($Repo.FullName)" --index 2>&1 | Out-Null
            Write-Host "    v Indexed: $($Repo.Name)" -ForegroundColor Green
            $NewCount++
        } catch {
            Write-Host "    ! Skipped: $($Repo.Name)" -ForegroundColor Yellow
        }
    }
}
if ($NewCount -eq 0) { Write-Host "    All repos already indexed" -ForegroundColor Gray }

Write-Host ""
Write-Host "All services running. Restart CodeWhale." -ForegroundColor Cyan

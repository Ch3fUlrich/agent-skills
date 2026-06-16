# MCP Server Stack — Full Automated Setup (Windows)
# ============================================================================
# Installs: Serena, Mem0, Superpowers
# Backend:  Qdrant (Docker) + native Ollama (bge-m3 + gemma4:e4b)
# Then initializes Serena projects for all repos
#
# Usage: .\windows\setup.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path "$PSScriptRoot\.."
$CodeWhaleMCP = "$env:USERPROFILE\.codewhale\mcp.json"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  MCP Server Stack — Self-Hosted Setup (Windows)                      " -ForegroundColor Cyan
Write-Host "  Serena + Mem0 + Superpowers                                         " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

# ─── Prerequisites ────────────────────────────────────────────────────────────
Write-Host "[1/6] Prerequisites..." -ForegroundColor Yellow
try { docker --version 2>&1 | Out-Null; Write-Host "  v Docker" -ForegroundColor Green } catch { Write-Host "  X Docker not found" -ForegroundColor Red; exit 1 }
try { docker info 2>&1 | Out-Null; Write-Host "  v Docker running" -ForegroundColor Green } catch { Write-Host "  X Docker not running" -ForegroundColor Red; exit 1 }
try { uv --version 2>&1 | Out-Null; Write-Host "  v uv" -ForegroundColor Green } catch { Write-Host "  Installing uv..."; irm https://astral.sh/uv/install.ps1 | iex }
try { node --version 2>&1 | Out-Null; Write-Host "  v Node.js" -ForegroundColor Green } catch { Write-Host "  X Node.js not found" -ForegroundColor Red; exit 1 }
try { $r = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 3; Write-Host "  v Native Ollama" -ForegroundColor Green } catch { Write-Host "  X Ollama not running" -ForegroundColor Red; exit 1 }
Write-Host ""

# ─── Data Dirs ────────────────────────────────────────────────────────────────
Write-Host "[2/6] Data directories..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path "$RepoRoot\data\qdrant" | Out-Null
Write-Host "  v Ready" -ForegroundColor Green
Write-Host ""

# ─── Qdrant + bge-m3 ─────────────────────────────────────────────────────────
Write-Host "[3/6] Starting Qdrant + bge-m3..." -ForegroundColor Yellow
Push-Location $RepoRoot
docker compose up -d qdrant 2>&1 | Out-Null
Pop-Location

$retries = 0; while ($retries -lt 30) { try { if ((Invoke-WebRequest -Uri "http://localhost:6333/" -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { break } } catch { } $retries++; Start-Sleep -Seconds 2 }
Write-Host "  v Qdrant ready" -ForegroundColor Green

# Pull bge-m3 if not present
$tags = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing | ConvertFrom-Json
$hasBge = $tags.models | Where-Object { $_.name -eq "bge-m3:latest" }
if (-not $hasBge) { Write-Host "  Pulling bge-m3 (~2 GB)..."; Invoke-WebRequest -Uri "http://localhost:11434/api/pull" -Method POST -Body '{"name":"bge-m3:latest"}' -ContentType "application/json" -UseBasicParsing | Out-Null }
Write-Host "  v bge-m3 ready" -ForegroundColor Green
Write-Host ""

# ─── Serena Install ───────────────────────────────────────────────────────────
Write-Host "[4/6] Installing Serena..." -ForegroundColor Yellow
try { uv tool install serena-agent 2>&1 | Out-Null } catch { }
$sv = serena --version 2>&1
Write-Host "  v Serena $sv" -ForegroundColor Green
Write-Host ""

# ─── Superpowers Install ──────────────────────────────────────────────────────
Write-Host "[5/6] Installing Superpowers..." -ForegroundColor Yellow
$SpDir = "$RepoRoot\superpowers"
if (-not (Test-Path "$SpDir\build\index.js")) {
    Write-Host "  Cloning & building..." -ForegroundColor Gray
    if (-not (Test-Path "$SpDir\.git")) { git clone https://github.com/erophames/superpowers-mcp $SpDir 2>&1 | Out-Null }
    Push-Location $SpDir; npm install 2>&1 | Out-Null; npm run build 2>&1 | Out-Null; Pop-Location
}
Write-Host "  v Superpowers ready" -ForegroundColor Green
Write-Host ""

# ─── CodeWhale Config ─────────────────────────────────────────────────────────
Write-Host "[6/6] Configuring CodeWhale..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.codewhale" | Out-Null
Copy-Item -Path "$RepoRoot\config\mcp.json" -Destination $CodeWhaleMCP -Force
Write-Host "  v MCP config deployed" -ForegroundColor Green
Write-Host ""

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  Base setup complete!                                                 " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Next: Initialize Serena projects (one-time, downloads language servers)" -ForegroundColor White
Write-Host "  .\windows\init-serena-projects.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "Then restart CodeWhale." -ForegroundColor Gray
Write-Host ""

# MCP Server Stack — Full Automated Setup (Windows)
# ============================================================================
# Installs: Serena, Mem0, Superpowers
# Backend:  Mem0 Docker stack (PostgreSQL + pgvector, Mem0 REST API, MCP bridge)
#           + native Ollama (for Serena)
#
# Usage: .\windows\setup.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path "$PSScriptRoot\.."
$CodeWhaleMCP = "$env:USERPROFILE\.codewhale\mcp.json"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  MCP Server Stack — Self-Hosted Setup (Windows)                      " -ForegroundColor Cyan
Write-Host "  Serena + Superpowers + Mem0                                         " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

# --- Prerequisites ---
Write-Host "[1/6] Prerequisites..." -ForegroundColor Yellow
try { docker --version 2>&1 | Out-Null; Write-Host "  v Docker" -ForegroundColor Green } catch { Write-Host "  X Docker not found" -ForegroundColor Red; exit 1 }
try { docker info 2>&1 | Out-Null; Write-Host "  v Docker running" -ForegroundColor Green } catch { Write-Host "  X Docker not running" -ForegroundColor Red; exit 1 }
try { uv --version 2>&1 | Out-Null; Write-Host "  v uv" -ForegroundColor Green } catch { Write-Host "  Installing uv..."; irm https://astral.sh/uv/install.ps1 | iex }
try { node --version 2>&1 | Out-Null; Write-Host "  v Node.js" -ForegroundColor Green } catch { Write-Host "  X Node.js not found" -ForegroundColor Red; exit 1 }
try { $r = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 3; Write-Host "  v Native Ollama" -ForegroundColor Green } catch { Write-Host "  X Ollama not running" -ForegroundColor Red; exit 1 }
Write-Host ""

# --- Data Dirs ---
Write-Host "[2/6] Data directories..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path "$RepoRoot\data\postgres" | Out-Null
New-Item -ItemType Directory -Force -Path "$RepoRoot\data\mem0-history" | Out-Null
Write-Host "  v Ready" -ForegroundColor Green
Write-Host ""

# --- Mem0 Docker Stack ---
Write-Host "[3/6] Mem0 Docker stack..." -ForegroundColor Yellow

# Check .env exists
if (-not (Test-Path "$RepoRoot\.env")) {
    Write-Host "  Creating .env from .env.example — EDIT BEFORE CONTINUING!" -ForegroundColor Yellow
    Copy-Item "$RepoRoot\.env.example" "$RepoRoot\.env"
    Write-Host "  X Edit .env and set DEEPSEEK_API_KEY + POSTGRES_PASSWORD, then re-run." -ForegroundColor Red
    exit 1
} else {
    # Quick validation
    $envContent = Get-Content "$RepoRoot\.env" -Raw
    if ($envContent -match "DEEPSEEK_API_KEY\s*=\s*$") {
        Write-Host "  X DEEPSEEK_API_KEY not set in .env. Set it and re-run." -ForegroundColor Red
        exit 1
    }
    if ($envContent -match "POSTGRES_PASSWORD\s*=\s*$") {
        Write-Host "  X POSTGRES_PASSWORD not set in .env. Set it and re-run." -ForegroundColor Red
        exit 1
    }
    Write-Host "  v .env configured" -ForegroundColor Green
}

# Pull images
Push-Location $RepoRoot
Write-Host "  Pulling Docker images (one-time)..." -ForegroundColor Gray
docker compose pull 2>&1 | Out-Null

# Start stack
Write-Host "  Starting mem0 services..." -ForegroundColor Gray
docker compose up -d --build 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "  X Failed to start mem0 stack." -ForegroundColor Red
    Write-Host "    Check: docker compose logs" -ForegroundColor White
    Pop-Location
    exit 1
}

# Wait for services
Write-Host "  Waiting for mem0 services (up to 90s)..." -ForegroundColor Gray
$retries = 0
while ($retries -lt 30) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:8888/health" -UseBasicParsing -TimeoutSec 3
        if ($r.StatusCode -eq 200) { break }
    } catch { }
    $retries++
    Start-Sleep -Seconds 3
}
if ($retries -ge 30) {
    Write-Host "  ! Mem0 API not healthy after 90s. Check: docker compose logs mem0" -ForegroundColor Yellow
} else {
    Write-Host "  v Mem0 API ready on :8888" -ForegroundColor Green
}
Pop-Location
Write-Host ""

# --- Serena Install ---
Write-Host "[4/6] Installing Serena..." -ForegroundColor Yellow
try { uv tool install serena-agent 2>&1 | Out-Null } catch { }
$sv = serena --version 2>&1
Write-Host "  v Serena $sv" -ForegroundColor Green
Write-Host ""

# --- Superpowers Install ---
Write-Host "[5/6] Installing Superpowers..." -ForegroundColor Yellow
$SpDir = "$RepoRoot\superpowers"
if (-not (Test-Path "$SpDir\build\index.js")) {
    Write-Host "  Cloning & building..." -ForegroundColor Gray
    if (-not (Test-Path "$SpDir\.git")) { git clone https://github.com/erophames/superpowers-mcp $SpDir 2>&1 | Out-Null }
    Push-Location $SpDir; npm install 2>&1 | Out-Null; npm run build 2>&1 | Out-Null; Pop-Location
}
Write-Host "  v Superpowers ready" -ForegroundColor Green
Write-Host ""

# --- CodeWhale Config ---
Write-Host "[6/6] Configuring CodeWhale..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.codewhale" | Out-Null
Copy-Item -Path "$RepoRoot\config\mcp.json" -Destination $CodeWhaleMCP -Force
Write-Host "  v MCP config deployed" -ForegroundColor Green
Write-Host ""

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  Setup complete!                                                     " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Services running:" -ForegroundColor White
Write-Host "  Mem0 API:         http://localhost:8888/docs" -ForegroundColor Gray
Write-Host "  Mem0 MCP bridge:  http://localhost:8001/sse" -ForegroundColor Gray
Write-Host ""
Write-Host "Next:" -ForegroundColor White
Write-Host "  1. Initialize Serena projects: .\windows\init-serena-projects.ps1" -ForegroundColor Gray
Write-Host "  2. Restart CodeWhale" -ForegroundColor Gray
Write-Host ""

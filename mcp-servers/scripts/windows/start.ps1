# MCP Server Stack — Start Services + Initialize New Repos (Windows)
# ============================================================================
# Ensures Docker Desktop is running, starts the mem0 Docker stack, verifies
# Ollama availability for Serena, and indexes new Serena repos.
#
# Usage: .\windows\start.ps1
# ============================================================================

$ErrorActionPreference = "Continue"
$RepoRoot = Resolve-Path "$PSScriptRoot\.."
$CodeRoot = "C:\Users\mauls\Documents\Code"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  MCP Server Stack — Start Services                                  " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: Docker Desktop ---
Write-Host "[1/4] Docker Desktop" -ForegroundColor Yellow

try {
    $dockerVersion = docker --version 2>&1
    Write-Host "  v Docker: $dockerVersion" -ForegroundColor Green
} catch {
    Write-Host "  X Docker not installed. Install Docker Desktop:" -ForegroundColor Red
    Write-Host "    winget install Docker.DockerDesktop" -ForegroundColor White
    Write-Host "    Then re-run this script." -ForegroundColor White
    exit 1
}

try {
    docker info 2>&1 | Out-Null
    Write-Host "  v Docker daemon is running" -ForegroundColor Green
} catch {
    Write-Host "  Docker daemon not running. Attempting to start Docker Desktop..." -ForegroundColor Yellow

    $dockerDesktop = "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerDesktop) {
        Start-Process -FilePath $dockerDesktop -WindowStyle Hidden
        Write-Host "  Launching Docker Desktop..." -ForegroundColor Gray
    } elseif (Test-Path "${env:LocalAppData}\Docker\Docker Desktop.exe") {
        Start-Process -FilePath "${env:LocalAppData}\Docker\Docker Desktop.exe" -WindowStyle Hidden
        Write-Host "  Launching Docker Desktop..." -ForegroundColor Gray
    } else {
        Write-Host "  X Docker Desktop executable not found." -ForegroundColor Red
        Write-Host "    Start Docker Desktop manually, then re-run this script." -ForegroundColor White
        exit 1
    }

    Write-Host "  Waiting for Docker daemon to start (up to 60s)..." -ForegroundColor Gray
    $dockerRetries = 0
    while ($dockerRetries -lt 30) {
        Start-Sleep -Seconds 2
        try {
            docker info 2>&1 | Out-Null
            break
        } catch { }
        $dockerRetries++
        if ($dockerRetries % 5 -eq 0) { Write-Host "    ...still waiting ($($dockerRetries * 2)s)" -ForegroundColor Gray }
    }

    try {
        docker info 2>&1 | Out-Null
        Write-Host "  v Docker daemon is now running" -ForegroundColor Green
    } catch {
        Write-Host "  X Docker did not start within 60 seconds." -ForegroundColor Red
        Write-Host "    Check Docker Desktop manually and re-run." -ForegroundColor White
        exit 1
    }
}

Write-Host ""

# --- Step 2: Mem0 Docker Stack ---
Write-Host "[2/4] Mem0 memory stack" -ForegroundColor Yellow

Push-Location $RepoRoot

# Pull latest images (skip if we want fast startup)
Write-Host "  Pulling latest images..." -ForegroundColor Gray
docker compose pull postgres mem0 2>&1 | Out-Null

# Start the stack
Write-Host "  Starting mem0 services..." -ForegroundColor Gray
docker compose up -d --build 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "  X Failed to start mem0 stack." -ForegroundColor Red
    Write-Host "    Check: docker compose logs" -ForegroundColor White
    Pop-Location
    exit 1
}

# Wait for mem0 API to become healthy
Write-Host "  Waiting for mem0 API health check..." -ForegroundColor Gray
$mem0Retries = 0
while ($mem0Retries -lt 30) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:8888/health" -UseBasicParsing -TimeoutSec 3
        if ($r.StatusCode -eq 200) {
            Write-Host "  v Mem0 API ready on :8888" -ForegroundColor Green
            break
        }
    } catch { }
    $mem0Retries++
    if ($mem0Retries % 5 -eq 0) { Write-Host "    ...still waiting ($($mem0Retries * 3)s)" -ForegroundColor Gray }
    Start-Sleep -Seconds 3
}

if ($mem0Retries -ge 30) {
    Write-Host "  ! Mem0 API not healthy after 90s. Check: docker compose logs mem0" -ForegroundColor Yellow
} else {
    # Check MCP bridge too
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:8001/sse" -UseBasicParsing -TimeoutSec 3
        Write-Host "  v Mem0 MCP bridge ready on :8001" -ForegroundColor Green
    } catch {
        Write-Host "  ! MCP bridge not ready yet (may still be building)" -ForegroundColor Yellow
    }
}

Pop-Location
Write-Host ""

# --- Step 3: Ollama (for Serena) ---
Write-Host "[3/4] Ollama (native)" -ForegroundColor Yellow

try {
    $r = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 3
    $models = (ConvertFrom-Json $r.Content).models.name
    Write-Host "  v Ollama ready on :11434" -ForegroundColor Green
    Write-Host "    Models: $($models -join ', ')" -ForegroundColor Gray
} catch {
    Write-Host "  ! Ollama not responding on :11434." -ForegroundColor Yellow
    Write-Host "    Serena may be affected. Install: winget install Ollama.Ollama" -ForegroundColor White
}

Write-Host ""

# --- Step 4: Serena Initialization ---
Write-Host "[4/4] Serena project initialization" -ForegroundColor Yellow

try {
    serena --version 2>&1 | Out-Null
    Write-Host "  v Serena CLI available" -ForegroundColor Green
} catch {
    Write-Host "  ! serena not on PATH; checking uvx..." -ForegroundColor Yellow
    try {
        uvx --from serena-agent serena --version 2>&1 | Out-Null
        Write-Host "  v Serena available via uvx" -ForegroundColor Green
    } catch {
        Write-Host "  X Serena not found. Run setup.ps1 first." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  Services started!                                                   " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Mem0 API:         http://localhost:8888/docs" -ForegroundColor Gray
Write-Host "  Mem0 MCP bridge:  http://localhost:8001/sse" -ForegroundColor Gray
Write-Host ""
Write-Host "Restart CodeWhale to connect to the MCP bridge." -ForegroundColor White
Write-Host ""

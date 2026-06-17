# MCP Server Stack — Start Services + Initialize New Repos (Windows)
# ============================================================================
# Ensures Docker Desktop is running, starts Qdrant container, verifies
# Ollama availability, pre-warms models, and indexes new Serena repos.
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

# ─── Step 1: Docker Desktop ─────────────────────────────────────────────────
Write-Host "[1/4] Docker Desktop" -ForegroundColor Yellow

# Check if Docker is installed
try {
    $dockerVersion = docker --version 2>&1
    Write-Host "  v Docker: $dockerVersion" -ForegroundColor Green
} catch {
    Write-Host "  X Docker not installed. Install Docker Desktop:" -ForegroundColor Red
    Write-Host "    winget install Docker.DockerDesktop" -ForegroundColor White
    Write-Host "    Then re-run this script." -ForegroundColor White
    exit 1
}

# Check if Docker daemon is running; if not, try to start Docker Desktop
try {
    docker info 2>&1 | Out-Null
    Write-Host "  v Docker daemon is running" -ForegroundColor Green
} catch {
    Write-Host "  Docker daemon not running. Attempting to start Docker Desktop..." -ForegroundColor Yellow

    # Try to launch Docker Desktop (it takes ~10-20s to start)
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

    # Wait up to 60s for Docker to become ready
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

    # Final check
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

# ─── Step 2: Start Qdrant Container ─────────────────────────────────────────
Write-Host "[2/4] Qdrant vector database" -ForegroundColor Yellow

Push-Location $RepoRoot

# Check if Qdrant container already exists and is running
$qdrantRunning = $false
try {
    $qdrantStatus = docker inspect --format='{{.State.Status}}' mcp-qdrant 2>&1
    if ($qdrantStatus -eq "running") {
        Write-Host "  v Qdrant container is already running" -ForegroundColor Green
        $qdrantRunning = $true
    }
} catch {
    # Container doesn't exist yet — will create it
}

if (-not $qdrantRunning) {
    Write-Host "  Starting Qdrant container..." -ForegroundColor Gray

    # Pull latest image (optional, skip if we want fast startup)
    # docker compose pull qdrant 2>&1 | Out-Null

    docker compose up -d qdrant 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  X Failed to start Qdrant container." -ForegroundColor Red
        Write-Host "    Check: docker compose logs qdrant" -ForegroundColor White
        Pop-Location
        exit 1
    }
}

# Wait for Qdrant to become healthy
Write-Host "  Waiting for Qdrant health check..." -ForegroundColor Gray
$qdrantRetries = 0
while ($qdrantRetries -lt 30) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:6333/" -UseBasicParsing -TimeoutSec 2
        if ($r.StatusCode -eq 200) {
            $version = (ConvertFrom-Json $r.Content).version
            Write-Host "  v Qdrant v$version ready on :6333" -ForegroundColor Green
            break
        }
    } catch { }
    $qdrantRetries++
    if ($qdrantRetries % 5 -eq 0) { Write-Host "    ...still waiting ($($qdrantRetries * 2)s)" -ForegroundColor Gray }
    Start-Sleep -Seconds 2
}

if ($qdrantRetries -ge 30) {
    Write-Host "  X Qdrant did not become healthy within 60 seconds." -ForegroundColor Red
    Write-Host "    Check: docker compose logs qdrant" -ForegroundColor White
    Pop-Location
    exit 1
}

# Verify collection exists
try {
    $collections = Invoke-WebRequest -Uri "http://localhost:6333/collections" -UseBasicParsing -TimeoutSec 3
    $collectionNames = ((ConvertFrom-Json $collections.Content).result.collections).name
    if ($collectionNames -contains "mem0_mcp_selfhosted") {
        $points = (Invoke-WebRequest -Uri "http://localhost:6333/collections/mem0_mcp_selfhosted" -UseBasicParsing -TimeoutSec 3).Content | ConvertFrom-Json
        Write-Host "  v Collection 'mem0_mcp_selfhosted' exists ($($points.result.points_count) points)" -ForegroundColor Green
    } else {
        Write-Host "  ! No mem0 collection yet (will be created on first use)" -ForegroundColor Gray
    }
} catch {
    Write-Host "  ! Could not verify Qdrant collections" -ForegroundColor Gray
}

Pop-Location
Write-Host ""

# ─── Step 3: Ollama ─────────────────────────────────────────────────────────
Write-Host "[3/4] Ollama (native)" -ForegroundColor Yellow

try {
    $r = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 3
    $models = (ConvertFrom-Json $r.Content).models.name
    Write-Host "  v Ollama ready on :11434" -ForegroundColor Green
    Write-Host "    Models: $($models -join ', ')" -ForegroundColor Gray

    # Check for required models
    $hasBge = $models -contains "bge-m3:latest"
    $hasQwen = $models -contains "qwen2.5:1.5b"
    if (-not $hasBge) {
        Write-Host "  ! bge-m3 not found. Pulling (~2 GB, one-time)..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri "http://localhost:11434/api/pull" -Method POST -Body '{"name":"bge-m3:latest"}' -ContentType "application/json" -UseBasicParsing | Out-Null
    }
    if (-not $hasQwen) {
        Write-Host "  ! qwen2.5:1.5b not found. Pulling (~1 GB, one-time)..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri "http://localhost:11434/api/pull" -Method POST -Body '{"name":"qwen2.5:1.5b"}' -ContentType "application/json" -UseBasicParsing | Out-Null
    }
} catch {
    Write-Host "  X Ollama not responding on :11434." -ForegroundColor Red
    Write-Host "    Install: winget install Ollama.Ollama" -ForegroundColor White
    Write-Host "    Then run: ollama serve" -ForegroundColor White
    exit 1
}

Write-Host ""

# ─── Step 4: Pre-warm + Initialize ──────────────────────────────────────────
Write-Host "[4/4] Initialization" -ForegroundColor Yellow

# Pre-warm models (load into VRAM so first mem0 call is fast)
Write-Host "  Pre-warming models..." -ForegroundColor Gray
$warmOk = $true
try {
    $null = Invoke-WebRequest -Uri "http://localhost:11434/api/embed" -Method POST -Body '{"model":"bge-m3:latest","input":"warmup"}' -ContentType "application/json" -TimeoutSec 30
    Write-Host "    v bge-m3" -ForegroundColor Green
} catch {
    Write-Host "    ! bge-m3 warm failed" -ForegroundColor Yellow
    $warmOk = $false
}

try {
    $null = Invoke-WebRequest -Uri "http://localhost:11434/api/generate" -Method POST -Body '{"model":"qwen2.5:1.5b","prompt":"warmup","stream":false}' -ContentType "application/json" -TimeoutSec 60
    Write-Host "    v qwen2.5:1.5b" -ForegroundColor Green
} catch {
    Write-Host "    ! qwen2.5 warm failed" -ForegroundColor Yellow
    $warmOk = $false
}

if ($warmOk) { Write-Host "  v Models pre-warmed and loaded in VRAM" -ForegroundColor Green }
else { Write-Host "  ! Some models not warmed — first call may be slow" -ForegroundColor Yellow }

# Initialize new Serena repositories
Write-Host "  Checking for new repos to index..." -ForegroundColor Gray
$Repos = Get-ChildItem -Path $CodeRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".git") }
$NewCount = 0
foreach ($Repo in $Repos) {
    $IndexFile = Join-Path $Repo.FullName ".serena" "project.yml"
    if (-not (Test-Path $IndexFile)) {
        try {
            ("N`n" * 10) | serena project create "$($Repo.FullName)" --index 2>&1 | Out-Null
            Write-Host "    v Indexed: $($Repo.Name)" -ForegroundColor Green
            $NewCount++
        } catch {
            Write-Host "    ! Skipped: $($Repo.Name)" -ForegroundColor Yellow
        }
    }
}
if ($NewCount -eq 0) { Write-Host "    All repos already indexed" -ForegroundColor Gray }

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  All services running. Ready to start CodeWhale.                     " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Qdrant:   http://localhost:6333/dashboard" -ForegroundColor Gray
Write-Host "  Ollama:   http://localhost:11434" -ForegroundColor Gray
Write-Host ""
Write-Host "  Active MCP servers: Serena, Superpowers, Filesystem" -ForegroundColor Gray
Write-Host ""

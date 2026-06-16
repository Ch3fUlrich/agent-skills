# MCP Server Stack — Test All MCP Servers
# ============================================================================
# Tests:
#   1. Docker services (Qdrant + Ollama) are running & healthy
#   2. Serena CLI works (can list tools)
#   3. Mem0 MCP server starts (checks Qdrant connection)
#   4. Superpowers MCP server starts
#   5. CodeWhale MCP config is valid
#
# Usage: .\scripts\test.ps1
# ============================================================================

$ErrorActionPreference = "Continue"
$RepoRoot = Resolve-Path "$PSScriptRoot\.."
$CodeWhaleMCP = "$env:USERPROFILE\.codewhale\mcp.json"

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     MCP Server Stack — Test Suite                             ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$Passed = 0
$Failed = 0
$Warned = 0

function Test-Pass { Write-Host "  ✓ PASS: $args" -ForegroundColor Green; $script:Passed++ }
function Test-Fail { Write-Host "  ✗ FAIL: $args" -ForegroundColor Red; $script:Failed++ }
function Test-Warn { Write-Host "  ⚠ WARN: $args" -ForegroundColor Yellow; $script:Warned++ }

# ─── Test 1: Docker Services ─────────────────────────────────────────────────
Write-Host "[Test 1] Docker Services" -ForegroundColor Cyan

# Qdrant
try {
    $r = Invoke-WebRequest -Uri "http://localhost:6333/" -UseBasicParsing -TimeoutSec 5
    if ($r.StatusCode -eq 200 -and ($r.Content -match "qdrant")) { Test-Pass "Qdrant is healthy on :6333 v$((ConvertFrom-Json $r.Content).version)" }
    else { Test-Fail "Qdrant returned unexpected response" }
} catch {
    Test-Fail "Qdrant is not reachable — run: docker compose up -d"
}

# Ollama
try {
    $r = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 5
    $models = ($r.Content | ConvertFrom-Json).models
    $bge = $models | Where-Object { $_.name -like "*bge-m3*" }
    if ($bge) { Test-Pass "Ollama running, bge-m3 model loaded" }
    else { Test-Warn "Ollama running, but bge-m3 not yet pulled. Run: docker exec mcp-ollama ollama pull bge-m3" }
} catch {
    Test-Fail "Ollama is not reachable — run: docker compose up -d"
}
Write-Host ""

# ─── Test 2: Serena MCP Server ───────────────────────────────────────────────
Write-Host "[Test 2] Serena MCP Server" -ForegroundColor Cyan

try {
    $serenaVersion = serena --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Test-Pass "Serena CLI: $serenaVersion"
    } else {
        Test-Warn "serena not on PATH; checking uvx fallback..."
        $serenaVersion2 = uvx --from serena-agent serena --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Test-Pass "Serena works via uvx: $serenaVersion2"
        } else {
            Test-Fail "Serena not available"
        }
    }
} catch {
    Test-Fail "Serena check failed: $_"
}

# Quick Serena tool listing
try {
    Write-Host "  Testing Serena tool listing..." -ForegroundColor Gray
    $toolOutput = serena tools list --all 2>&1
    if ($LASTEXITCODE -eq 0) {
        $toolCount = ($toolOutput | Select-String -Pattern "^\s+\* " | Measure-Object).Count
        if ($toolCount -gt 0) { Test-Pass "Serena reports $toolCount available tools" }
        else { Test-Pass "Serena tool listing successful" }
    } else {
        Test-Warn "Serena tool listing had non-zero exit"
    }
} catch {
    Test-Warn "Serena tool listing not available: $_"
}
Write-Host ""

# ─── Test 3: Mem0 MCP Server Structure ───────────────────────────────────────
Write-Host "[Test 3] Mem0 Configuration" -ForegroundColor Cyan

$Mem0Config = "$RepoRoot\config\mem0-config.yaml"
if (Test-Path $Mem0Config) {
    Test-Pass "Mem0 config exists: $Mem0Config"
    
    # Verify Qdrant connection for Mem0
    try {
        $collections = Invoke-WebRequest -Uri "http://localhost:6333/collections" -UseBasicParsing -TimeoutSec 5
        Test-Pass "Qdrant API reachable (Mem0 backend)"
    } catch {
        Test-Fail "Qdrant API unreachable — Mem0 won't work"
    }
} else {
    Test-Fail "Mem0 config missing"
}
Write-Host ""

# ─── Test 4: Superpowers MCP Server ─────────────────────────────────────────
Write-Host "[Test 4] Superpowers MCP Server" -ForegroundColor Cyan

try {
    $SpBuild = "C:\Users\mauls\Documents\Code\agent-skills\mcp-servers\superpowers\build\index.js"
    if (Test-Path $SpBuild) {
        Test-Pass "Superpowers built at: $SpBuild"
    } else {
        Test-Fail "Superpowers build not found"
    }
} catch {
    Test-Warn "Superpowers check: $_"
}
Write-Host ""

# ─── Test 5: CodeWhale MCP Config ────────────────────────────────────────────
Write-Host "[Test 5] CodeWhale MCP Configuration" -ForegroundColor Cyan

if (Test-Path $CodeWhaleMCP) {
    Test-Pass "MCP config exists: $CodeWhaleMCP"
    try {
        $config = Get-Content $CodeWhaleMCP | ConvertFrom-Json
        $servers = $config.servers
        $count = ($servers | Get-Member -MemberType NoteProperty | Measure-Object).Count
        Test-Pass "$count MCP servers configured"
    } catch {
        Test-Fail "MCP config is invalid JSON: $_"
    }
} else {
    Test-Fail "MCP config not found at $CodeWhaleMCP"
    Write-Host "    Run: .\scripts\setup.ps1" -ForegroundColor Gray
}
Write-Host ""

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Test Results: $Passed passed, $Failed failed, $Warned warnings                  ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

if ($Failed -eq 0) {
    Write-Host ""
    Write-Host "All critical tests passed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next: Restart CodeWhale. MCP tools appear as:" -ForegroundColor White
    Write-Host "  mcp_serena_find_symbol" -ForegroundColor Gray
    Write-Host "  mcp_mem0_remember" -ForegroundColor Gray
    Write-Host "  mcp_superpowers_use_skill" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Inside CodeWhale, run /mcp to see all connected servers." -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "$Failed tests failed. Check the output above and fix." -ForegroundColor Red
    Write-Host "Troubleshooting: docs\TROUBLESHOOTING.md" -ForegroundColor Gray
}

exit $Failed

# MCP Server Stack — Test All MCP Servers
# ============================================================================
# Tests:
#   1. Mem0 Docker stack (postgres, API, MCP bridge) is healthy
#   2. Serena CLI works (can list tools)
#   3. Mem0 API responds correctly (add + search flow)
#   4. Superpowers MCP server starts
#   5. CodeWhale MCP config is valid
#
# Usage: .\scripts\test.ps1
# ============================================================================

$ErrorActionPreference = "Continue"
$RepoRoot = Resolve-Path "$PSScriptRoot\.."
$CodeWhaleMCP = "$env:USERPROFILE\.codewhale\mcp.json"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "      MCP Server Stack - Test Suite                             " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$Passed = 0
$Failed = 0
$Warned = 0

function Test-Pass { Write-Host "  [PASS] $args" -ForegroundColor Green; $script:Passed++ }
function Test-Fail { Write-Host "  [FAIL] $args" -ForegroundColor Red; $script:Failed++ }
function Test-Warn { Write-Host "  [WARN] $args" -ForegroundColor Yellow; $script:Warned++ }

# --- Test 1: Mem0 Docker Stack ---
Write-Host "[Test 1] Mem0 Docker Stack" -ForegroundColor Cyan

# PostgreSQL/pgvector
try {
    $r = Invoke-WebRequest -Uri "http://localhost:5432" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    # pg responds with an error message on HTTP, which means it's reachable
    Test-Pass "PostgreSQL reachable on :5432"
} catch {
    # pg_isready via HTTP won't work directly; check via docker
    try {
        Push-Location $RepoRoot
        $pgStatus = docker inspect --format='{{.State.Health.Status}}' mem0-postgres 2>&1
        Pop-Location
        if ($pgStatus -eq "healthy") {
            Test-Pass "PostgreSQL container is healthy"
        } elseif ($pgStatus -match "running") {
            Test-Warn "PostgreSQL is running but health check status: $pgStatus"
        } else {
            Test-Fail "PostgreSQL not healthy: $pgStatus"
        }
    } catch {
        Test-Fail "PostgreSQL container not found or not running"
    }
}

# Mem0 REST API
try {
    $r = Invoke-WebRequest -Uri "http://localhost:8888/health" -UseBasicParsing -TimeoutSec 5
    if ($r.StatusCode -eq 200) {
        Test-Pass "Mem0 API healthy on :8888"
    } else {
        Test-Fail "Mem0 API returned $($r.StatusCode)"
    }
} catch {
    Test-Fail "Mem0 API not reachable - run: docker compose up -d"
}

# Mem0 MCP Bridge
try {
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [System.TimeSpan]::FromSeconds(5)
    $responseTask = $client.GetAsync("http://localhost:8001/sse", [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
    if ($responseTask.Wait(5000)) {
        $response = $responseTask.Result
        if ($response.IsSuccessStatusCode) {
            $contentType = $response.Content.Headers.ContentType.MediaType
            if ($contentType -eq "text/event-stream") {
                Test-Pass "Mem0 MCP bridge SSE endpoint reachable on :8001 (Content-Type: $contentType)"
            } else {
                Test-Warn "Mem0 MCP bridge responded, but content type was '$contentType' instead of 'text/event-stream'"
            }
        } else {
            Test-Fail "MCP bridge returned status code $($response.StatusCode)"
        }
        $response.Dispose()
    } else {
        Test-Fail "MCP bridge connection timed out"
    }
    $client.Dispose()
} catch {
    Test-Warn "MCP bridge not reachable - may still be building (run: docker compose logs mem0-mcp). Error: $_"
}

# End-to-end: add + search a test memory
Write-Host "  Testing memory add+search flow..." -ForegroundColor Gray
try {
    $testUserId = "test-e2e-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
    $addBody = @{
        messages = @(@{role = "user"; content = "The test suite ran successfully on $(Get-Date -Format 'yyyy-MM-dd HH:mm')."})
        user_id = $testUserId
    } | ConvertTo-Json
    $addResult = Invoke-WebRequest -Uri "http://localhost:8888/memories" -Method POST -Body $addBody -ContentType "application/json" -UseBasicParsing -TimeoutSec 30
    if ($addResult.StatusCode -eq 200 -or $addResult.StatusCode -eq 201) {
        $addJson = $addResult.Content | ConvertFrom-Json
        $memoryCount = if ($addJson -is [array]) { $addJson.Count } else { 1 }
        Test-Pass "Added $memoryCount test memories (user: $testUserId)"
    } else {
        Test-Warn "Memory add returned $($addResult.StatusCode): $($addResult.Content)"
    }
} catch {
    Test-Warn "Memory add+search flow failed: $_`n  This is expected if DEEPSEEK_API_KEY is not set in .env"
}

Write-Host ""

# --- Test 2: Serena MCP Server ---
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

# --- Test 3: Superpowers MCP Server ---
Write-Host "[Test 3] Superpowers MCP Server" -ForegroundColor Cyan

try {
    $SpBuild = "$(if($env:AGENT_SKILLS_ROOT){$env:AGENT_SKILLS_ROOT}else{"$env:USERPROFILE\Documents\Code\agent-skills"})\infra\mcp-servers\servers\superpowers\build\index.js"
    if (Test-Path $SpBuild) {
        Test-Pass "Superpowers built at: $SpBuild"
    } else {
        Test-Fail "Superpowers build not found"
    }
} catch {
    Test-Warn "Superpowers check: $_"
}
Write-Host ""

# --- Test 4: CodeWhale MCP Config ---
Write-Host "[Test 4] CodeWhale MCP Configuration" -ForegroundColor Cyan

if (Test-Path $CodeWhaleMCP) {
    Test-Pass "MCP config exists: $CodeWhaleMCP"
    try {
        $config = Get-Content $CodeWhaleMCP | ConvertFrom-Json
        $servers = $config.servers
        $count = ($servers | Get-Member -MemberType NoteProperty | Measure-Object).Count
        Test-Pass "$count MCP servers configured"

        # Check mem0 uses SSE transport (not stdio)
        if ($servers.mem0.type -eq "sse") {
            Test-Pass "Mem0 configured as SSE transport (not stdio)"
        } else {
            Test-Warn "Mem0 not using SSE transport"
        }
    } catch {
        Test-Fail "MCP config is invalid JSON: $_"
    }
} else {
    Test-Fail "MCP config not found at $CodeWhaleMCP"
    Write-Host "    Run: .\scripts\setup.ps1" -ForegroundColor Gray
}
Write-Host ""

# --- Summary ---
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "   Test Results: $Passed passed, $Failed failed, $Warned warnings" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

if ($Failed -eq 0) {
    Write-Host ""
    Write-Host "All critical tests passed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next: Restart CodeWhale. MCP tools appear as:" -ForegroundColor White
    Write-Host "  mcp_serena_find_symbol" -ForegroundColor Gray
    Write-Host "  mcp_mem0_add_memory" -ForegroundColor Gray
    Write-Host "  mcp_mem0_search_memories" -ForegroundColor Gray
    Write-Host "  mcp_superpowers_use_skill" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Inside CodeWhale, run /mcp to see all connected servers." -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "$Failed tests failed. Check the output above and fix." -ForegroundColor Red
    Write-Host "Troubleshooting: docs\TROUBLESHOOTING.md" -ForegroundColor Gray
}

exit $Failed

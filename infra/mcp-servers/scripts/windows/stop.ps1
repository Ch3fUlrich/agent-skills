# MCP Server Stack — Stop Docker Services
# ============================================================================
# Stops the mem0 Docker stack, preserving data.
#
# Usage: .\scripts\stop.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path "$PSScriptRoot\.."

Write-Host "Stopping MCP Docker services..." -ForegroundColor Cyan
Push-Location $RepoRoot
docker compose stop
Pop-Location
Write-Host "Services stopped. Data preserved in .\data\" -ForegroundColor Green
Write-Host "Run .\scripts\start.ps1 to restart." -ForegroundColor Gray

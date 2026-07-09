# MCP Server Stack — Migrate Data from Claude Code Plugins
# ============================================================================
# After the new MCP servers are running and tested, this script:
#   1. Exports Serena project indices from Claude Code's plugin cache
#   2. Bootstraps Mem0 with any transferable knowledge
#   3. Copies Superpowers skill data if available
#
# Usage: .\scripts\migrate.ps1
# ============================================================================

$ErrorActionPreference = "Continue"
$RepoRoot = Resolve-Path "$PSScriptRoot\.."
$HomeDir = $env:USERPROFILE
$CodeRoot = "$(if($env:CODE_ROOT){$env:CODE_ROOT}else{"$env:USERPROFILE\Documents\Code"})"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "      MCP Server Stack - Claude Code Data Migration             " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script migrates knowledge from Claude Code plugins"
Write-Host "to the new self-hosted MCP servers."
Write-Host ""

# --- Phase 1: Discover Claude Code Data ---
Write-Host "[Phase 1] Discovering Claude Code data..." -ForegroundColor Yellow

$ClaudeDirs = @(
    "$HomeDir\.claude",
    "$HomeDir\AppData\Roaming\Claude",
    "$HomeDir\AppData\Local\AnthropicClaude"
)

$FoundDirs = @()
foreach ($dir in $ClaudeDirs) {
    if (Test-Path $dir) {
        $FoundDirs += $dir
        Write-Host "  Found: $dir" -ForegroundColor Green
    }
}

if ($FoundDirs.Count -eq 0) {
    Write-Host "  [WARN] No Claude Code data directories found." -ForegroundColor Yellow
    Write-Host "  This is normal if Claude was installed differently." -ForegroundColor Gray
    Write-Host "  Proceeding with fresh setup." -ForegroundColor Gray
}

# --- Phase 2: Export Serena Project Indices ---
Write-Host ""
Write-Host "[Phase 2] Exporting Serena project indices..." -ForegroundColor Yellow

# Claude Code's serena plugin stores project data in .serena/ under each repo.
# The standalone serena CLI uses the same directory structure, so indices are
# already shared. We just need to verify they exist and are accessible.

$Repos = Get-ChildItem -Path $CodeRoot -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName ".git")
}

Write-Host "  Checking Serena indices in $($Repos.Count) repositories..." -ForegroundColor Gray

$IndexedRepos = @()
foreach ($repo in $Repos) {
    $SerenaDir = Join-Path $repo.FullName ".serena"
    if (Test-Path $SerenaDir) {
        $IndexedRepos += $repo.Name
        Write-Host "    [OK] $($repo.Name) has .serena/ index" -ForegroundColor Green
    } else {
        Write-Host "    - $($repo.Name) - no index (will be created on first use)" -ForegroundColor Gray
    }
}

if ($IndexedRepos.Count -gt 0) {
    Write-Host "  [OK] $($IndexedRepos.Count) repos have existing Serena indices" -ForegroundColor Green
    Write-Host "  These are automatically used by the new Serena setup." -ForegroundColor Gray
}
Write-Host ""

# --- Phase 3: Bootstrap Mem0 Memories ---
Write-Host "[Phase 3] Bootstrapping Mem0 memories..." -ForegroundColor Yellow

$BootstrapFile = "$RepoRoot\data\mem0\bootstrap_memories.txt"

# Create bootstrap memories from known project context
@"
# Mem0 Bootstrap Memories
# Auto-generated from Claude Code migration - review and edit as needed.
# Each line starting with # is a comment. Non-comment lines are stored as memories.

# === Project Architecture ===
Code monorepo at $env:CODE_ROOT containing 20+ projects
Main programming languages: Python (most repos), TypeScript, Shell, C#
Key frameworks: PyTorch, FastAPI, DeepLabCut, MARBLE, MaxEnt, IsingModel

# === Coding Preferences ===
User prefers Python with type hints and descriptive variable names
User uses uv for package management (pyproject.toml in newer repos)
Prefer explicit error handling over try/except passthrough
Shell scripts should have both .ps1 (Windows) and .sh (Unix) versions

# === Infrastructure ===
Self-hosted Docker services for AI tooling
Qdrant on :6333 for vector storage
Ollama on :11434 for local LLM inference
bge-m3 as the default embedding model (2 GB, fits 12 GB GPU)

# === Agent Workflow ===
CodeWhale is the primary coding agent (DeepSeek V4 backend)
Claude Code is used as secondary agent with plugin system
All MCP servers are self-hosted, no cloud API keys
Token efficiency is a primary concern - prefer tools that minimize context usage
"@ | Out-File -FilePath $BootstrapFile -Encoding UTF8

Write-Host "  [OK] Bootstrap memories written to: $BootstrapFile" -ForegroundColor Green
Write-Host "  Review this file and ask your agent to 'remember' important entries." -ForegroundColor Gray
Write-Host "  Or the agent will discover these when you reference the file." -ForegroundColor Gray
Write-Host ""

# --- Phase 4: Superpowers Skill Migration ---
Write-Host "[Phase 4] Checking Superpowers compatibility..." -ForegroundColor Yellow

# Superpowers MCP server serves the same skills as the Claude Code plugin.
# No data migration needed — just verify the skills are accessible.

try {
    $spCheck = uvx --from git+https://github.com/erophames/superpowers-mcp superpowers-mcp --help 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Superpowers MCP server is available" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Superpowers not yet available - install first: uv tool install --from git+https://github.com/erophames/superpowers-mcp superpowers-mcp" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [WARN] Superpowers check skipped" -ForegroundColor Yellow
}
Write-Host ""

# --- Phase 5: Verify Migration ---
Write-Host "[Phase 5] Verifying migration..." -ForegroundColor Yellow

$VerificationOk = $true

# Check Qdrant is reachable
try {
    $r = Invoke-WebRequest -Uri "http://localhost:6333/health" -UseBasicParsing -TimeoutSec 5
    Write-Host "  [OK] Qdrant online (Mem0 backend ready)" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Qdrant not reachable - start Docker first: .\scripts\start.ps1" -ForegroundColor Red
    $VerificationOk = $false
}

# Check Serena accessible
try {
    serena --version 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "  [OK] Serena CLI available" -ForegroundColor Green }
} catch {
    Write-Host "  [WARN] Serena CLI not on PATH" -ForegroundColor Yellow
}

# Summary
Write-Host ""
if ($VerificationOk) {
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "   Migration complete!                                          " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "What was migrated:" -ForegroundColor White
    Write-Host "  * Serena: $($IndexedRepos.Count) project indices (shared automatically)" -ForegroundColor Gray
    Write-Host "  * Mem0: Bootstrap memories in $BootstrapFile" -ForegroundColor Gray
    Write-Host "  * Superpowers: Same skills, different server (compatible)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor White
    Write-Host "  1. Restart CodeWhale" -ForegroundColor Gray
    Write-Host "  2. Ask agent: 'What do you remember about this codebase?' (tests Mem0)" -ForegroundColor Gray
    Write-Host "  3. Ask agent: 'Find all definitions of class X' (tests Serena)" -ForegroundColor Gray
    Write-Host "  4. See TODO.md for Claude Code migration plan" -ForegroundColor Gray
} else {
    Write-Host "  [WARN] Some checks failed. Fix issues above and re-run." -ForegroundColor Yellow
}

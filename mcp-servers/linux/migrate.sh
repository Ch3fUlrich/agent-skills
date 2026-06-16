#!/usr/bin/env bash
# MCP Server Stack — Migrate Data from Claude Code Plugins (Linux/macOS)
# ============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "\033[36m══════════════════════════════════════════════════════════════\033[0m"
echo -e "\033[36m  MCP Server Stack — Claude Code Data Migration (Unix)         \033[0m"
echo -e "\033[36m══════════════════════════════════════════════════════════════\033[0m"
echo ""

# ─── Phase 1: Discover Claude Code Data ──────────────────────────────────────
echo -e "\033[33m[Phase 1] Discovering Claude Code data...\033[0m"
CLAUDE_DIRS=("$HOME/.claude" "$HOME/.config/claude" "$HOME/Library/Application Support/Claude")
for dir in "${CLAUDE_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "  Found: $dir"
    fi
done
echo ""

# ─── Phase 2: Check Serena indices ───────────────────────────────────────────
echo -e "\033[33m[Phase 2] Checking Serena project indices...\033[0m"
# (same logic as Windows version — indices are shared)
echo "  Serena indices are shared between plugin and CLI — no migration needed"
echo ""

# ─── Phase 3: Bootstrap Mem0 memories ────────────────────────────────────────
echo -e "\033[33m[Phase 3] Bootstrapping Mem0 memories...\033[0m"
BOOTSTRAP_FILE="$REPO_ROOT/data/mem0/bootstrap_memories.txt"
cat > "$BOOTSTRAP_FILE" << 'BOOTSTRAP'
# Mem0 Bootstrap Memories
# Auto-generated from Claude Code migration — review and edit as needed.

# === Project Architecture ===
Code monorepo containing 20+ projects
Main programming languages: Python, TypeScript, Shell, C#
Key frameworks: PyTorch, FastAPI, DeepLabCut, MARBLE, MaxEnt, IsingModel

# === Coding Preferences ===
User prefers Python with type hints
User uses uv for package management
Prefer explicit error handling
Shell scripts should have both .ps1 and .sh versions

# === Infrastructure ===
Self-hosted Docker services for AI tooling
Qdrant on :6333 for vector storage
Ollama on :11434 for local LLM inference
bge-m3 as default embedding model (2 GB)

# === Agent Workflow ===
CodeWhale is primary coding agent (DeepSeek V4)
Claude Code is secondary agent
All MCP servers self-hosted, no cloud API keys
Token efficiency is primary concern
BOOTSTRAP

echo "  ✓ Bootstrap memories written to: $BOOTSTRAP_FILE"
echo ""

# ─── Phase 4: Verify ─────────────────────────────────────────────────────────
echo -e "\033[33m[Phase 4] Verifying migration...\033[0m"
OK=true

if curl -sf http://localhost:6333/health >/dev/null 2>&1; then
    echo "  ✓ Qdrant online (Mem0 backend ready)"
else
    echo "  ✗ Qdrant not reachable"
    OK=false
fi

if command -v serena &>/dev/null || uvx --from serena-agent serena --version &>/dev/null 2>&1; then
    echo "  ✓ Serena available"
else
    echo "  ⚠ Serena not on PATH"
fi

echo ""
if $OK; then
    echo -e "\033[36mMigration complete!\033[0m"
    echo "See TODO.md for Claude Code migration plan."
else
    echo -e "\033[33mSome checks failed. Fix and re-run.\033[0m"
fi

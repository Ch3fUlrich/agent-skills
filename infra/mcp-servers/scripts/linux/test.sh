#!/usr/bin/env bash
# MCP Server Stack — Test All MCP Servers (Linux/macOS)
# ============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CODEWHALE_MCP="$HOME/.codewhale/mcp.json"

PASSED=0
FAILED=0
WARNED=0

pass()  { echo -e "  \033[32m✓ PASS: $*\033[0m"; ((PASSED++)); }
fail()  { echo -e "  \033[31m✗ FAIL: $*\033[0m"; ((FAILED++)); }
warn()  { echo -e "  \033[33m⚠ WARN: $*\033[0m"; ((WARNED++)); }

echo -e "\033[36m══════════════════════════════════════════════════════════════\033[0m"
echo -e "\033[36m  MCP Server Stack — Test Suite (Unix)                         \033[0m"
echo -e "\033[36m══════════════════════════════════════════════════════════════\033[0m"
echo ""

# ─── Test 1: Docker Services ─────────────────────────────────────────────────
echo -e "\033[36m[Test 1] Docker Services\033[0m"

if curl -sf http://localhost:6333/health >/dev/null 2>&1; then
    pass "Qdrant is healthy on :6333"
else
    fail "Qdrant is not reachable — run: docker compose up -d"
fi

if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    if curl -s http://localhost:11434/api/tags | grep -q "bge-m3"; then
        pass "Ollama running, bge-m3 model loaded"
    else
        warn "Ollama running, but bge-m3 not yet pulled"
    fi
else
    fail "Ollama is not reachable — run: docker compose up -d"
fi
echo ""

# ─── Test 2: Serena MCP Server ───────────────────────────────────────────────
echo -e "\033[36m[Test 2] Serena MCP Server\033[0m"

if command -v serena &>/dev/null; then
    pass "Serena CLI: $(serena --version 2>&1)"
elif uvx --from serena-agent serena --version &>/dev/null 2>&1; then
    pass "Serena works via uvx"
else
    fail "Serena not available"
fi
echo ""

# ─── Test 3: Mem0 Configuration ──────────────────────────────────────────────
echo -e "\033[36m[Test 3] Mem0 Configuration\033[0m"

if [ -f "$REPO_ROOT/config/mem0-config.yaml" ]; then
    pass "Mem0 config exists"
    if curl -sf http://localhost:6333/collections >/dev/null 2>&1; then
        pass "Qdrant API reachable (Mem0 backend)"
    else
        fail "Qdrant API unreachable"
    fi
else
    fail "Mem0 config missing"
fi
echo ""

# ─── Test 4: Superpowers MCP Server ──────────────────────────────────────────
echo -e "\033[36m[Test 4] Superpowers MCP Server\033[0m"

if uvx --from git+https://github.com/erophames/superpowers-mcp superpowers-mcp --version &>/dev/null 2>&1; then
    pass "Superpowers available via uvx"
elif command -v superpowers-mcp &>/dev/null; then
    pass "Superpowers installed"
else
    warn "Superpowers check — will use uvx on first launch"
fi
echo ""

# ─── Test 5: CodeWhale MCP Config ────────────────────────────────────────────
echo -e "\033[36m[Test 5] CodeWhale MCP Configuration\033[0m"

if [ -f "$CODEWHALE_MCP" ]; then
    pass "MCP config exists: $CODEWHALE_MCP"
    if command -v jq &>/dev/null; then
        count=$(jq '.servers | keys | length' "$CODEWHALE_MCP")
        pass "$count MCP servers configured"
    else
        warn "jq not installed — can't validate JSON"
    fi
else
    fail "MCP config not found at $CODEWHALE_MCP"
    echo "    Run: bash scripts/setup.sh"
fi
echo ""

# ─── Summary ─────────────────────────────────────────────────────────────────
echo -e "\033[36m══════════════════════════════════════════════════════════════\033[0m"
echo -e "\033[36m  Test Results: $PASSED passed, $FAILED failed, $WARNED warnings\033[0m"
echo -e "\033[36m══════════════════════════════════════════════════════════════\033[0m"

if [ "$FAILED" -eq 0 ]; then
    echo ""
    echo "All critical tests passed!"
    echo ""
    echo "Next: Restart CodeWhale. MCP tools appear as:"
    echo "  mcp_serena_find_symbol"
    echo "  mcp_mem0_remember"
    echo "  mcp_superpowers_use_skill"
else
    echo ""
    echo "$FAILED tests failed. Check output above."
    echo "Troubleshooting: docs/TROUBLESHOOTING.md"
fi

exit "$FAILED"

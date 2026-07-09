#!/usr/bin/env bash
# MCP Server Stack — Full Automated Setup (Linux)
# ============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CODEWHALE_MCP="$HOME/.codewhale/mcp.json"

echo -e "\033[36m======================================================================\033[0m"
echo -e "\033[36m  MCP Server Stack — Self-Hosted Setup (Linux)                         \033[0m"
echo -e "\033[36m======================================================================\033[0m"
echo ""

# ─── Prerequisites ────────────────────────────────────────────────────────────
echo -e "\033[33m[1/6] Prerequisites...\033[0m"
command -v docker &>/dev/null || { echo "  X Docker not found"; exit 1; }
command -v uv &>/dev/null || { curl -LsSf https://astral.sh/uv/install.sh | sh; export PATH="$HOME/.cargo/bin:$PATH"; }
command -v node &>/dev/null || { echo "  X Node.js not found"; exit 1; }
command -v ollama &>/dev/null && curl -sf http://localhost:11434/api/tags >/dev/null || { echo "  X Install Ollama: curl -fsSL https://ollama.com/install.sh | sh"; exit 1; }
echo -e "  \033[32mv All prerequisites met\033[0m"
echo ""

# ─── Data Dirs ────────────────────────────────────────────────────────────────
echo -e "\033[33m[2/6] Data directories...\033[0m"
mkdir -p "$REPO_ROOT/data/qdrant"
echo -e "  \033[32mv Ready\033[0m"
echo ""

# ─── Qdrant + bge-m3 ─────────────────────────────────────────────────────────
echo -e "\033[33m[3/6] Starting Qdrant + bge-m3...\033[0m"
cd "$REPO_ROOT" && docker compose up -d qdrant
for i in $(seq 1 30); do curl -sf http://localhost:6333/ >/dev/null && break; sleep 2; done
echo -e "  \033[32mv Qdrant ready\033[0m"
curl -s http://localhost:11434/api/tags | grep -q "bge-m3" || { echo -e "  \033[33m  Pulling bge-m3 (~2 GB)...\033[0m"; curl -s -X POST http://localhost:11434/api/pull -d '{"name":"bge-m3:latest"}' >/dev/null; }
echo -e "  \033[32mv bge-m3 ready\033[0m"
echo ""

# ─── Serena ───────────────────────────────────────────────────────────────────
echo -e "\033[33m[4/6] Installing Serena...\033[0m"
uv tool install serena-agent 2>/dev/null || true
echo -e "  \033[32mv Serena $(serena --version 2>&1)\033[0m"
echo ""

# ─── Superpowers ──────────────────────────────────────────────────────────────
echo -e "\033[33m[5/6] Installing Superpowers...\033[0m"
SP_DIR="$REPO_ROOT/superpowers"
if [ ! -f "$SP_DIR/build/index.js" ]; then
    git clone https://github.com/erophames/superpowers-mcp "$SP_DIR" 2>/dev/null
    cd "$SP_DIR" && npm install && npm run build
fi
echo -e "  \033[32mv Superpowers ready\033[0m"
echo ""

# ─── CodeWhale Config ─────────────────────────────────────────────────────────
echo -e "\033[33m[6/6] Configuring CodeWhale...\033[0m"
mkdir -p "$HOME/.codewhale"
cp "$REPO_ROOT/config/mcp.json" "$CODEWHALE_MCP"
echo -e "  \033[32mv MCP config deployed\033[0m"
echo ""

echo -e "\033[36m======================================================================\033[0m"
echo -e "\033[36m  Base setup complete!                                                 \033[0m"
echo -e "\033[36m======================================================================\033[0m"
echo ""
echo -e "\033[1mNext:\033[0m bash linux/init-serena-projects.sh"
echo "Then restart CodeWhale."

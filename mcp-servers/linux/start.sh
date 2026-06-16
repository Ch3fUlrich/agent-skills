#!/usr/bin/env bash
# MCP Server Stack — Start Services + Initialize New Repos (Linux)
# ============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "\033[36mStarting MCP services...\033[0m"

cd "$REPO_ROOT" && docker compose up -d 2>/dev/null

echo -n "  Waiting for Qdrant..."
for i in $(seq 1 30); do curl -sf http://localhost:6333/ >/dev/null && break; sleep 2; done
echo -e " \033[32mv ready on :6333\033[0m"

curl -sf http://localhost:11434/api/tags >/dev/null && echo -e "  \033[32mv Ollama ready on :11434\033[0m" || echo -e "  \033[33m! Ollama not responding\033[0m"

echo -e "  Checking for new repos..."
for repo in "$HOME/Documents/Code"/*/; do
    [ -d "$repo/.git" ] || continue
    [ -f "$repo/.serena/project.yml" ] && continue
    printf 'n\n%.0s' {1..5} | serena project create "$repo" --index 2>/dev/null && echo -e "    \033[32mv Indexed: $(basename "$repo")\033[0m"
done

echo ""
echo -e "\033[36mAll services running. Restart CodeWhale.\033[0m"

#!/usr/bin/env bash
# MCP Server Stack — Stop Docker Services (Linux/macOS)
# ============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Stopping MCP Docker services..."
cd "$REPO_ROOT"
docker compose stop
echo "Services stopped. Data preserved in ./data/"
echo "Run bash scripts/start.sh to restart."

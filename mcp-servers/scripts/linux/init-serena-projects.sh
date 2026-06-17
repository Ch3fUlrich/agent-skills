#!/usr/bin/env bash
# MCP Server Stack — Serena Project Initialization Script (Linux)
# ============================================================================
# Pre-creates and indexes Serena projects for all git repositories.
# Prevents repeated language server downloads on first code navigation.
#
# Usage: bash linux/init-serena-projects.sh
# ============================================================================
set -euo pipefail

CODE_ROOT="$HOME/Documents/Code"
echo -e "\033[36m======================================================================\033[0m"
echo -e "\033[36m  Serena — Initialize All Project Indices                             \033[0m"
echo -e "\033[36m======================================================================\033[0m"

COUNT=0
SKIPPED=0
ERRORS=0

for repo in "$CODE_ROOT"/*/; do
    [ -d "$repo/.git" ] || continue
    name=$(basename "$repo")
    echo -e "\033[33m[$((COUNT + 1))] $name...\033[0m"
    
    if [ -f "$repo/.serena/project.yml" ]; then
        serena project index "$repo" 2>/dev/null && SKIPPED=$((SKIPPED + 1)) && echo -e "  \033[32mv Updated\033[0m" || true
    else
        printf 'n\n%.0s' {1..5} | serena project create "$repo" --index 2>/dev/null && COUNT=$((COUNT + 1)) && echo -e "  \033[32mv Created + indexed\033[0m" || { ERRORS=$((ERRORS + 1)); echo -e "  \033[31mX Error\033[0m"; }
    fi
done

echo ""
echo -e "\033[36mComplete: $COUNT new, $SKIPPED updated, $ERRORS errors\033[0m"

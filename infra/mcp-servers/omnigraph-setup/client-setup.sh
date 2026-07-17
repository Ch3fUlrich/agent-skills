#!/usr/bin/env bash
# client-setup.sh — configure a device to use the Omnigraph memory server.
#
#   --mode online   (default) register the omnigraph MCP against the central
#                   server; the agent works on `main` directly. Nothing to sync.
#   --mode offline  bring up a LOCAL stack and install the sync timer so the
#                   agent works on local `main` and reconciles when online.
#
#   --url    <URL>     central server URL (e.g. https://omnigraph.ohje.ooguy.com)
#   --token  <BEARER>  central bearer token
#
# Examples:
#   ./client-setup.sh --mode online  --url https://omnigraph.ohje.ooguy.com --token $TOK
#   ./client-setup.sh --mode offline --url https://omnigraph.ohje.ooguy.com --token $TOK
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mode="online"; URL=""; TOKEN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) mode="$2"; shift 2;;
    --url) URL="$2"; shift 2;;
    --token) TOKEN="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$URL" ] && [ -n "$TOKEN" ] || { echo "need --url and --token" >&2; exit 2; }

register_mcp() {  # $1=OMNIGRAPH_URL $2=TOKEN
  echo "Register the 'omnigraph' MCP server with your agent, e.g. Claude Code:"
  echo
  echo "  OMNIGRAPH_URL=$1 OMNIGRAPH_TOKEN=$2 \\"
  echo "    npx -y @modernrelay/omnigraph-mcp   # (or add to your MCP config JSON)"
  echo
  if command -v claude >/dev/null 2>&1; then
    echo "Detected 'claude' — adding it now:"
    claude mcp add --scope user omnigraph \
      -e "OMNIGRAPH_URL=$1" -e "OMNIGRAPH_TOKEN=$2" \
      -- npx -y @modernrelay/omnigraph-mcp || echo "  (add it manually — see config/mcp-claude-code.json)"
  fi
}

case "$mode" in
  online)
    echo "== online client: use the central server's main branch directly =="
    register_mcp "$URL" "$TOKEN"
    echo "Done. The agent reads/writes central main. No sync needed while online."
    ;;
  offline)
    echo "== offline-capable client: local stack + auto-sync =="
    echo "1) Bring up the local Omnigraph stack (reference compose):"
    echo "   cd $here/.. && cp .env.example .env  # set MINIO/OMNIGRAPH secrets"
    echo "   docker compose --env-file .env.shared --env-file .env.client -f docker-compose.client.yml --profile offline up -d"
    echo
    echo "2) Point the agent's omnigraph MCP at the LOCAL server:"
    register_mcp "http://127.0.0.1:8080" "\${LOCAL_OMNIGRAPH_TOKEN}"
    echo
    echo "3) Write sync config and install the timer:"
    cat > "$here/.env" <<EOF
CENTRAL_URL=$URL
CENTRAL_TOKEN=$TOKEN
LOCAL_URL=http://127.0.0.1:8080
LOCAL_TOKEN=<your local server OMNIGRAPH_TOKEN>
GRAPH=memory
DEVICE=$(hostname)
EOF
    echo "   wrote $here/.env (fill LOCAL_TOKEN)."
    echo "   mkdir -p ~/.config/systemd/user"
    echo "   cp $here/omnigraph-sync.service $here/omnigraph-sync.timer ~/.config/systemd/user/"
    echo "   systemctl --user enable --now omnigraph-sync.timer"
    echo
    echo "The agent works on local main; omnigraph-sync reconciles with central when online."
    ;;
  *) echo "unknown --mode: $mode (online|offline)" >&2; exit 2;;
esac

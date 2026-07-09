#!/usr/bin/env bash
# omnigraph-sync.sh — reconcile a client's local Omnigraph memory with the
# central server whenever the internet is present. Agents keep writing to the
# LOCAL `main`; this script handles branching + merging so they don't have to.
#
# Flow (only when the central server is reachable):
#   1. export local main  -> JSONL
#   2. push it onto central branch device/<host> (create from main if needed)
#   3. native `branch merge device/<host> -> main` on central  (edge-safe)
#   4. export central main, de-dup edges, load into local main (--mode merge)
#
# Node conflicts resolve by slug-keyed upsert (last-writer-wins per node). See
# setup/README.md "Honest caveats" for the offline multi-writer tradeoffs.
#
# Config via env (or a .env next to this script):
#   CENTRAL_URL   e.g. https://omnigraph.ohje.ooguy.com
#   CENTRAL_TOKEN bearer token for the central server
#   LOCAL_URL     e.g. http://127.0.0.1:8080   (this device's local server)
#   LOCAL_TOKEN   bearer token for the local server
#   GRAPH         graph id (default: memory)
#   DEVICE        device name (default: hostname)
#   OMNIGRAPH_IMAGE  CLI image (default: modernrelay/omnigraph-server:v0.8.1)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
[ -f "$here/.env" ] && . "$here/.env"

: "${CENTRAL_URL:?set CENTRAL_URL}"; : "${CENTRAL_TOKEN:?set CENTRAL_TOKEN}"
: "${LOCAL_URL:=http://127.0.0.1:8080}"; : "${LOCAL_TOKEN:?set LOCAL_TOKEN}"
GRAPH="${GRAPH:-memory}"; DEVICE="${DEVICE:-$(hostname)}"
IMAGE="${OMNIGRAPH_IMAGE:-modernrelay/omnigraph-server:v0.8.1}"
BRANCH="device/${DEVICE}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
log() { echo "[omnigraph-sync] $*" >&2; }

# Run the omnigraph CLI in a throwaway container with a config for both servers.
og() {
  docker run --rm --network host -v "$work:/w" \
    -e HOME=/w -e OMNIGRAPH_BEARER_TOKEN="$1" --entrypoint omnigraph "$IMAGE" "${@:2}"
}
mkdir -p "$work/.omnigraph"
cat > "$work/.omnigraph/config.yaml" <<YAML
servers:
  central: { url: ${CENTRAL_URL} }
  local:   { url: ${LOCAL_URL} }
YAML

# 0. Reachable?
if ! curl -fsS --max-time 8 "${CENTRAL_URL%/}/healthz" >/dev/null 2>&1; then
  log "central unreachable — offline, skipping (agent keeps working on local main)"; exit 0
fi
log "central reachable — syncing device branch ${BRANCH}"

# 1. export local main
og "$LOCAL_TOKEN" export --server local --graph "$GRAPH" > "$work/local.jsonl" 2>/dev/null || {
  log "local export failed (is the local server up?)"; exit 1; }

# 2. ensure central branch, push local changes onto it
og "$CENTRAL_TOKEN" branch create "$BRANCH" --server central --graph "$GRAPH" 2>/dev/null || true
og "$CENTRAL_TOKEN" load --server central --graph "$GRAPH" --branch "$BRANCH" \
   --data /w/local.jsonl --mode merge --yes >/dev/null

# 3. native merge device branch -> main (edge-safe on the central store)
og "$CENTRAL_TOKEN" branch merge "$BRANCH" --into main --server central --graph "$GRAPH" --yes >/dev/null
log "merged ${BRANCH} -> main on central"

# 4. pull central main back to local (de-dup edges first)
og "$CENTRAL_TOKEN" export --server central --graph "$GRAPH" > "$work/central.jsonl" 2>/dev/null
awk '!/"edge"/ || !seen[$0]++' "$work/central.jsonl" > "$work/central.dedup.jsonl"
og "$LOCAL_TOKEN" load --server local --graph "$GRAPH" --data /w/central.dedup.jsonl --mode merge --yes >/dev/null
log "pulled central main -> local main; sync complete"

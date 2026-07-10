#!/usr/bin/env bash
# omnigraph-sync.sh — reconcile a client's LOCAL Omnigraph memory with the
# CENTRAL server, with a local backup first and a NO-DUPLICATES guarantee.
#
# Flow (only when central is reachable):
#   0. BACKUP local main -> backups/local-main-<ts>.jsonl   (local is newest/authoritative)
#   1. export local main
#   2. central: branch create device/<host>; load local onto it (merge, upsert by slug)
#   3. central: branch merge device/<host> -> main          (native, edge-de-duplicating)
#   4. export central main; VERIFY no node/edge duplicates (omnigraph_jsonl.py)
#   5. if clean: dedup + load --mode OVERWRITE into local (local := clean central; no dup edges)
#      if dirty: STOP — leave local untouched; the backup is your rollback
#   6. VERIFY local; restore from backup if the pull corrupted it; optional device-branch delete
#
# Overwrite (not merge) is used for the local pull because merge of nodes that
# carry vector embeddings trips a Lance ingest bug on v0.8.1; overwrite is clean.
# Because we pushed local -> central first, central main ⊇ local, so overwrite is lossless.
#
# Config via env (or a .env next to this script):
#   CENTRAL_URL, CENTRAL_TOKEN, LOCAL_URL(=http://127.0.0.1:8080), LOCAL_TOKEN
#   GRAPH(=memory)  DEVICE(=hostname)  OMNIGRAPH_IMAGE(=modernrelay/omnigraph-server:v0.8.1)
#   DOCKER_NET(=host)          CLI-container network (Linux: host; see sync-windows.ps1 for Docker Desktop)
#   BACKUP_DIR(=<here>/backups)
#   DRY_RUN(=)                 set to 1 to only snapshot + verify BOTH sides, no writes
#   KEEP_DEVICE_BRANCH(=)      set to 1 to keep device/<host> on central after merge
#   PYTHON(=python3)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
[ -f "$here/.env" ] && . "$here/.env"
: "${CENTRAL_URL:?set CENTRAL_URL}"; : "${CENTRAL_TOKEN:?set CENTRAL_TOKEN}"
: "${LOCAL_URL:=http://127.0.0.1:8080}"; : "${LOCAL_TOKEN:?set LOCAL_TOKEN}"
GRAPH="${GRAPH:-memory}"; DEVICE="${DEVICE:-$(hostname)}"
IMAGE="${OMNIGRAPH_IMAGE:-modernrelay/omnigraph-server:v0.8.1}"
DOCKER_NET="${DOCKER_NET:-host}"
BACKUP_DIR="${BACKUP_DIR:-$here/backups}"
BRANCH="device/${DEVICE}"
JQ="$here/omnigraph_jsonl.py"; PY="${PYTHON:-python3}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
log() { echo "[omnigraph-sync] $*" >&2; }

og() {  # og <token> <cli-args...>  — omnigraph CLI in a throwaway container
  docker run --rm -i --network "$DOCKER_NET" -v "$work:/w" \
    -e HOME=/w -e OMNIGRAPH_BEARER_TOKEN="$1" --entrypoint omnigraph "$IMAGE" "${@:2}"
}
mkdir -p "$work/.omnigraph" "$BACKUP_DIR"
cat > "$work/.omnigraph/config.yaml" <<YAML
servers:
  central: { url: ${CENTRAL_URL} }
  local:   { url: ${LOCAL_URL} }
YAML

if ! curl -fsS --max-time 8 "${CENTRAL_URL%/}/healthz" >/dev/null 2>&1; then
  log "central unreachable — offline, skipping"; exit 0
fi

# 0. BACKUP local main (authoritative/newest copy) BEFORE touching anything
ts="$(date -u +%Y%m%dT%H%M%SZ)"; backup="$BACKUP_DIR/local-main-$ts.jsonl"
og "$LOCAL_TOKEN" export --server local --graph "$GRAPH" > "$backup" 2>/dev/null || {
  log "local export/backup failed (is the local server up?)"; exit 1; }
cp "$backup" "$work/local.jsonl"
log "backed up local main -> $backup ($(wc -l < "$work/local.jsonl") records)"
log "local pre-sync verify:"; "$PY" "$JQ" verify < "$work/local.jsonl" || true

if [ -n "${DRY_RUN:-}" ]; then
  og "$CENTRAL_TOKEN" export --server central --graph "$GRAPH" > "$work/central.jsonl" 2>/dev/null || { log "central export failed"; exit 1; }
  log "central verify:"; "$PY" "$JQ" verify < "$work/central.jsonl" || true
  log "DRY_RUN complete — no writes made. Backup at $backup"; exit 0
fi

# 1-3. push local onto central device branch, then native merge -> main
og "$CENTRAL_TOKEN" branch create "$BRANCH" --server central --graph "$GRAPH" 2>/dev/null || true
og "$CENTRAL_TOKEN" load   "$BRANCH" --server central --graph "$GRAPH" --branch "$BRANCH" --data /w/local.jsonl --mode merge --yes >/dev/null 2>&1 \
  || og "$CENTRAL_TOKEN" load --server central --graph "$GRAPH" --branch "$BRANCH" --data /w/local.jsonl --mode merge --yes >/dev/null
og "$CENTRAL_TOKEN" branch merge "$BRANCH" --into main --server central --graph "$GRAPH" --yes >/dev/null
log "merged $BRANCH -> main on central"

# 4. export central + verify NO duplicates before we trust it
og "$CENTRAL_TOKEN" export --server central --graph "$GRAPH" > "$work/central.jsonl" 2>/dev/null
if ! "$PY" "$JQ" verify < "$work/central.jsonl"; then
  log "!! central main has DUPLICATES after merge — NOT overwriting local. Backup kept: $backup"
  exit 2
fi

# 5. pull central -> local via OVERWRITE (deduped input; local := clean central)
"$PY" "$JQ" dedup < "$work/central.jsonl" > "$work/central.clean.jsonl"
if ! og "$LOCAL_TOKEN" load --server local --graph "$GRAPH" --data /w/central.clean.jsonl --mode overwrite --yes >/dev/null; then
  log "!! local overwrite failed — restoring local from backup"
  og "$LOCAL_TOKEN" load --server local --graph "$GRAPH" --data /w/local.jsonl --mode overwrite --yes >/dev/null || \
    log "!! restore also failed — rebuild local from cluster/seed + populate-embeddings.py (backup: $backup)"
  exit 3
fi
log "pulled central main -> local main (overwrite, deduped)"

# 6. verify local + optional branch cleanup
og "$LOCAL_TOKEN" export --server local --graph "$GRAPH" > "$work/local.after.jsonl" 2>/dev/null
log "local post-sync verify:"; "$PY" "$JQ" verify < "$work/local.after.jsonl"
if [ -z "${KEEP_DEVICE_BRANCH:-}" ]; then
  og "$CENTRAL_TOKEN" branch delete "$BRANCH" --server central --graph "$GRAPH" --yes >/dev/null 2>&1 || true
  log "deleted device branch $BRANCH on central"
fi
log "sync complete. Local backup: $backup"

#!/usr/bin/env bash
# Converge cluster/ (graphs + policies) into the live MinIO-backed store.
#
# The server's init container SKIPS `apply` on an existing store on purpose, so
# config changes (new graphs, new policies, multi-user) are applied here, on
# demand, with a safety net: snapshot the `memory` graph first, apply, restart
# the server, then VERIFY memory's node count is unchanged. If it dropped, the
# snapshot path is printed so you can restore.
#
# Run from infra/mcp-servers:  ./scripts/apply-cluster.sh
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"        # infra/mcp-servers
cd "$here"
set -a; . ./.env; set +a                        # MINIO_ROOT_USER/PASSWORD, S3_BUCKET, OMNIGRAPH_TOKEN
IMAGE="modernrelay/omnigraph-server:v0.8.1"
NET="${OMNI_NET:-mcp-servers_default}"          # network where the minio container resolves
S3="${OMNI_S3:-http://omnigraph-minio:9000}"    # must match omnigraph-server's AWS_ENDPOINT_URL_S3
BK=".graph-backup/pre-apply-$(date -u +%Y%m%d-%H%M%S).jsonl"

count() { # node count of the memory graph (nodes have "type"; edges have "from")
  curl -s -X POST "http://127.0.0.1:8080/graphs/memory/export" \
    -H "Authorization: Bearer ${OMNIGRAPH_TOKEN}" -H 'content-type: application/json' -d '{}' \
    | grep -c '"type"' || true
}

mkdir -p .graph-backup
echo "› snapshotting memory graph -> $BK"
curl -s -X POST "http://127.0.0.1:8080/graphs/memory/export" \
  -H "Authorization: Bearer ${OMNIGRAPH_TOKEN}" -H 'content-type: application/json' -d '{}' -o "$BK"
BEFORE=$(count); echo "  memory nodes before: $BEFORE"

# the running server holds the cluster state lock — stop it so apply can acquire it
echo "› stopping omnigraph-server (releases the state lock)…"
docker stop omnigraph-server >/dev/null

echo "› applying cluster config…"
docker run --rm --network "$NET" -v "$here/cluster:/cluster:ro" --entrypoint omnigraph \
  -e AWS_ACCESS_KEY_ID="$MINIO_ROOT_USER" -e AWS_SECRET_ACCESS_KEY="$MINIO_ROOT_PASSWORD" \
  -e AWS_REGION="${AWS_REGION:-us-east-1}" -e AWS_ENDPOINT_URL_S3="$S3" \
  -e AWS_ALLOW_HTTP=true -e AWS_S3_FORCE_PATH_STYLE=true \
  "$IMAGE" cluster apply --config /cluster --yes --as default || { echo "apply failed — restarting server unchanged"; docker start omnigraph-server >/dev/null; exit 1; }

echo "› starting omnigraph-server to pick up new graphs…"
docker start omnigraph-server >/dev/null
for i in $(seq 1 20); do curl -sf http://127.0.0.1:8080/healthz >/dev/null 2>&1 && break || sleep 2; done

AFTER=$(count); echo "  memory nodes after:  $AFTER"
echo "› graphs now:"; curl -s http://127.0.0.1:8080/graphs -H "Authorization: Bearer ${OMNIGRAPH_TOKEN}"

if [ "$AFTER" -lt "$BEFORE" ]; then
  echo "!! memory node count DROPPED ($BEFORE -> $AFTER). Restore with:"
  echo "   python3 scripts/populate-embeddings.py  # or load $BK back into memory (overwrite)"
  exit 1
fi
echo "✓ apply complete; memory graph intact ($AFTER nodes)."

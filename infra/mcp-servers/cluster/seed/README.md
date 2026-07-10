# Initial memory seed

Bootstrap `Project`/`Decision`/`Rule`/`Convention`/`Component`/`Task` nodes for
the `memory` graph, one file per project. Idempotent by `slug` — load with
`merge` (re-running updates rather than duplicates).

| Seed | Source |
|---|---|
| `agent-skills.jsonl` | this repo's ADRs / README / docs |
| `homelab-server.jsonl` | the `Server` repo (edge / reverse-proxy / security model) |
| `basic-analysis.jsonl` | distilled from Mem0 (`user_id=basic-analysis`, 283 memories) |
| `invest.jsonl` | distilled from the `Invest` repo (Mem0 had no memories for it) |

Load one (Windows-safe stdin pattern — bind mounts mangle paths under Git Bash):

```bash
cd infra/mcp-servers; set -a; . ./.env.shared; set +a
docker run --rm -i --network mcp-server_mcp-net -e OMNIGRAPH_BEARER_TOKEN="$OMNIGRAPH_TOKEN" \
  --entrypoint sh modernrelay/omnigraph-server:v0.8.1 -c \
  'cat > /tmp/d.jsonl; omnigraph load --server http://omnigraph-server:8080 --graph memory --data /tmp/d.jsonl --mode merge --yes --json' \
  < cluster/seed/agent-skills.jsonl
```

Format: NDJSON — `{"type":"NodeType","data":{…}}` and
`{"edge":"EdgeType","from":"<slug>","to":"<slug>"}`. Schema:
`../../../../skills/structured-memory/references/schema.md`.

**Vector search:** `Decision` embeddings are intentionally NOT stored in these
seeds (they are large and regenerable). Populate them after loading with
[`../../scripts/populate-embeddings.py`](../../scripts/populate-embeddings.py)
(computes via the local Ollama, then `overwrite`-loads). Full detail:
[`../../docs/OMNIGRAPH-LOCAL-RUNBOOK.md`](../../docs/OMNIGRAPH-LOCAL-RUNBOOK.md) §4.

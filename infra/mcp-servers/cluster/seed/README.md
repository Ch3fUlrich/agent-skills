# Initial memory seed

Bootstrap `Project`/`Decision`/`Rule`/`Convention`/`Component`/`Task` nodes, **one
file per graph**. Idempotent by `slug` — load with `merge` (re-running updates
rather than duplicates).

**A seed file loads into the graph matching its file name**, never into a shared
one — that is what keeps projects isolated (`cluster.yaml` declares one graph per
repo). The `omnigraph-seed` compose service applies this mapping on every boot.

| Seed | Target graph | Source |
|---|---|---|
| `memory.jsonl` | `memory` | **globals only** — cross-project `Preference {scope: global}` |
| `agent-skills.jsonl` | `agent-skills` | this repo's ADRs / README / docs |
| `homelab-server.jsonl` | `homelab-server` | the `Server` repo (edge / reverse-proxy / security model) |
| `basic-analysis.jsonl` | `basic-analysis` | live graph export (the `basic-analysis` repo) |
| `invest.jsonl` | `invest` | live graph export (originally distilled from the `Invest` repo) |

> **Keep seeds in sync with live.** The loader merges by `@key(slug)`, so a seed
> that has fallen behind will **overwrite newer live values** on the next boot.
> Refresh from live before relying on them:
> `python3 ../../scripts/split-project-graph.py <project> --write-seed`.

Load one by hand (Windows-safe stdin pattern — bind mounts mangle paths under Git
Bash). Note `--graph` matches the file name:

```bash
cd infra/mcp-servers; set -a; . ./.env.shared; set +a
docker run --rm -i --network mcp-server_mcp-net -e OMNIGRAPH_BEARER_TOKEN="$OMNIGRAPH_TOKEN" \
  --entrypoint sh modernrelay/omnigraph-server:v0.8.1 -c \
  'cat > /tmp/d.jsonl; omnigraph load --server http://omnigraph-server:8080 --graph agent-skills --data /tmp/d.jsonl --mode merge --yes --json' \
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

# Omnigraph — Structured Memory Server

Omnigraph is the **default** memory layer for this stack: a lakehouse-native
graph engine with combined graph-traversal + vector + full-text retrieval,
backed by an S3-compatible store (MinIO here). It replaces Mem0 as the source of
truth for cross-project, cross-agent memory. See
[`../../../../docs/decisions/0001-omnigraph-over-mem0.md`](../../../../docs/decisions/0001-omnigraph-over-mem0.md)
for the rationale and the fallback plan, and the
[`structured-memory`](../../../../skills/structured-memory/SKILL.md) skill for the
usage protocol.

There is no source to build here — the server runs from the upstream image and
the MCP bridge runs via `npx`. This folder documents how they are wired into the
compose stack and the agent configs.

## Run the server (via the stack)

The `omnigraph-server` + `minio` + `minio-init` + `omnigraph-init` services are
defined in the **server** compose
[`../../docker-compose.server.yml`](../../docker-compose.server.yml):

```bash
cd infra/mcp-servers
cp .env.shared.example .env.shared    # OMNIGRAPH_TOKEN + S3_BUCKET
cp .env.server.example .env.server    # MINIO_ROOT_USER/PASSWORD, embeddings
docker compose --env-file .env.shared --env-file .env.server \
  -f docker-compose.server.yml up -d  # omnigraph-server :8080 + minio :9000/:9001 + viewer :8090
```

Verify:

```bash
curl -fsS http://localhost:8080/healthz     # server up (bypasses auth)
# authenticated call uses the bearer token:
curl -fsS -H "Authorization: Bearer $OMNIGRAPH_TOKEN" http://localhost:8080/graphs
```

Key facts (from Omnigraph `docs/user/deployment.md`, v0.8.1):

| Setting | Value |
|---|---|
| Image | `modernrelay/omnigraph-server:v0.8.1` (Docker Hub; the GHCR mirror is not public) |
| Bind | `OMNIGRAPH_BIND` (default `0.0.0.0:8080`) |
| Cluster source | `OMNIGRAPH_CLUSTER` — here `s3://$S3_BUCKET/cluster` |
| Auth | `OMNIGRAPH_SERVER_BEARER_TOKEN` (implicit `default` actor) |
| Storage | `AWS_*` contract → MinIO (`AWS_ENDPOINT_URL_S3=http://minio:9000`, `AWS_ALLOW_HTTP=true`, `AWS_S3_FORCE_PATH_STYLE=true`) |
| Health | `GET /healthz` (unauthenticated) |

## Cluster bootstrap & policy (important)

Omnigraph is **cluster-only boot**: the server serves a storage root only after a
cluster has been converged into it. The declared config lives in git at
[`../../cluster/`](../../cluster/) (`cluster.yaml` + `memory.pg`); the state
ledger lives in MinIO (the Terraform split). The compose stack does this
automatically via the `omnigraph-init` one-shot:

```bash
omnigraph cluster import --config /cluster --yes   # bootstrap state.json
omnigraph cluster apply  --config /cluster --yes   # create graphs + schema, write ledger
# then omnigraph-server --cluster s3://omnigraph/cluster serves it
```

`/healthz` is open; **all server-scoped/management and data-plane actions are
closed by default (HTTP 403) until an explicit policy bundle is applied** —
"the management surface is never exposed without operator opt-in". Applying that
policy bundle (granting the `default` actor access to the `memory` graph) and
expanding `memory.pg` to the full structured-memory schema is the next step; see
`skills/structured-memory/references/schema.md`. Until then the graph exists and
is reachable by direct store access
(`--store s3://omnigraph/cluster/graphs/memory.omni`) but not through the server
API.

## Embeddings (vector search)

The `memory` graph's embedding provider is **Ollama `nomic-embed-text` on
`cloud.vm`** (openai-compatible, 768-dim — matches `Vector(768)` in `memory.pg`).
Configured in `cluster/cluster.yaml`; the server resolves it at boot
(`OLLAMA_DUMMY_KEY` + the `cloud.vm` `extra_hosts` entry). Benchmarked CPU-only:
~360 ms cold, ~60 ms warm — comfortably within the 16-CPU container.

- The server calls the provider at **query time** for `nearest($v, "text")`
  auto-embedding, so vector search works even though boot doesn't require the
  endpoint (non-vector queries always work if `cloud.vm` is down).
- **Stored vectors are populated by supplying them in load data** — the simplest
  reliable path (the `omnigraph embed` CLI is a `--input/--output/--spec` file
  pipeline, not an in-place re-embed). Compute the embedding for each node's
  source text via the same endpoint and include it as the node's `embedding`
  field, then `load --mode merge`. The seed loader does this for `Decision`
  nodes, so semantic search is **live**: e.g. `search_decisions("why did we
  replace the memory system")` ranks the *omnigraph-over-mem0* decision first.
- To fall back to zero-dependency embeddings, set the provider `kind: mock` in
  `cluster.yaml` and re-apply.

Review embeddings / semantic search:
```bash
# via the stored query (server-side, uses the configured embedder)
curl -s -X POST -H "Authorization: Bearer $OMNIGRAPH_TOKEN" -H 'Content-Type: application/json' \
  -d '{"params":{"q":"how do we run agents remotely"}}' \
  http://localhost:8080/graphs/memory/queries/search_decisions
```

## Register the MCP bridge

[`@modernrelay/omnigraph-mcp`](https://www.npmjs.com/package/@modernrelay/omnigraph-mcp)
runs over stdio and exposes the graph's tools (`query`, `mutate`, `load`,
`schema_get`, `branches_*`, `snapshot`, `commits_*`) + resources. Required env:

| Var | Value |
|---|---|
| `OMNIGRAPH_BASE_URL` | the server URL (e.g. `http://omnigraph-server:8080`, `http://localhost:8080`, or the public URL) |
| `OMNIGRAPH_GRAPH_ID` | **`memory`** — required (server is cluster-only; the bridge refuses to start without it) |
| `OMNIGRAPH_TOKEN` | the bearer token |

**Hosts with Node** run it directly (see `config/mcp.json`, `config/mcp_antigravity.json`):

```json
"omnigraph": { "command": "npx", "args": ["-y", "@modernrelay/omnigraph-mcp"],
  "env": { "OMNIGRAPH_BASE_URL": "http://localhost:8080", "OMNIGRAPH_GRAPH_ID": "memory", "OMNIGRAPH_TOKEN": "${OMNIGRAPH_TOKEN}" } }
```

**Hosts without Node** (e.g. this coding VM) run the bridge in a container — build
[`../omnigraph-mcp/`](../omnigraph-mcp/) (`docker build -t omnigraph-mcp:latest
servers/omnigraph-mcp`) and use the docker-run form in `config/mcp-claude-code.json`.
For Claude Code, register it directly:

```bash
claude mcp add --scope user omnigraph -- \
  docker run -i --rm --network mcp-servers_default \
  -e OMNIGRAPH_BASE_URL=http://omnigraph-server:8080 \
  -e OMNIGRAPH_GRAPH_ID=memory -e OMNIGRAPH_TOKEN=<bearer> omnigraph-mcp:latest
claude mcp get omnigraph      # -> Status: Connected
```

Restart the agent so it loads the new MCP server at session start.

## Mem0 fallback (off by default)

Mem0 remains available for when Omnigraph is unavailable. Its services live under
`servers/_fallback/` and only start with the compose profile:

```bash
docker compose --profile mem0-fallback up -d   # postgres + mem0 API + mem0-mcp + dashboard
```

Then register an SSE MCP server at `http://localhost:8001/sse`. Prefer restoring
Omnigraph over running on the fallback — see the ADR switch-back criteria.

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

The `omnigraph-server` + `minio` + `minio-init` services are defined in
[`../../docker-compose.yml`](../../docker-compose.yml) and start by default:

```bash
cd infra/mcp-servers
cp .env.example .env    # set MINIO_ROOT_USER/PASSWORD, OMNIGRAPH_TOKEN, S3_BUCKET
docker compose up -d    # omnigraph-server (:8080) + minio (:9000/:9001)
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

## Register the MCP bridge

`@modernrelay/omnigraph-mcp` runs over stdio and bridges the server's
`schema / branches / queries / mutations / ingest` tools into the agent. It is
already registered in the config files under `config/`:

```json
"omnigraph": {
  "command": "npx",
  "args": ["-y", "@modernrelay/omnigraph-mcp"],
  "env": {
    "OMNIGRAPH_URL": "http://localhost:8080",
    "OMNIGRAPH_TOKEN": "${OMNIGRAPH_TOKEN}"
  }
}
```

> The `OMNIGRAPH_URL` / `OMNIGRAPH_TOKEN` env names follow the server's URL +
> bearer contract. Confirm the exact env/arg names the installed
> `@modernrelay/omnigraph-mcp` version expects during first bring-up (plan task
> B1) and adjust the three `config/*.json` files together if they differ.

Restart the agent so it loads the new MCP server at session start.

## Mem0 fallback (off by default)

Mem0 remains available for when Omnigraph is unavailable. Its services live under
`servers/_fallback/` and only start with the compose profile:

```bash
docker compose --profile mem0-fallback up -d   # postgres + mem0 API + mem0-mcp + dashboard
```

Then register an SSE MCP server at `http://localhost:8001/sse`. Prefer restoring
Omnigraph over running on the fallback — see the ADR switch-back criteria.

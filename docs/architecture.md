# Architecture

This repository has three pillars. The first two are content (skills and their
per-repo adapters); the third is a self-hosted runtime that agents connect to.

```text
skills/     ── reusable agent skills (single source of truth)
starters/   ── thin per-repo adapters that point at skills
infra/      ── self-hosted runtime
              ├── mcp-servers/    MCP stack (navigation, graph, memory, workflows)
              └── remote-access/  run/persist/reach agents (Herdr, Antigravity UI)
```

## MCP server stack (`infra/mcp-servers/`)

| Server | Transport | Role |
|---|---|---|
| Serena | stdio (`uvx`) | LSP semantic code navigation (symbols, refs, refactor) |
| Graphify | stdio (`uv`/Docker) | Auto-extracted **code-structure** graph |
| **Omnigraph** | stdio bridge (`@modernrelay/omnigraph-mcp`) → HTTP `:8080` | **Structured cross-project memory** (typed nodes; graph+vector+full-text) |
| Superpowers | stdio (`node`) | Disciplined workflow skills (TDD, debugging, planning) |
| Playwright | stdio (`npx`) | Browser automation |
| ~~Mem0~~ | SSE (profile `mem0-fallback`) | Fallback memory only (off by default) |

Memory vs code graph: **Graphify** answers "how is the code structured" (it
auto-extracts from source); **Omnigraph** answers "what did we decide and why"
(agents write typed memory explicitly). They are complementary, not redundant.

```text
Agent
 ├── Serena ─────────► source code (LSP)
 ├── Graphify ───────► graphify-out/graph.json (code structure)
 ├── Omnigraph ──────► omnigraph-server :8080 ──► MinIO (S3) :9000/:9001
 │     (structured memory: Project/Decision/Rule/Preference/Convention/...)
 │       └── vector search ──► Ollama nomic-embed-text (768-dim, cloud.vm)
 ├── Superpowers ────► workflow skills
 └── Playwright ─────► browser

omnigraph-viewer :8090 ──► omnigraph-server (read-only web UI over the API)
```

Default runtime = `docker compose up -d` (Omnigraph + MinIO + viewer). The Mem0
fallback starts only with `--profile mem0-fallback`. See
`docs/decisions/0001-omnigraph-over-mem0.md`.

### Omnigraph internals

Omnigraph is **cluster-only boot**: a declared cluster (`infra/mcp-servers/cluster/`
— `cluster.yaml` + `memory.pg` schema + Cedar `*.policy.yaml` + stored `queries/`)
is `import`+`apply`ed into the MinIO storage root (the state ledger), then
`omnigraph-server --cluster s3://…` serves it. The API is bearer-token protected;
management/data actions require the applied policy bundle. Vector columns
(`Vector(768)` on `Decision`) are populated by supplying embeddings in load data
or the `omnigraph embed` pipeline; the `search_decisions($q)` stored query does
`nearest($d.embedding, $q)`.

## Deployed topology (this homelab)

The authoritative instance runs on **`coding.vm`**, spun up from the single
source of truth `Server/server/coding/mcp-servers/docker-compose.yml` (which
references this repo's `cluster/` config + viewer image). It is exposed through
the OPNsense `os-caddy` reverse proxy:

| Host | Backend | Auth |
|---|---|---|
| `omnigraph.ohje.ooguy.com` | `coding.vm:8080` (API/MCP) | **bearer token only** — no Authelia (SSO would block programmatic clients) |
| `omnigraph-ui.ohje.ooguy.com` | `coding.vm:8090` (viewer) | Authelia SSO (admin) |
| `omnigraph-minio.ohje.ooguy.com` | `coding.vm:9001` (MinIO console) | Authelia SSO (admin) |

Clients: **online** = MCP → the public API on `main`; **offline-capable** = local
stack + `setup/omnigraph-sync.sh` timer that pushes to a `device/<host>` branch
and merges into `main` when reachable (`infra/mcp-servers/setup/`).

## Remote access (`infra/remote-access/`)

- **Herdr** — agent multiplexer: run/persist multiple agents, reattach over SSH
  or phone, agent-to-agent socket API. Recommended over raw tmux
  (`docs/decisions/0002-herdr-multiplexer.md`).
- **Antigravity remote UI** — streams the Antigravity IDE chat to a phone browser
  (a distinct, GUI-specific use case).

## Data & secrets

- `graphify-out/` and `infra/mcp-servers/data/` (Omnigraph/MinIO/Postgres) are
  generated and **untracked**.
- No personal absolute paths or secrets in tracked files. Paths come from
  `${AGENT_SKILLS_ROOT}` / `${CODE_ROOT}` / `${SERENA_HOME}` and `.env`
  (`.env.example` is the template).

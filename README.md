# Agent Skills

Reusable AI-agent skills, per-repo starter adapters, and a self-hosted MCP
runtime for coding agents — so useful workflows are reused across projects
instead of rediscovered in every new repository.

The repository is organized into **three pillars**:

```text
skills/     # Pillar 1 — reusable skills (each skill's SKILL.md is the source of truth)
starters/   # Pillar 2 — thin per-repo adapters that point at a skill
infra/      # Pillar 3 — self-hosted runtime (MCP stack + remote access)
prompts/    # standalone prompt templates (repo→spec, big-todo workflow, examples)
docs/       # architecture, agent-compatibility, decision records (ADRs)
```

See [`docs/architecture.md`](docs/architecture.md) for how the pieces fit and
[`CHANGELOG.md`](CHANGELOG.md) for what changed.

## Pillar 1 — Skills

| Skill | Purpose |
|---|---|
| [`coding-principles`](skills/coding-principles/SKILL.md) | Engineering baseline: DRY, TDD, single responsibility, document-the-why, changelog/ADR backtracking, MCP-first navigation. |
| [`structured-memory`](skills/structured-memory/SKILL.md) | Typed, cross-project, cross-agent memory on Omnigraph — recall at session start, persist durable decisions at end. |
| [`mcp-servers-setup`](skills/mcp-servers-setup/SKILL.md) | Configure and use the self-hosted MCP stack for token-efficient coding. |
| [`html-working-documents`](skills/html-working-documents/SKILL.md) | Self-contained HTML artifacts for planning, review, research, diagrams, reports, prototypes, and handoff. |

Each skill is self-contained: required `SKILL.md`, optional `agents/openai.yaml`,
`references/`, `scripts/`, `assets/`. Keep reusable detail in `references/` and
`SKILL.md` focused on when to use the skill and how to run it.

## Pillar 2 — Starters

Thin adapters to drop a skill into another repository. Add a short pointer to your
project's agent instruction file (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, …):

```markdown
For any implementation, refactor, or bugfix, follow the skill at
`skills/coding-principles/SKILL.md`.
```

Available: [`starters/coding-principles`](starters/coding-principles/),
[`starters/mcp-servers`](starters/mcp-servers/),
[`starters/html-working-documents`](starters/html-working-documents/). Starters
are pointers, never copies of the workflow — see
[`docs/agent-compatibility.md`](docs/agent-compatibility.md) for the native
instruction file each agent expects.

## Pillar 3 — Infrastructure (`infra/`)

A self-hosted stack that reduces token usage on code-heavy tasks and gives agents
persistent, structured memory. Runs on your own hardware; no OpenAI key required.

### MCP server stack (`infra/mcp-servers/`)

| Server | Role |
|---|---|
| [Serena](https://github.com/oraios/serena) | LSP semantic code navigation |
| [Graphify](https://github.com/safishamsi/graphify) | Auto-extracted code-structure graph |
| **[Omnigraph](https://github.com/ModernRelay/omnigraph)** | Structured cross-project memory (default), + MinIO object store |
| [Superpowers](https://github.com/erophames/superpowers-mcp) | Disciplined workflow skills |
| [Playwright](https://github.com/microsoft/playwright-mcp) | Browser automation |
| [Omnigraph viewer](infra/mcp-servers/servers/omnigraph-viewer/) | Read-only web UI for the memory graph (tabs, interactive graph, table, search) |
| Mem0 | Fallback memory only — off by default (`--profile mem0-fallback`) |

### Setup: there are TWO roles — pick yours

Everything lives in [`infra/mcp-servers/`](infra/mcp-servers/). There are **two
Docker Compose files** and **three env files**. You always load `.env.shared`
plus the one for your role.

| Role | Compose file | What it runs | Who runs it |
|---|---|---|---|
| **SERVER** | `docker-compose.server.yml` | the memory backend: `omnigraph-server` + `minio` + `omnigraph-viewer` | **one** always-on machine (e.g. a homelab VM) |
| **CLIENT** | `docker-compose.client.yml` | your agent's tools: `serena` (code nav), `graphify` image; optional offline-local memory | **every** developer machine |

`.env.shared` holds the two values that **connect** the roles —
`OMNIGRAPH_TOKEN` (clients authenticate with the same token) and `S3_BUCKET`.
Prerequisite: Docker. All commands run from `infra/mcp-servers/`.

**Step 0 — create your env files** (do this once, on both roles):

```bash
cd infra/mcp-servers
cp .env.shared.example .env.shared     # set OMNIGRAPH_TOKEN (openssl rand -hex 32) + S3_BUCKET
cp .env.server.example .env.server     # SERVER only: MinIO creds, embeddings
cp .env.client.example .env.client     # CLIENT only: CODE_ROOT, OMNIGRAPH_URL (= the server's URL)
```

**If you are the SERVER** — start the memory backend:

```bash
docker compose --env-file .env.shared --env-file .env.server \
  -f docker-compose.server.yml up -d
curl -fsS http://localhost:8080/healthz          # expect {"status":"ok",...}
```

**If you are a CLIENT** — start Serena, build the Graphify image, then point your
agent's `omnigraph` MCP at the server (`OMNIGRAPH_URL` in `.env.client`):

```bash
docker compose --env-file .env.shared --env-file .env.client \
  -f docker-compose.client.yml up -d                       # serena (SSE :9121)
docker compose --env-file .env.shared --env-file .env.client \
  -f docker-compose.client.yml --profile build build graphify   # stdio image
# register the MCP servers into your agent's config (config/*.json), then restart it.
# OFFLINE (optional): run a local memory the sync timer reconciles later:
#   … -f docker-compose.client.yml --profile offline up -d
```

> **Mem0 is retired** (Omnigraph replaced it — ADR 0001). It is off by default;
> start it only for the fallback with
> `-f docker-compose.server.yml --profile mem0-fallback up -d`.

Memory is **Omnigraph** by default: agents write typed `Decision / Rule /
Preference / Convention / Component / Task` nodes (see the `structured-memory`
skill) rather than Mem0's unstructured blobs. Real vector search uses a local
**Ollama `nomic-embed-text`** embedder (768-dim; no cloud key). Mem0 is retained
as a documented fallback — rationale in
[`docs/decisions/0001-omnigraph-over-mem0.md`](docs/decisions/0001-omnigraph-over-mem0.md).
Full setup and per-agent wiring:
[`infra/mcp-servers/README.md`](infra/mcp-servers/README.md).

**Client vs server, offline & auto-sync.** A server (always-on) owns the
authoritative `main`; online clients point their MCP straight at it, and
offline-capable clients run a local copy that a timer reconciles when the
internet returns — agents never manage branches themselves. See
[`infra/mcp-servers/setup/`](infra/mcp-servers/setup/).

**Deployed instance (this homelab).** The stack runs on `coding.vm` from the
single-source compose in
`Server/server/coding/mcp-servers/docker-compose.yml`, exposed through the
OPNsense/Caddy reverse proxy: `omnigraph.ohje.ooguy.com` (API, bearer token),
`omnigraph-ui.ohje.ooguy.com` (viewer, Authelia), `omnigraph-minio.ohje.ooguy.com`
(MinIO console, Authelia).

### Remote access & multi-agent (`infra/remote-access/`)

- **[Herdr](infra/remote-access/herdr/)** — recommended agent multiplexer: run and
  persist multiple agents, reattach over SSH or phone, agent-to-agent socket API
  (Linux/macOS/Windows). Supersedes raw tmux
  ([ADR 0002](docs/decisions/0002-herdr-multiplexer.md)).
- **[antigravity-remote-ui](infra/remote-access/antigravity-remote-ui/)** — stream
  the Antigravity IDE chat to a phone browser (a distinct GUI use case).

See [`infra/remote-access/README.md`](infra/remote-access/README.md) for when to
use which.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for conventions on adding skills and
starters. Decisions are recorded as ADRs under
[`docs/decisions/`](docs/decisions/); notable changes go in `CHANGELOG.md`.

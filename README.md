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

### Start here: the router (`repository-index`)

**[`skills/repository-index/SKILL.md`](skills/repository-index/SKILL.md) is the entry point
for every agent, and the one file to read before deciding how to do anything else.**

A skill an agent does not know about is a skill it will not load — and nothing announces the
omission. The work simply comes out worse: conventions re-derived that were already written
down, whole files read where a symbol lookup would do, and everything learned in the session
lost at the end. The router exists so that never depends on an agent happening to browse
`skills/`.

It answers three questions in one place:

| The router tells you | So an agent can |
|---|---|
| **Which MCP server answers which question** — omnigraph for memory, serena for code, graphify for blast radius, context7 for library docs, and what each *isn't* for | reach for the right tool instead of `Read`-ing whole files (Principle 6 of `coding-principles`, and where most of the token savings come from) |
| **Which skills are always-on vs. triggered** — `coding-principles` and `structured-memory` apply to *any* task; `html-working-documents` or the review swarm only when their trigger fires | stop treating the baseline as an escalation, and stop invoking heavy machinery for a one-line fix |
| **The routing decision tree** — session start (recall → activate → baseline), the task itself, then session end (verify → **persist**) | close the memory loop it opened, rather than letting recall shrink over time |

Triggers are **observable** ("diff touches > 3 files", "the answer would exceed ~100 lines of
markdown"), not vibes like "any complex task" — an agent can evaluate them without judgement
calls. Adding a skill without a router row means nobody routes to it, so
[`CONTRIBUTING.md`](CONTRIBUTING.md) makes the row part of adding the skill.

`skills/SYNC.md` is **not** a router — it is the vendoring ledger (upstream, licence, sync
date) for the borrowed skills.

| Skill | Purpose |
|---|---|
| [`repository-index`](skills/repository-index/SKILL.md) | **The router — read first.** Maps every MCP server and skill to the trigger that should load it. |
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
| **[Omnigraph](https://github.com/ModernRelay/omnigraph)** | Structured cross-project memory + MinIO object store |
| [Superpowers](https://github.com/erophames/superpowers-mcp) | Disciplined workflow skills |
| [Playwright](https://github.com/microsoft/playwright-mcp) | Browser automation |
| [Context7](https://context7.com/) | Advanced contextual retrieval for agents |
| Sentry | Runtime error debugging and early error detection (Default Observability) |
| Datadog | Cross-service context for distributed setups (Conditional Observability) |
| [Omnigraph viewer](infra/mcp-servers/servers/omnigraph-viewer/) | Read-only web UI for the memory graph (tabs, interactive graph, table, search) |

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

Memory is **Omnigraph**: agents write typed `Decision / Rule /
Preference / Convention / Component / Task` nodes (see the `structured-memory`
skill) rather than unstructured blobs. Real vector search uses a local
**Ollama `nomic-embed-text`** embedder (768-dim; no cloud key) — and is optional:
without it, recall degrades to graph traversal + scalar indexes. There is no
fallback memory layer; the stack requires Omnigraph — rationale in
[`docs/decisions/0001-omnigraph-over-mem0.md`](docs/decisions/0001-omnigraph-over-mem0.md).
Full setup and per-agent wiring:
[`infra/mcp-servers/README.md`](infra/mcp-servers/README.md).

> **Per-project graph isolation.** Every repo gets its **own** graph named after the
> repo folder; the shared **`memory`** graph holds **only** global-scope
> `Preference`s. Point a repo at its graph with `OMNIGRAPH_GRAPH_ID=<repo>` in a
> project-scoped `.mcp.json` — **one** bridge, no more. A bridge serves exactly one
> graph, so reading `memory` would need a second server; that was tried and removed
> on 2026-07-17, because `memory` holds just two global `Preference`s (TDD-by-default,
> MCP-first navigation) which are already Principles 2 and 6 of
> [`coding-principles`](skills/coding-principles/SKILL.md) — a whole MCP server to
> re-serve two lines was duplication. Keep the bearer out of the tracked file: use
> `"OMNIGRAPH_TOKEN": "${OMNIGRAPH_TOKEN}"` and export it, along with `OMNIGRAPH_NET`
> (the docker network differs per host). See this repo's own [`.mcp.json`](.mcp.json).
> A declared graph is not live until `infra/mcp-servers/scripts/apply-cluster.sh` runs —
> verify with `graphs_list` / `schema_get`, not by reading the config.
>
> **Wiring all of that up is one command** — it builds the bridge image, sets both env vars,
> removes any user-scope override, audits every repo's `.mcp.json`, and proves it by driving
> the real bridge:
> ```powershell
> cd infra/mcp-servers/omnigraph-setup
> .\setup-agent-memory.ps1 -Check    # diagnose  (./setup-agent-memory.sh --check)
> .\setup-agent-memory.ps1           # fix
> ```
> **If a graph ever looks empty, suspect config before data.** A same-named `omnigraph` in
> `~/.claude.json` (user scope) silently outranks a repo's `.mcp.json`: on 2026-07-17 one
> pinned to `memory` made every repo read the wrong graph, and an agent nearly rebuilt an
> intact 135-node graph on top of it. `0 rows except 2 Preferences` **is** the `memory`
> graph. `setup-agent-memory --check` detects exactly this.

**Client vs server, offline & auto-sync.** A server (always-on) owns the
authoritative `main`; online clients point their MCP straight at it, and
offline-capable clients run a local copy that a timer reconciles when the
internet returns — agents never manage branches themselves. See
[`infra/mcp-servers/omnigraph-setup/`](infra/mcp-servers/omnigraph-setup/).

**Deployed instance (this homelab).** The stack runs on `coding.vm` from the
single-source compose in
`Server/server/coding/mcp-servers/docker-compose.yml`, exposed through the
OPNsense/Caddy reverse proxy: `omnigraph.ohje.ooguy.com` (API, bearer token),
`omnigraph-ui.ohje.ooguy.com` (viewer, Authelia), `omnigraph-minio.ohje.ooguy.com`
(MinIO console, Authelia).

### Local AI stack (`infra/local-ai/`) — optional, but it powers memory search

A self-hosted LLM inference + UI + agent stack. **Optional**, with one important
exception: **its Ollama is the embedder Omnigraph uses.** The memory graph stores
`Vector(768)` embeddings from **`nomic-embed-text`** served on `:11434`, and that is what
makes `nearest()` semantic recall work. Without it nothing breaks — recall simply degrades
to graph traversal + full-text — but with it, "why did we replace the memory layer?" finds
the right `Decision` without you knowing its slug. It is CPU-fine (~360 ms cold, ~60 ms
warm) and needs no cloud key.

| Component | Why it earns its place |
|---|---|
| **Ollama** (`:11434`) | Serves `nomic-embed-text` → Omnigraph's vector search (above). Also runs chat/coding models locally — no key, no egress, works offline. |
| **LiteLLM** (`:4000`) | One OpenAI-compatible endpoint in front of many providers (Perplexity, OpenAI, Anthropic, local). Centralises keys, and lets `swarm-orchestration` route roles to different models without per-tool config. |
| **OpenHands** (`:3000`) | Browser-based SWE agent in a sandboxed runtime — a second opinion on agent execution; see `skills/swarm-orchestration/CUSTOM_ORCHESTRATION_VS_OPENHANDS.md` for how it compares to this repo's own orchestration. |
| **Open WebUI** (`:3131`) | Chat frontend over both Ollama and LiteLLM — for exploration that doesn't warrant a coding agent. |
| **ollama-agent** | Sandboxed sibling sharing the model dir — run a model in isolation without touching the serving instance. |

Setup: [`infra/local-ai/README.md`](infra/local-ai/README.md). The MCP stack does **not**
require it: no Postgres, no pgvector, no LLM API key anywhere in the memory path.

### Remote access & multi-agent (`infra/remote-access/`)

- **[Herdr](infra/remote-access/herdr/)** — recommended agent multiplexer: run and
  persist multiple agents, reattach over SSH or phone, agent-to-agent socket API
  (Linux/macOS/Windows). Supersedes raw tmux
  ([ADR 0002](docs/decisions/0002-herdr-multiplexer.md)).
- **[antigravity-remote-ui](infra/remote-access/antigravity-remote-ui/)** — stream
  the Antigravity IDE chat to a phone browser (a distinct GUI use case).

### Container Registry (Harbor)

This repository incorporates **Harbor**, an enterprise-class self-hosted container registry.
- Do **not** install the container registry on local developer machines.
- Harbor is designed to be hosted on your remote cloud server. 
- You can push built container images (e.g., your custom MCP servers or agent environments) to the remote Harbor registry and pull them wherever needed across your infrastructure.

See [`infra/remote-access/README.md`](infra/remote-access/README.md) for when to
use which.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for conventions on adding skills and
starters. Decisions are recorded as ADRs under
[`docs/decisions/`](docs/decisions/); notable changes go in `CHANGELOG.md`.

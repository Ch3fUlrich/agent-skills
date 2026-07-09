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
 ├── Omnigraph ──────► omnigraph-server :8080 ──► MinIO (S3) :9000
 │     (structured memory: Project/Decision/Rule/Preference/Convention/...)
 ├── Superpowers ────► workflow skills
 └── Playwright ─────► browser
```

Default runtime = `docker compose up -d` (Omnigraph + MinIO). The Mem0 fallback
starts only with `--profile mem0-fallback`. See
`docs/decisions/0001-omnigraph-over-mem0.md`.

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

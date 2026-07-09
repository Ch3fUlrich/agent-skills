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
| **[Omnigraph](https://github.com/ModernRelay/omnigraph)** | Structured cross-project memory (default) |
| [Superpowers](https://github.com/erophames/superpowers-mcp) | Disciplined workflow skills |
| [Playwright](https://github.com/microsoft/playwright-mcp) | Browser automation |
| Mem0 | Fallback memory only — off by default (`--profile mem0-fallback`) |

Quick start:

```bash
cd infra/mcp-servers
cp .env.example .env          # set MinIO creds, OMNIGRAPH_TOKEN, S3_BUCKET
docker compose up -d          # default: Omnigraph + MinIO
```

Memory is **Omnigraph** by default: agents write typed `Decision / Rule /
Preference / Convention / Component / Task` nodes (see the `structured-memory`
skill) rather than Mem0's unstructured blobs. Mem0 is retained as a documented
fallback — rationale in
[`docs/decisions/0001-omnigraph-over-mem0.md`](docs/decisions/0001-omnigraph-over-mem0.md).
Full setup and per-agent wiring:
[`infra/mcp-servers/README.md`](infra/mcp-servers/README.md).

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

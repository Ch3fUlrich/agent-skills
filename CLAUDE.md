# Claude Code Instructions

This repository stores reusable skills, per-repo starter adapters, and a
self-hosted MCP runtime. See [AGENTS.md](AGENTS.md) for the shared, agent-neutral
instructions — this file adds only Claude-specific notes.

Keep starters and root instruction files as **thin pointers**; a skill's
`SKILL.md` is the single source of truth (see
`skills/coding-principles/SKILL.md`, Principle 1).

## Skills to apply

- **Router — start here:** `skills/repository-index/SKILL.md` (which server/skill for
  which trigger). `skills/SYNC.md` is the vendoring ledger, not a router.
- Coding discipline: `skills/coding-principles/SKILL.md`
- Memory (recall at start, persist at end): `skills/structured-memory/SKILL.md`
  — and `skills/structured-memory/references/operations.md` for the Omnigraph
  operational rules/gotchas (read before any query/mutate/load/sync).
- HTML working documents: `skills/html-working-documents/SKILL.md`
- MCP stack usage: `skills/mcp-servers-setup/SKILL.md`
- Multi-agent orchestration: `skills/swarm-orchestration/SKILL.md`

## Claude-specific notes

- **This repo's MCP config is its own `.mcp.json`** (project scope), which pins the
  `omnigraph` bridge to the **`agent-skills`** graph. A project-scoped server overrides a
  same-named user-level one in `~/.claude.json` — that is how the repo gets its own graph
  instead of the machine-global default. `infra/mcp-servers/config/mcp-claude-code.json`
  is a *template* for wiring a machine up, not what this repo uses.
- **Restart to load MCP servers** — they only initialize at session start, and Claude Code
  prompts once to approve a project's `.mcp.json` servers.
- **Export `OMNIGRAPH_TOKEN` (and `OMNIGRAPH_NET`) before launching**, or `.mcp.json`
  resolves them to empty and memory silently does not work. See `AGENTS.md`.
- **A same-named server in `~/.claude.json` (user scope) SILENTLY WINS over this repo's
  `.mcp.json`.** On 2026-07-17 a user-scope `omnigraph` pinned to `graph_id: memory` with a
  hardcoded token overrode every repo's pin. Nothing errored — the bridge answered happily,
  just about the wrong graph — and an agent read `memory`'s two Preferences, concluded
  `basic-analysis` (135 nodes, perfectly intact) had been **wiped**, and began rebuilding it
  into the wrong graph. If a graph looks empty or unfamiliar, check for a user-scope
  override *before* believing it:
  ```bash
  python -c "import json,pathlib;print(sorted((json.loads((pathlib.Path.home()/'.claude.json').read_text()).get('mcpServers') or {})))"
  ```
  There must be **no** `omnigraph` in that list — this repo's `.mcp.json` provides it.
- The bridge runs via **docker**, not `npx`, because node/npx is absent on `coding.vm`.
  Docker works on every host that runs the stack **only after the image is built** — it is
  published to no registry, so `docker run` otherwise fails with `pull access denied for
  omnigraph-mcp`. Build it once per host:
  ```bash
  docker build -t omnigraph-mcp:latest infra/mcp-servers/servers/omnigraph-mcp
  ```
  Repos on a host that *has* Node may instead use the `npx` bridge (as `basic-analysis`
  does): it needs neither the image nor `OMNIGRAPH_NET`, since it reaches the published port
  on `localhost` rather than a container DNS alias.
- When updating a starter pack, keep the tool-specific entrypoints aligned with
  the shared guidance in `skills/` and with the full `SKILL.md`.

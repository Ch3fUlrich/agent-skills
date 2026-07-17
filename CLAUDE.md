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
- The bridge runs via **docker**, not `npx` — node/npx is absent on `coding.vm`, and
  docker works on every host that runs the stack.
- When updating a starter pack, keep the tool-specific entrypoints aligned with
  the shared guidance in `skills/` and with the full `SKILL.md`.

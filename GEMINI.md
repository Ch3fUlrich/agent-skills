# Gemini CLI Instructions

This repository stores reusable skills, per-repo starter adapters, and a
self-hosted MCP runtime. See [AGENTS.md](AGENTS.md) for the shared, agent-neutral
instructions — this file adds only Gemini-specific notes.

Keep starters and root instruction files as **thin pointers**; a skill's
`SKILL.md` is the single source of truth.

## Skills to apply

- **Router — start here:** `skills/repository-index/SKILL.md` (which server/skill for
  which trigger). `skills/SYNC.md` is the vendoring ledger, not a router.
- Coding discipline: `skills/coding-principles/SKILL.md`
- Memory (recall at start, persist at end): `skills/structured-memory/SKILL.md`
  — and `skills/structured-memory/references/operations.md` before any
  query/mutate/load/sync.
- HTML working documents: `skills/html-working-documents/SKILL.md`
- MCP stack usage: `skills/mcp-servers-setup/SKILL.md`
- Multi-agent orchestration: `skills/swarm-orchestration/SKILL.md`

## Memory

Each repo has its **own** Omnigraph graph named after the repo folder (this one:
`agent-skills`). A bridge serves exactly one graph, chosen by `OMNIGRAPH_GRAPH_ID` — set
it per project and never write this repo's data to the shared `memory` graph, which holds
only two global `Preference`s. Omnigraph is the only memory layer; there is no fallback
(ADR 0003). `OMNIGRAPH_TOKEN` and `OMNIGRAPH_NET` must be exported before launch — see
`AGENTS.md`.

## Gemini/Antigravity-specific notes

- MCP config for Google Antigravity: `infra/mcp-servers/config/mcp_antigravity.json`.
  Antigravity reads its global `mcp_config.json`; see
  `infra/mcp-servers/README.md` for the exact location and transport notes.
- That config is **global**, so it cannot pin a per-repo graph the way a project-scoped
  `.mcp.json` does. Set `OMNIGRAPH_GRAPH_ID` to the repo you are working in before
  launching Antigravity, or you will read and write the wrong graph.
- `.agents/AGENTS.md` in a target repo may define Antigravity swarm roles
  (`@architect` / `@engineer` / `@reviewer`). Prefer `skills/swarm-orchestration/SKILL.md`
  as the source of truth and keep that file a pointer.

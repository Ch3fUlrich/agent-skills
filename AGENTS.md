# Agent Instructions

This repository stores reusable AI-agent skills, per-repo starter adapters, and a
self-hosted MCP runtime. Keep starters and this file as **thin pointers** — a
skill's `SKILL.md` is the single source of truth; never copy its workflow here.

## Skills (source of truth in `skills/`)

- **Coding discipline** — for any implementation, refactor, or bugfix, follow
  `skills/coding-principles/SKILL.md` (DRY, TDD, single responsibility,
  document-the-why, changelog/ADR backtracking, MCP-first navigation).
- **Memory** — at session start and end, follow
  `skills/structured-memory/SKILL.md` to recall and persist typed, cross-project
  memory in Omnigraph. Before any Omnigraph query/mutate/load/sync, read
  `skills/structured-memory/references/operations.md` — the operational rules and
  gotchas (edge casing, insert-xor-delete, duplicate-edge handling, never
  overwriting shared `main`, lowercase slugs, `nomic-embed-text` embeddings) that
  keep the graph clean without troubleshooting.
- **HTML working documents** — for long planning, research, review, report,
  diagram, prototype, and handoff work, follow
  `skills/html-working-documents/SKILL.md`.
- **MCP stack usage** — `skills/mcp-servers-setup/SKILL.md`.

## Compatibility goal

Prefer broad, plug-and-play compatibility over a single-vendor setup. Provide the
native instruction file each agent expects and keep each adapter short. See
`docs/agent-compatibility.md`.

## Infrastructure

Self-hosted MCP runtime lives under `infra/` — `infra/mcp-servers/` (Serena,
Graphify, Omnigraph memory, Superpowers, Playwright) and
`infra/remote-access/` (Herdr multiplexer + Antigravity remote UI). See
`docs/architecture.md`.

We also use **Harbor** as a self-hosted container registry. 
- Do **not** install the Harbor registry locally on this device. 
- The container should be pushed to a remote cloud server where it acts as a centralized registry. Agents and deployment scripts can push/pull images to and from the remote Harbor instance whenever needed.

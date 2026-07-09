# Claude Code Instructions

This repository stores reusable skills, per-repo starter adapters, and a
self-hosted MCP runtime. See [AGENTS.md](AGENTS.md) for the shared, agent-neutral
instructions — this file adds only Claude-specific notes.

Keep starters and root instruction files as **thin pointers**; a skill's
`SKILL.md` is the single source of truth (see
`skills/coding-principles/SKILL.md`, Principle 1).

## Skills to apply

- Coding discipline: `skills/coding-principles/SKILL.md`
- Memory (recall at start, persist at end): `skills/structured-memory/SKILL.md`
- HTML working documents: `skills/html-working-documents/SKILL.md`
- MCP stack usage: `skills/mcp-servers-setup/SKILL.md`

## Claude-specific notes

- MCP config for Claude Code: `infra/mcp-servers/config/mcp-claude-code.json`
  (Serena, Playwright, Omnigraph, Superpowers, Graphify). Restart to load MCP
  servers — they only initialize at session start.
- When updating a starter pack, keep the tool-specific entrypoints aligned with
  the shared guidance in `skills/` and with the full `SKILL.md`.

# Gemini CLI Instructions

This repository stores reusable skills, per-repo starter adapters, and a
self-hosted MCP runtime. See [AGENTS.md](AGENTS.md) for the shared, agent-neutral
instructions — this file adds only Gemini-specific notes.

Keep starters and root instruction files as **thin pointers**; a skill's
`SKILL.md` is the single source of truth.

## Skills to apply

- Coding discipline: `skills/coding-principles/SKILL.md`
- Memory (recall at start, persist at end): `skills/structured-memory/SKILL.md`
- HTML working documents: `skills/html-working-documents/SKILL.md`
- MCP stack usage: `skills/mcp-servers-setup/SKILL.md`

## Gemini/Antigravity-specific notes

- MCP config for Google Antigravity: `infra/mcp-servers/config/mcp_antigravity.json`.
  Antigravity reads its global `mcp_config.json`; see
  `infra/mcp-servers/README.md` for the exact location and transport notes.

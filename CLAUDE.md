# Claude Code Instructions

This repository stores reusable skills and starter packs for AI coding agents.

When updating a starter pack, keep the tool-specific entrypoints aligned with the shared guidance in `skills/` and with the full skill under `skills/<skill-name>/SKILL.md`.

## Compatibility Goal

Prefer broad, plug-and-play compatibility over a single-vendor setup. If a workflow should work in multiple agents, provide the native instruction file each agent expects and keep each adapter short.

## HTML Working Documents

For long planning, research, review, report, diagram, prototype, and handoff work in this repository, follow the skill at `skills/html-working-documents/SKILL.md`.

## MCP Server Stack

This repository includes a self-hosted MCP server stack under `mcp-servers/`. See `mcp-servers/README.md` for setup and `starters/mcp-servers/` for per-repository installation.

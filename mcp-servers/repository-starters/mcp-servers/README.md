# MCP Server Stack — Repository Starter

Copy this directory into any repository to enable the self-hosted MCP server
stack (Serena + Mem0 + Superpowers) for that repo.

## What Gets Installed

| File | Purpose |
|---|---|
| `AGENTS.md` | Instructions for AGENTS.md-aware tools (Codex, etc.) |
| `CLAUDE.md` | Instructions for Claude Code |
| `.serena/project.yml` | Serena project config (optional, auto-detected without it) |
| `README.md` | This file |

## Prerequisites

The MCP servers must be set up first. From the parent `agent-skills/mcp-servers/`
directory:

```powershell
.\scripts\setup.ps1   # One-time setup
.\scripts\start.ps1   # Start Docker services
```

## What Agents Get

Once installed, agents using the MCP stack can:

- **Navigate code semantically** — Find symbols, references, and file structure
  without reading entire files (Serena)
- **Remember across sessions** — Store architectural decisions, user preferences,
  and code patterns for future use (Mem0)
- **Use disciplined workflows** — TDD, systematic debugging, brainstorming,
  and planning templates (Superpowers)

## Multi-Repo Setup

Serena auto-detects which repository you're working in via `--project-from-cwd`.
No per-repo configuration needed — just `cd` into any repo and the agent sees
only that repo's code.

For cross-repo references, add paths to `.serena/project.yml`:
```yaml
additional_workspace_folders:
  - ../../DeepLabCut    # Can read DeepLabCut code while working here
  - ../../AnimalClass   # Can read AnimalClass code while working here
```

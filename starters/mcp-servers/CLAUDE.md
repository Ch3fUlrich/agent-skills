# MCP Server Stack — CLAUDE.md

This repository is configured with a self-hosted MCP server stack. Three
servers are active when Claude Code connects:

| Server | Purpose |
|---|---|
| **Serena** | LSP-powered semantic code navigation, refactoring, and project memory |
| **Superpowers** | Disciplined workflow skills (TDD, debugging, planning, brainstorming) |
| **Mem0** | Persistent cross-session memory (uses SSE transport to bypass timeouts) |

> **IMPORTANT: Project Isolation for Mem0**
> To prevent cross-project memory spillover, you **MUST** always specify the project's folder name as the `user_id` when calling any Mem0 tools (e.g. `user_id="MaxEnt"`, `user_id="SERBRA"`, etc.).

---

## First-Time Setup (Per Repository)

When Claude Code first works in a repo, Serena must be configured:

1. **Activate the project**: Ask Claude to run `mcp_serena_activate_project`
   with the current directory. This creates `.serena/project.yml` and indexes
   the code.

2. **Onboard**: Ask Claude to run `mcp_serena_onboarding()`. This analyzes
   the project structure and creates memories.

3. **Verify**: `mcp_serena_find_symbol(name_path_pattern="main")` should
   return results.

After setup, Serena auto-activates on future sessions via `--project-from-cwd`
in the MCP config — no manual activation needed.

---

## Serena Tools (Code Navigation & Refactoring)

### Finding Code (replace file reads with these)

- `mcp_serena_find_symbol` — Search symbols by name path pattern
- `mcp_serena_get_symbols_overview` — File structure outline
- `mcp_serena_find_referencing_symbols` — All call sites / usages
- `mcp_serena_find_declaration` — Jump to definition
- `mcp_serena_find_implementations` — All implementations of an interface
- `mcp_serena_get_diagnostics_for_file` — IDE-level errors/warnings

**Rule**: Before reading a file to find something, use Serena. It returns
precise results in far fewer tokens. Use `find_symbol` with `depth=1` to
list a class's methods; add `include_body=True` only when you need code.

### Refactoring (LSP-safe, updates all references)

- `mcp_serena_rename_symbol` — Rename across entire codebase
- `mcp_serena_replace_symbol_body` — Replace a definition
- `mcp_serena_insert_after_symbol` — Add code after a symbol
- `mcp_serena_insert_before_symbol` — Add code before a symbol
- `mcp_serena_safe_delete_symbol` — Delete only if no remaining references

### Project Memory (persists across sessions)

- `mcp_serena_write_memory` / `mcp_serena_read_memory`
- `mcp_serena_list_memories` / `mcp_serena_edit_memory` / `mcp_serena_delete_memory`

**Rule**: After learning anything reusable (architecture, preferences,
patterns, build commands, test frameworks), store it with `write_memory`.

---

## Superpowers Tools (Workflows)

- `mcp_superpowers_use_skill "test-driven-development"` — Write tests first
- `mcp_superpowers_use_skill "systematic-debugging"` — Hypothesis-driven debugging
- `mcp_superpowers_use_skill "writing-plans"` — Structured implementation plans
- `mcp_superpowers_use_skill "brainstorming"` — Requirements and design exploration

**Rule**: For any multi-step task, activate the relevant workflow first.

---

## Token Savings

This stack reduces token usage by 40-60% compared to raw file reading and
session-from-scratch approaches. Serena's semantic tools return only the
code you need; Superpowers provides structure that prevents rework.

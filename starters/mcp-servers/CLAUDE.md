# MCP Server Stack — CLAUDE.md

This repository is configured with a self-hosted MCP server stack. Three
servers are active when Claude Code connects:

| Server | Purpose |
|---|---|
| **Serena** | LSP-powered semantic code navigation and refactoring (memory/config tools filtered out) |
| **Superpowers** | Disciplined workflow skills (TDD, debugging, planning, brainstorming) |
| **Mem0** | Unified persistent cross-session memory (uses stdio transport for robustness) |

> **IMPORTANT: Project Isolation for Mem0**
> To prevent cross-project memory spillover, you **MUST** always specify the project's folder name as the `user_id` when calling any Mem0 tools (e.g. `user_id="MaxEnt"`, `user_id="SERBRA"`, etc.).

---

## Setup & Verification

Serena automatically activates and indexes the workspace via the client's `--project-from-cwd` flag. No manual configuration is required.

To verify Serena and Mem0 connection:
```
# Verify Serena code navigation
mcp_serena_find_symbol(name_path_pattern="main")

# Verify Mem0 connection
mcp_mem0_get_memories(user_id="<current-repo-folder-name>")
```
If these return results, the stack is ready.

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

---

## Mem0 Tools (Unified Memory)

- `mcp_mem0_add_memory` — Store a fact, pattern, or decision
- `mcp_mem0_get_memories` — List all memories for this project
- `mcp_mem0_search_memories` — Retrieve memories by semantic query
- `mcp_mem0_delete_memory` — Remove a memory by its ID

**Rule**: After learning anything reusable (architecture, preferences,
patterns, build commands, test frameworks), store it with `mcp_mem0_add_memory` (always specify the project name as `user_id`).

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

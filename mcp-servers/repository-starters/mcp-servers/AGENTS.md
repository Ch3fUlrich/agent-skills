# MCP Server Stack — AGENTS.md

This repository is configured with a self-hosted MCP server stack for AI coding
agents. When working in this repo, the following tools are available:

## MCP Tools

### Serena — Semantic Code Navigation
- `mcp_serena_find_symbol` — Find definitions of functions, classes, variables
- `mcp_serena_find_references` — Find all call sites / usages of a symbol
- `mcp_serena_get_file_structure` — Get a tree view of a file's contents
- `mcp_serena_get_code_context` — Get code around a specific location
- `mcp_serena_activate_project` — Switch which project Serena indexes

**Use these instead of reading entire files.** When you need to find where
something is defined or who calls it, use Serena — it returns precise results
with 10-100x fewer tokens than reading files.

### Mem0 — Persistent Memory
- `mcp_mem0_remember` — Store a fact, decision, or pattern for future sessions
- `mcp_mem0_recall` — Retrieve relevant memories based on a query
- `mcp_mem0_search_memories` — Full-text search across all stored memories
- `mcp_mem0_get_all_memories` — List all stored memories
- `mcp_mem0_delete_memory` — Remove a specific memory

**Use these to avoid re-explaining context.** When you learn something important
about the codebase, user preferences, or architectural decisions, store it in
Mem0. Future sessions (by you or other agents) can recall it immediately.

### Superpowers — Disciplined Workflows
- `mcp_superpowers_use_skill` — Activate a workflow (tdd, debug, brainstorm, plan)
- `mcp_superpowers_list_skills` — List available workflow skills

**Use these for complex tasks.** The TDD workflow ensures you write tests first.
The debug workflow guides systematic hypothesis testing. The plan workflow
structures brainstorming before implementation.

## Best Practices

1. **Read less code** — Use Serena tools instead of reading entire files
2. **Store what you learn** — Every significant discovery goes into Mem0
3. **Use workflows** — Complex tasks benefit from structured approaches
4. **Verify with evidence** — MCP tools return data, verify it before acting

## Token Efficiency

This stack reduces token usage by 40-60% on code-heavy tasks by replacing
brute-force file reads with targeted semantic queries, and by persisting
knowledge across sessions instead of re-learning it every time.

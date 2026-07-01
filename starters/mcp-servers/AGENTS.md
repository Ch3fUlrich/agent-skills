# MCP Server Stack — AGENTS.md

This repository is configured with a self-hosted MCP server stack for AI coding
agents. Four servers are active:

| Server | Purpose |
|---|---|
| **Serena** | LSP-powered semantic code navigation and refactoring (memory/config tools filtered out) |
| **Graphify** | Queryable project graph for code, docs, and cross-file relationships |
| **Superpowers** | Disciplined workflow skills (TDD, debugging, planning, brainstorming) |
| **Mem0** | Unified persistent cross-session memory (uses stdio transport for robustness) |

> **IMPORTANT: Project Isolation for Mem0**
> To prevent cross-project memory spillover, you **MUST** always specify the project's folder name as the `user_id` when calling any Mem0 tools (e.g. `user_id="MaxEnt"`, `user_id="SERBRA"`, etc.).

---

## First-Time Setup (Per Repository)

When starting in a new repository, Serena automatically activates and indexes the workspace via the client's `--project-from-cwd` flag. No manual project creation or activation is required.

Graphify does not need activation, but it does need a graph build. Run the repo-scoped Graphify initializer after Serena onboarding so `graphify-out/graph.json` exists for later sessions.

To verify Serena and Mem0 connection:
```
# Verify Serena code navigation
mcp_serena_find_symbol(name_path_pattern="main")

# Verify Mem0 connection
mcp_mem0_get_memories(user_id="<current-repo-folder-name>")
```
If these return results, the stack is ready.

---

## Serena Tools — Semantic Code Navigation

Use these **instead of reading entire files**. They return precise results with 10-100× fewer tokens.

### Finding and Understanding Code

| Tool | What it does |
|---|---|
| `mcp_serena_find_symbol` | Search for functions, classes, variables by name across the codebase |
| `mcp_serena_get_symbols_overview` | Get a structured outline of a file (all top-level symbols) |
| `mcp_serena_find_referencing_symbols` | Find every call site / usage of a symbol |
| `mcp_serena_find_declaration` | Jump to where a symbol is defined |
| `mcp_serena_find_implementations` | Find all implementations of an interface/abstract method |
| `mcp_serena_get_diagnostics_for_file` | Get IDE-level errors/warnings for a file |

**Pro tip**: Use `find_symbol` with `depth=1` to see a class's methods without reading the body. Use `include_body=True` only when you need the actual implementation.

### Editing and Refactoring

| Tool | What it does |
|---|---|
| `mcp_serena_rename_symbol` | Rename a symbol across the entire codebase (LSP-safe) |
| `mcp_serena_replace_symbol_body` | Replace a function/method/class definition |
| `mcp_serena_insert_after_symbol` | Add new code after a symbol (e.g., new method at end of class) |
| `mcp_serena_insert_before_symbol` | Add new code before a symbol |
| `mcp_serena_safe_delete_symbol` | Delete a symbol only if it has no remaining references |

---

## Mem0 Tools — Unified Persistent Memory

Mem0 is the single source of truth for persistent repository and user memory.

| Tool | What it does |
|---|---|
| `mcp_mem0_add_memory` | Store a fact, pattern, or decision about the project |
| `mcp_mem0_get_memories` | List all stored memories for this project |
| `mcp_mem0_search_memories` | Retrieve stored memories by semantic search query |
| `mcp_mem0_delete_memory` | Remove a memory by its ID |

**Use memories for**: architecture decisions, build commands, test patterns, user preferences, known pitfalls. Memories persist across sessions and agents.

## Graphify Tooling — Project Graphs

Use Graphify after Serena when you need relationship-level answers that span
multiple files, docs, or code paths.

| Tool | What it does |
|---|---|
| `graphify query` | Ask graph-level questions about the repo |
| `graphify path` | Find a path between concepts or symbols |
| `graphify explain` | Explain a node or cluster in graph terms |

**Rule**: If a repo has `graphify-out/graph.json`, prefer Graphify for broad structure questions before falling back to raw file reads.

---

## Superpowers Tools — Disciplined Workflows

| Tool | What it does |
|---|---|
| `mcp_superpowers_use_skill` | Activate a workflow by name |
| `mcp_superpowers_list_skills` | List all available skills |
| `mcp_superpowers_recommend_skills` | Get skill recommendations for a task |

Available skills: `brainstorming`, `test-driven-development`, `systematic-debugging`,
`writing-plans`, `executing-plans`, `subagent-driven-development`,
`requesting-code-review`, `receiving-code-review`, `finishing-a-development-branch`,
`dispatching-parallel-agents`, `verification-before-completion`, `using-git-worktrees`.

**Rule**: For multi-step tasks, activate the relevant workflow first instead of improvising.

---

## Best Practices

1. **Read less code, use Serena** — You **MUST** use Serena's `find_symbol` and `get_symbols_overview` instead of `read_file` or `grep_search` to understand codebase structure. Use `replace_symbol_body` and other Serena refactoring tools for code updates instead of generic file editing tools where possible.
2. **Store what you learn** — Every significant discovery, architecture pattern, or decision **MUST** go into `mcp_mem0_add_memory` (always specify the project name as `user_id`). Rely on Mem0 instead of keeping track in your scratchpad.
3. **Use workflows** — Complex tasks benefit from structured approaches via Superpowers.
4. **Verify with evidence** — Tool results are ground truth; verify before acting.

## Architecture and Implementation Rules

1. **Generalized Batch Processing** — When writing batch processing logic that iterates over a dataset (like sessions, animals, or subjects), use a generalized batch function that accepts a callable/function and parameters. This prevents duplicating nested loops and cleanly separates single-item logic from bulk processing boilerplate.
2. **Testing Importance** — Testing is strictly required. You must add tests when defining new functions, and you must rerun tests when updating existing functions. Test on both simulated data and against known baselines (if migrating code). Test coverage for modified modules should be nearly 100%.

# MCP Server Stack — AGENTS.md

This repository is configured with a self-hosted MCP server stack for AI coding
agents. Two servers are active:

| Server | Purpose |
|---|---|
| **Serena** | LSP-powered semantic code navigation, refactoring, and project memory |
| **Superpowers** | Disciplined workflow skills (TDD, debugging, planning, brainstorming) |

> **Mem0** (persistent cross-session memory) is **disabled** due to a CodeWhale
> hardcoded 120s MCP stdio timeout. Use Serena's `write_memory` / `read_memory`
> for project-scoped persistence instead.

---

## First-Time Setup (Per Repository)

When you first start working in a new repository, Serena needs to be set up.
Run these steps **once per repo**:

### Step 1: Create the Serena project
```
mcp_serena_activate_project(project=".")
```
This auto-detects the language, creates `.serena/project.yml`, and indexes
the codebase. If you need cross-repo references, edit `.serena/project.yml`
to add `additional_workspace_folders`.

### Step 2: Onboard Serena
```
mcp_serena_onboarding()
```
This analyzes the project structure (build system, test framework, entry
points) and creates memories so future sessions can start immediately.

### Step 3: Verify
```
mcp_serena_find_symbol(name_path_pattern="main")
mcp_serena_get_symbols_overview(relative_path="src")
```
If these return results, Serena is ready.

---

## Serena Tools — Semantic Code Navigation

Use these **instead of reading entire files**. They return precise results
with 10-100× fewer tokens.

### Finding and Understanding Code

| Tool | What it does |
|---|---|
| `mcp_serena_find_symbol` | Search for functions, classes, variables by name across the codebase |
| `mcp_serena_get_symbols_overview` | Get a structured outline of a file (all top-level symbols) |
| `mcp_serena_find_referencing_symbols` | Find every call site / usage of a symbol |
| `mcp_serena_find_declaration` | Jump to where a symbol is defined |
| `mcp_serena_find_implementations` | Find all implementations of an interface/abstract method |
| `mcp_serena_get_diagnostics_for_file` | Get IDE-level errors/warnings for a file |

**Pro tip**: Use `find_symbol` with `depth=1` to see a class's methods
without reading the body. Use `include_body=True` only when you need
the actual implementation.

### Editing and Refactoring

| Tool | What it does |
|---|---|
| `mcp_serena_rename_symbol` | Rename a symbol across the entire codebase (LSP-safe) |
| `mcp_serena_replace_symbol_body` | Replace a function/method/class definition |
| `mcp_serena_insert_after_symbol` | Add new code after a symbol (e.g., new method at end of class) |
| `mcp_serena_insert_before_symbol` | Add new code before a symbol |
| `mcp_serena_safe_delete_symbol` | Delete a symbol only if it has no remaining references |

### Project Memory

| Tool | What it does |
|---|---|
| `mcp_serena_write_memory` | Store a fact, pattern, or decision about the project |
| `mcp_serena_read_memory` | Retrieve a stored memory by name |
| `mcp_serena_list_memories` | List all stored memories |
| `mcp_serena_edit_memory` | Update a memory (regex search/replace) |
| `mcp_serena_delete_memory` | Remove a memory |

**Use memories for**: architecture decisions, build commands, test patterns,
user preferences, known pitfalls. Memories persist across sessions and agents.

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

**Rule**: For multi-step tasks, activate the relevant workflow first instead
of improvising.

---

## Best Practices

1. **Read less code** — Use Serena's `find_symbol` and `get_symbols_overview`
   instead of reading entire files with `read_file`.
2. **Store what you learn** — Every significant discovery goes into
   `mcp_serena_write_memory`.
3. **Use workflows** — Complex tasks benefit from structured approaches
   via Superpowers.
4. **Onboard once** — Run `mcp_serena_onboarding()` in every new repo.
   It takes 30 seconds and saves hours of re-discovery.
5. **Verify with evidence** — Tool results are ground truth; verify before acting.

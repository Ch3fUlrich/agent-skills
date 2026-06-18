---
name: mcp-servers-setup
description: Configure and use the self-hosted MCP server stack (Serena, Superpowers, Filesystem) for token-efficient coding. Mem0 is disabled due to CodeWhale timeout limitation.
---

# MCP Servers Setup

This skill ensures proper configuration and usage of the self-hosted MCP server
stack across all repositories in `C:\Users\mauls\Documents\Code`.

## First Action — Always

**On every session start (first prompt), activate the Serena MCP server and read project memories:**

```
mcp_serena_activate_project → (current project name or path)
mcp_serena_read_memory → "core"
```

This loads the full project context: module inventory, test counts, tech stack,
commands, constraints, and references to domain memories (e.g. `mem:architecture`,
`mem:api_design`). Do this before any code changes — the memories are the ground
truth for what exists and how it works.

## Active MCP Servers (3)

### Serena — Semantic Code Navigation (51 tools)

| Tool | Purpose | Token Savings |
|------|---------|:---:|
| `mcp_serena_find_symbol` | Find definitions | 90%+ vs file read |
| `mcp_serena_find_references` | Find all call sites | 80%+ vs multi-file read |
| `mcp_serena_get_symbols_overview` | Module structure | 95%+ vs full file read |
| `mcp_serena_search_for_pattern` | Regex search | 50%+ vs grep+read |
| `mcp_serena_write_memory` | Project-scoped notes | N/A |
| `mcp_serena_read_memory` | Read project notes | N/A |

**Usage**: Always activate the project first, then use symbolic tools:
```
mcp_serena_activate_project(project="agent-skills")
mcp_serena_find_symbol(name_path_pattern="function_name")
mcp_serena_find_references(name_path_pattern="ClassName", relative_path="src/")
```

**Project isolation**: Automatic via `.serena/project.yml` per repo.
Each repo gets its own language server indices.

**Serena memories** (`write_memory` / `read_memory`): Project-scoped notes
that persist within the project. Use these as a lightweight alternative to
Mem0 for storing architecture decisions, coding conventions, etc.

### Superpowers — Workflow Skills (14 skills)

| Skill | When to Use |
|-------|------------|
| `systematic-debugging` | Any bug, test failure, unexpected behavior |
| `test-driven-development` | Before writing implementation code |
| `brainstorming` | Before creative work, features, design |
| `writing-plans` | Multi-step tasks with specs |
| `requesting-code-review` | Before merging |
| `subagent-driven-development` | Independent parallel tasks |
| `verification-before-completion` | Before claiming work is done |

**Usage**:
```
mcp_superpowers_use_skill(name="systematic-debugging")
mcp_superpowers_recommend_skills(task="debug a timeout issue")
mcp_superpowers_compose_workflow(goal="add error handling to pipeline")
```

### Filesystem — Directory Operations (14 tools)

| Tool | Purpose |
|------|---------|
| `mcp_filesystem_directory_tree` | Recursive JSON tree (NOT in built-in tools) |
| `mcp_filesystem_read_multiple_files` | Batch file reads |
| `mcp_filesystem_search_files` | Glob search |
| `mcp_filesystem_get_file_info` | File metadata |

## Infrastructure

| Service | Address | Model(s) | Purpose |
|---------|---------|----------|---------|
| Qdrant | `:6333` | — | Vector store |
| Ollama | `:11434` | bge-m3 (566MB), qwen2.5:1.5b | Embedding + extraction |
| OLLAMA_KEEP_ALIVE=24h | Windows env | — | Keep models in VRAM |

## Project Initialization

```powershell
cd C:\Users\mauls\Documents\Code\agent-skills\mcp-servers
.\windows\start.ps1     # Start Qdrant, pre-warm Ollama models
.\windows\test.ps1      # Verify all services
```

## Recommended Workflow

1. Run `.\windows\start.ps1` to start services and pre-warm models
2. Activate Serena project: `mcp_serena_activate_project(project="repo-name")`
3. Use Serena for navigation, Superpowers for workflows, Filesystem for directory ops
4. End session: services keep running

## Troubleshooting

```powershell
# Full health check
.\windows\test.ps1

# Serena
serena project list
serena --version

# Qdrant
curl http://localhost:6333/

# Ollama
curl http://localhost:11434/api/tags
```

---
name: mcp-servers-setup
description: Configure and use the self-hosted MCP server stack (Serena, Superpowers, Mem0) for token-efficient coding.
---

# MCP Servers Setup

This skill ensures proper configuration and usage of the self-hosted MCP server
stack across all repositories in `C:\Users\mauls\Documents\Code`.

## First Action — Always

**On every session start (first prompt), activate the Serena MCP server and retrieve project memories from Mem0:**

```
mcp_serena_activate_project → (current project name or path)
mcp_mem0_get_memories(user_id="<current-repo-folder-name>")
```

This loads the full project context: module structure, recent decisions, commands, and constraints. Do this before any code changes — the memories are the ground truth for what exists and how it works.

## Active MCP Servers (3)

### Serena — Semantic Code Navigation (LSP)

| Tool | Purpose | Token Savings |
|------|---------|:---:|
| `mcp_serena_find_symbol` | Find definitions | 90%+ vs file read |
| `mcp_serena_find_referencing_symbols` | Find all call sites | 80%+ vs multi-file read |
| `mcp_serena_get_symbols_overview` | Module structure | 95%+ vs full file read |
| `mcp_serena_find_declaration` | Find where symbol is defined | 90%+ vs file read |

**Usage**: Always activate the project first, then use symbolic tools:
```
mcp_serena_activate_project(project="agent-skills")
mcp_serena_find_symbol(name_path_pattern="function_name")
```

**Project isolation & settings**: Automatic via `.serena/project.yml` per repo. If language detection fails, ensure `languages: ["python", "html", "typescript", "markdown", "scss", "yaml"]` is specified.

**Note**: Serena memory tools are disabled. Use Mem0 for all persistent memory instead.

### Mem0 — Persistent Cross-Session Memory

| Tool | Purpose |
|------|---------|
| `mcp_mem0_add_memory` | Store fact, design decision, preference |
| `mcp_mem0_get_memories` | Retrieve all memories for this repository |
| `mcp_mem0_search_memories` | Search memories semantically |

**Usage**:
```
mcp_mem0_add_memory(messages=[{"role": "user", "content": "Memory to store"}], user_id="basic-analysis")
mcp_mem0_get_memories(user_id="basic-analysis")
```
*Crucial*: Always use the folder name of the current repository as the `user_id` to maintain project isolation.

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
```

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

1. Run `.\windows\start.ps1` to start services and pre-warm models (Docker and Ollama)
2. Activate Serena project: `mcp_serena_activate_project(project="repo-name")`
3. Retrieve memories: `mcp_mem0_get_memories(user_id="repo-name")`
4. Use Serena for navigation, Mem0 for memories, and Superpowers for workflows
5. End session: services keep running

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

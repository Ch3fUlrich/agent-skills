---
name: mcp-servers-setup
description: Configure and use the self-hosted MCP server stack (Serena, Mem0, Superpowers) for token-efficient coding. Use when working in any repository under the Code monorepo to ensure Serena projects are indexed, Mem0 memories are project-isolated, and MCP tools are used optimally.
---

# MCP Servers Setup

This skill ensures proper configuration and usage of the self-hosted MCP server
stack across all repositories in `C:\Users\mauls\Documents\Code`.

## Available MCP Tools

### Serena — Semantic Code Navigation
- `mcp_serena_find_symbol` — Find definitions of functions, classes, variables
- `mcp_serena_find_references` — Find all call sites / usages
- `mcp_serena_get_symbols_overview` — Module structure without reading files
- `mcp_serena_find_declaration` — Get exact location + signature
- `mcp_serena_get_code_context` — Get code around a specific location
- `mcp_serena_find_file` — Find files by name/pattern

**Rule**: Use these for any code navigation task before reading files.
Serena returns precise results with 10-100x fewer tokens than file reads.

### Mem0 — Persistent Memory (Per-Project Isolated)
- `mcp_mem0_remember` — Store a fact or decision for future sessions
- `mcp_mem0_recall` — Retrieve relevant memories based on query
- `mcp_mem0_search_memories` — Full-text search
- `mcp_mem0_get_all_memories` — List all stored memories
- `mcp_mem0_delete_memory` — Remove a specific memory

**Critical: Project Isolation Rule**
All memories are tagged with `MEM0_USER_ID=mauls`. To prevent memory spilling
between projects, **ALWAYS include the repository/project name** in the first
sentence of every `remember("...")` call. This ensures `recall` finds only
the relevant memories for the current project.

Good examples:
```
remember("In project DeepLabCut, the training pipeline uses PyTorch Lightning with custom callbacks for logging")
remember("In MARBLE, the main data structure is a graph with node features and edge weights")
```

Bad examples (memories ambiguous between projects):
```
remember("The training pipeline uses PyTorch Lightning")  # Which project?!
remember("The main data structure is a graph")            # Which project?!
```

When using `recall`, include the project name in the query:
```
recall("DeepLabCut training pipeline architecture")
recall("MARBLE data structures")
```

### Superpowers — Disciplined Workflows
- `mcp_superpowers_use_skill` — Activate a workflow (tdd, debug, brainstorm, plan)
- `mcp_superpowers_list_skills` — List available workflow skills

**Rule**: For complex multi-step tasks, activate the relevant workflow first.

## Project Initialization

Serena creates project indices automatically via `--project-from-cwd`. All 35
repos under `C:\Users\mauls\Documents\Code` have been pre-indexed with language
servers downloaded. If a new repo is added, run:

```powershell
serena project create "C:\Users\mauls\Documents\Code\NEW_REPO_NAME" --index
```

Or use the automated script:
```powershell
cd C:\Users\mauls\Documents\Code\agent-skills\mcp-servers
.\windows\init-serena-projects.ps1
```

## Backend Infrastructure

| Service | Purpose | How to verify |
|---------|---------|--------------|
| **Qdrant** (:6333) | Vector database for Mem0 | `curl http://localhost:6333/` |
| **Ollama** (:11434) | Local embeddings (bge-m3) | `curl http://localhost:11434/api/tags` |

Both must be running before CodeWhale starts. Use `.\windows\start.ps1` to start.

## Recommended Workflow

1. **Start session**: Run `.\windows\start.ps1` (starts Qdrant, checks Ollama, indexes new repos)
2. **Open CodeWhale**: Navigate to the repo you're working on
3. **Navigation**: Use Serena tools instead of reading files
4. **Knowledge**: Store important findings in Mem0 with project context
5. **Workflows**: Use Superpowers for complex tasks (TDD, debug, plan)
6. **End session**: Knowledge persists in Mem0 for next session

---
name: mcp-servers-setup
description: Configure and use the self-hosted MCP server stack (Serena, Mem0, Superpowers, Filesystem) for token-efficient coding with per-project memory isolation. Use when working in any repository under the Code monorepo.
---

# MCP Servers Setup — Per-Project Isolated

This skill ensures proper configuration and usage of the self-hosted MCP server
stack across all repositories in `C:\Users\mauls\Documents\Code`.

**Key design principle**: Memories from repository A must never be visible
when working in repository B. Serena handles this automatically (per-repo
`.serena/` directories). Mem0 requires explicit `agent_id` scoping.

## Available MCP Tools

### Serena — Semantic Code Navigation (Auto-Isolated)

| Tool | Token Savings | Project Isolation |
|------|:---:|---|
| `mcp_serena_find_symbol` | 90%+ vs file read | Auto (`.serena/project.yml` per repo) |
| `mcp_serena_find_references` | 80%+ vs multi-file read | Auto |
| `mcp_serena_get_symbols_overview` | 95%+ vs full file read | Auto |
| `mcp_serena_find_declaration` | 90%+ vs manual search | Auto |
| `mcp_serena_find_file` | N/A | Auto |

**Rule**: Use these for any code navigation task before reading files.
Serena returns precise results with 10-100x fewer tokens than file reads.

Serena's `--project-from-cwd` detects the current repo via `.git` and loads
the correct `.serena/project.yml` index. No configuration needed per repo.
Each repo's language server indices are fully isolated.

### Mem0 — Persistent Memory (Agent-ID Isolated)

| Tool | Purpose |
|------|---------|
| `mcp_mem0_add_memory` | Store a fact or decision |
| `mcp_mem0_search_memories` | Semantic search across memories |
| `mcp_mem0_get_memories` | List all memories for a scope |
| `mcp_mem0_get_memory` | Fetch a single memory by ID |
| `mcp_mem0_delete_memory` | Remove a specific memory |
| `mcp_mem0_list_entities` | List which users/agents/runs have memories |

#### CRITICAL: Permanent Project Isolation Rule

**Every Mem0 tool call MUST include `agent_id` set to the current repository name.** This is the ONLY reliable isolation mechanism — the `MEM0_USER_ID=mauls` is shared globally, but `agent_id` provides per-project fencing.

**Determining the current repository name**:
- Read from `$env:PWD` or the active workspace path
- Extract the leaf directory name (e.g., `DeepLabCut`, `agent-skills`, `MARBLE`)
- ALWAYS include this as `agent_id` in every mem0 call

Correct usage (working in `DeepLabCut`):
```
add_memory(text="...", agent_id="DeepLabCut")
search_memories(query="...", agent_id="DeepLabCut")
get_memories(agent_id="DeepLabCut")
```

Working in `agent-skills`:
```
add_memory(text="...", agent_id="agent-skills")
search_memories(query="...", agent_id="agent-skills")
get_memories(agent_id="agent-skills")
```

**Verification**: After storing memories in a repo, search with the same
`agent_id` — you should see ONLY that repo's memories. Search with a
different `agent_id` — you should see zero results.

**!!! Never omit `agent_id` !!!** — doing so causes permanent cross-project
memory contamination that is very difficult to clean up.

### Superpowers — Disciplined Workflows

- `mcp_superpowers_use_skill` — Activate a workflow (tdd, debug, brainstorm, plan)
- `mcp_superpowers_list_skills` — List available skills (14 total)
- `mcp_superpowers_compose_workflow` — Multi-skill workflow for a goal
- `mcp_superpowers_recommend_skills` — Semantic skill matching

**Rule**: For complex multi-step tasks, activate the relevant workflow first.
14 skills available covering TDD, debugging, brainstorming, code review, and more.

### Filesystem — Recursive Directory Operations

- `mcp_filesystem_directory_tree` — Recursive JSON tree (not in CodeWhale's built-ins)
- `mcp_filesystem_read_multiple_files` — Batch file reads
- `mcp_filesystem_get_file_info` — File metadata
- `mcp_filesystem_search_files` — Glob search

## Project Initialization

Serena creates project indices automatically via `--project-from-cwd`. All
repos under `C:\Users\mauls\Documents\Code` can be indexed with:

```powershell
cd C:\Users\mauls\Documents\Code\agent-skills\mcp-servers
.\windows\init-serena-projects.ps1
```

Each repo gets its own `.serena/project.yml` — fully isolated.

## Backend Infrastructure

| Service | Address | Purpose | Start |
|---------|---------|---------|-------|
| Qdrant v1.18.2 | `:6333` | Vector store for Mem0 | `docker compose up -d qdrant` |
| Ollama (native) | `:11434` | LLM + embeddings | `ollama serve` |
| bge-m3 (566MB) | in Ollama | Embedding model | Pre-warmed on start |
| qwen2.5:1.5b (1GB) | in Ollama | Memory extraction | Pre-warmed on start |
| OLLAMA_KEEP_ALIVE=24h | env var | Keeps models in VRAM | Set by setup.ps1 |

## Recommended Workflow

1. **Start session**: `cd agent-skills/mcp-servers; .\windows\start.ps1`
2. **Open CodeWhale**: Navigate to the repo you're working on
3. **Determine repo name**: Extract from CWD (e.g., `basename $PWD`)
4. **Navigation**: Use Serena tools instead of reading files
5. **Memory**: Use Mem0 with `agent_id=<repo-name>`
6. **Workflows**: Use Superpowers for complex tasks
7. **End session**: Memories persist in Mem0 for next session

## Verification Commands

```powershell
# Run full test suite
cd agent-skills/mcp-servers
.\windows\test.ps1

# Serena project list
serena project list

# Mem0 entity isolation check (should show per-repo agent_ids)
# From CodeWhale: mcp_mem0_list_entities
# The result should show "agents" key with repo names

# Infrastructure health
curl http://localhost:6333/          # Qdrant: {"title":"qdrant - vector search engine"}
curl http://localhost:11434/api/tags # Ollama: models list

# Config validation
cat ~/.codewhale/mcp.json | python -m json.tool
```

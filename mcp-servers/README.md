# MCP Server Stack — Self-Hosted, No API Keys

A combined MCP server stack for CodeWhale that reduces token usage by
40–60% on code-heavy tasks through semantic navigation, persistent memory,
and disciplined coding workflows.

All servers are **fully self-hosted** — no cloud API keys, no external services.
Runs on your own hardware with Docker + uv + Node.js.

## Quick Start

```powershell
cd C:\Users\mauls\Documents\Code\agent-skills\mcp-servers
.\windows\setup.ps1
.\windows\init-serena-projects.ps1   # Pre-index all repos (one-time)
# Restart CodeWhale
```

Then run `.\windows\start.ps1` each session or after reboot to start Qdrant
and pre-warm Ollama models.

See [INSTALL-GUIDE.md](docs/INSTALL-GUIDE.md) for manual step-by-step setup.

## What's Inside

| MCP Server | Transport | Purpose | Token Savings |
|-----------|-----------|---------|:---:|
| [Serena](https://github.com/oraios/serena) | stdio (`uvx`) | LSP semantic code navigation — find symbols, references, structure without reading files | ~40–60% |
| [Mem0](https://github.com/elvismdev/mem0-mcp-selfhosted) | stdio (`uvx` from local patch) | Persistent cross-session memory — store and recall facts across sessions | Context reuse |
| [Superpowers](https://github.com/erophames/superpowers-mcp) | stdio (`node`) | Disciplined workflow skills — TDD, debugging, planning, brainstorming | Quality |
| [Filesystem](https://github.com/modelcontextprotocol/servers) | stdio (`cmd /c npx`) | Recursive `directory_tree`, batch reads, file metadata | ~5% |

> **Mem0 note**: Uses a locally patched version of `mem0-mcp-selfhosted` that
> fixes `search_memories` and `get_memories` for mem0ai v2.x. See `mem0-patched/patch.py`.

## How It Works

```
                    stdio (per-session)
  CodeWhale ────────────▶ serena-agent        ── LSP tools (51 tools)
  (or Claude Code) ─────▶ superpowers-mcp     ── workflow tools (14 skills)
                   ─────▶ mem0-mcp-selfhosted ── memory tools (11 tools)
                   ─────▶ filesystem MCP      ── file tools (14 tools)
                              │
            Docker (persistent)│
            ┌─────────────────┘
            ▼
      ┌──────────┐     ┌──────────────┐
      │ Qdrant   │     │  Ollama      │
      │ :6333    │     │  :11434      │
      │ vector   │     │  bge-m3      │
      │ store    │     │  qwen2.5:1.5b│
      └──────────┘     └──────────────┘
```

### Multi-Repo Support

Serena's `--project-from-cwd` auto-detects the active repository from `.git`.
All 35 repos under `C:\Users\mauls\Documents\Code` have been pre-indexed.

### Mem0 Project Isolation

All memories use `MEM0_USER_ID=mauls` (persistent Windows env var). The agent
skill at `skills/mcp-servers-setup/SKILL.md` instructs agents to always include
the repo name in memories — preventing spillover between projects.

## Requirements

| Component | Check | Install |
|-----------|-------|---------|
| Docker Desktop | `docker info` | `winget install Docker.DockerDesktop` |
| Native Ollama | `ollama list` or `curl :11434` | `winget install Ollama.Ollama` |
| uv (Python) | `uv --version` | `winget install --id=astral-sh.uv -e` |
| Node.js 18+ | `node --version` | `winget install OpenJS.NodeJS.LTS` |
| CodeWhale 0.8+ | `codewhale-tui --version` | `codewhale-tui update` |

## Repository Layout — File Tree with Explanations

```
mcp-servers/                          # Root: self-contained MCP server stack.
│                                     # Everything needed runs from this directory.
│
├── README.md                         # This file — overview, quick start, architecture.
├── docker-compose.yml                # Qdrant vector database (single Docker container).
│                                     # Mem0 stores embeddings here. Persistent volume
│                                     # at data/qdrant/. Uses native Ollama (outside
│                                     # Docker) on port 11434 for embeddings.
├── .env.example                      # Template for environment overrides.
│                                     # Copy to .env and adjust as needed.
├── TODO.md                           # Claude Code migration plan (5 phases).
│                                     # Step-by-step from "run both" to "only MCP".
│
├── windows/                          # Windows PowerShell scripts (pwsh.exe).
│   ├── setup.ps1                     # One-command setup: starts Qdrant, pulls bge-m3
│   │                                 # and qwen2.5, installs Serena + Superpowers,
│   │                                 # sets MEM0_USER_ID and OLLAMA_KEEP_ALIVE env vars,
│   │                                 # deploys MCP config to ~/.codewhale/mcp.json.
│   │                                 # Run once. Then run init-serena-projects.ps1.
│   ├── start.ps1                     # Daily startup: starts Qdrant, pre-warms Ollama
│   │                                 # models (bge-m3 + qwen2.5:1.5b), auto-indexes
│   │                                 # any new git repos with Serena. Run before
│   │                                 # CodeWhale each session.
│   ├── stop.ps1                      # Gracefully stops Qdrant (data preserved at
│   │                                 # data/qdrant/). Run when done for the day.
│   ├── test.ps1                      # Test suite: Qdrant health, Ollama models,
│   │                                 # Serena CLI, Superpowers build, MCP config
│   │                                 # validity, server count. Run after setup.
│   ├── init-serena-projects.ps1      # Scans all git repos under Code root, creates
│   │                                 # Serena project configs (.serena/project.yml),
│   │                                 # downloads language servers. Auto-answers "N"
│   │                                 # to language detection prompts. Run once;
│   │                                 # re-run when adding new repos.
│   └── migrate.ps1                   # Migrates knowledge from Claude Code plugins
│                                     # into Mem0 bootstrap memories. Generates
│                                     # data/mem0/bootstrap_memories.txt.
│
├── linux/                            # Linux/macOS Bash equivalents of all scripts above.
│   ├── setup.sh, start.sh, stop.sh
│   ├── test.sh, init-serena-projects.sh, migrate.sh
│
├── config/
│   ├── mcp.json                      # ⚠ ACTIVE CONFIG — deployed to ~/.codewhale/mcp.json.
│   │                                 # Defines 4 stdio MCP servers:
│   │                                 #   serena: uvx serena-agent (LSP, 240s timeout)
│   │                                 #   mem0:   uvx from local patch (memory, 180s)
│   │                                 #   superpowers: node build/index.js (14 skills)
│   │                                 #   filesystem: cmd /c npx (Windows workaround)
│   │                                 # After editing: `Copy-Item config\mcp.json ~\.codewhale\`
│   ├── mcp-claude-code.json          # Same servers formatted for Claude Code's MCP
│   │                                 # format (mcpServers key). Used in TODO.md Phase 4.
│   ├── mem0-config.yaml              # Reference only — mem0 reads env vars, not YAML.
│   │                                 # All active settings are in mcp.json's env block.
│   └── serena-project.yml            # Optional per-repo template. Copy to any repo's
│                                     # .serena/project.yml to add cross-repo workspace
│                                     # folders, language overrides, or ignore patterns.
│
├── mem0-patched/                     # ⚠ Locally patched mem0-mcp-selfhosted server.
│   │                                 # Fixes mem0ai v2.x compatibility: moves user_id
│   │                                 # into filters dict for search_memories and
│   │                                 # get_memories. See patch.py for the fix.
│   ├── patch.py                      # Python script that applies the patch to server.py.
│   ├── src/mem0_mcp_selfhosted/      # Patched source code.
│   │   ├── server.py                 # Main MCP server (patched for v2.x compat)
│   │   ├── config.py                 # Env-var based configuration
│   │   ├── helpers.py                # Utility functions (list_entities, safe_bulk_delete)
│   │   └── env.py                    # Env var reader
│   └── .venv/                        # uv-managed virtualenv (not tracked in git)
│
├── superpowers/                      # Node.js MCP server for coding workflows.
│   ├── build/index.js                # Compiled server binary (CodeWhale spawns this).
│   │                                 # Discovers 14 skills from Claude Code cache.
│   ├── src/                          # TypeScript source (read-only reference).
│   ├── package.json                  # v0.1.0, MIT license.
│   └── node_modules/                 # Node.js dependencies (not tracked in git).
│
├── docs/
│   ├── ARCHITECTURE.md               # Full system architecture: data flow, component
│   │                                 # details, security model.
│   ├── TOKEN_SAVINGS.md              # Detailed analysis: ~50% reduction, before/after
│   │                                 # examples for common coding tasks.
│   ├── TROUBLESHOOTING.md            # All known issues: port conflicts, PATH problems,
│   │                                 # timeout fixes, GPU detection, reset procedures.
│   └── INSTALL-GUIDE.md              # Manual step-by-step setup for humans.
│                                     # Includes prerequisite checks, server-by-server
│                                     # install, and a printable TODO checklist.
│
├── data/                             # Persistent runtime data (auto-created, not in git).
│   ├── qdrant/                       # Qdrant vector database — Mem0 embeddings stored here.
│   └── mem0/                         # Mem0 SQLite history + bootstrap memory files.
│
└── repository-starters/              # Copy these into new repos to enable MCP setup.
    └── mcp-servers/
        ├── AGENTS.md                 # MCP tool instructions for AGENTS.md-aware tools.
        ├── CLAUDE.md                 # Instructions for Claude Code agents.
        └── README.md                 # How to use the starter pack.
```

## Ollama Models

| Model | Size | Purpose |
|-------|------|---------|
| `bge-m3:latest` | 566 MB | Embedding generation for Mem0 vector search |
| `qwen2.5:1.5b` | ~1 GB | LLM-based memory extraction in Mem0 |
| `gemma4:e4b` | 9.6 GB | General-purpose (available but not used by MCP) |

Models are pre-warmed at startup (`start.ps1`) and kept in VRAM via
`OLLAMA_KEEP_ALIVE=24h` (persistent system env var).

## Environment Variables

| Variable | Value | Set By |
|----------|-------|--------|
| `MEM0_USER_ID` | `mauls` | `setup.ps1` — persistent user env var |
| `OLLAMA_KEEP_ALIVE` | `24h` | `setup.ps1` — keeps models in VRAM |

## Documentation

| Document | Description |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System architecture and data flow |
| [TOKEN_SAVINGS.md](docs/TOKEN_SAVINGS.md) | Token savings estimates |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues and fixes |
| [INSTALL-GUIDE.md](docs/INSTALL-GUIDE.md) | Manual step-by-step setup |
| [TODO.md](TODO.md) | Claude Code migration plan |
| `skills/mcp-servers-setup/SKILL.md` | Agent skill for proper MCP usage |

## Claude Code Migration

Currently Claude Code uses its own plugin system. See [TODO.md](TODO.md) for
the 5-phase migration to use the same MCP servers as CodeWhale.

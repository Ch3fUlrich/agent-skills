# MCP Server Stack — Self-Hosted, No API Keys

A combined MCP server stack for CodeWhale and Claude Code that reduces token
usage by 40–60% on code-heavy tasks through semantic navigation, persistent
memory, and disciplined coding workflows.

All servers are **fully self-hosted** — no cloud API keys, no external services.
Runs on your own hardware with Docker + uv/Python.

## Quick Start

```powershell
# Windows
cd C:\Users\mauls\Documents\Code\agent-skills\mcp-servers
.\windows\setup.ps1
.\windows\init-serena-projects.ps1   # Pre-index all repos (one-time)
# Restart CodeWhale
```

```bash
# Linux
cd ~/Documents/Code/agent-skills/mcp-servers
bash linux/setup.sh
bash linux/init-serena-projects.sh
```

Or follow the [Manual Installation Guide](docs/INSTALL-GUIDE.md) for step-by-step
instructions with explanations.

## What's Inside

| MCP Server | Purpose | Token Savings |
|-----------|---------|:---:|
| [Serena](https://github.com/oraios/serena) | LSP semantic code navigation | ~40–60% |
| [Mem0](https://github.com/elvismdev/mem0-mcp-selfhosted) | Persistent cross-session memory | Context reuse |
| [Superpowers](https://github.com/erophames/superpowers-mcp) | Disciplined workflow skills | Quality |
| [Filesystem](https://github.com/modelcontextprotocol/servers) | Recursive `directory_tree`, batch reads, file metadata | ~5% |

## How It Works

```
                    stdio (per-session)
  CodeWhale ────────────▶ serena-agent        ── LSP tools
  (or Claude Code) ─────▶ superpowers-mcp     ── workflow tools
                   ─────▶ mem0-mcp-selfhosted ── memory tools
                                                  │ HTTP
                          Docker (persistent)      │
                          ┌───────────────────────┘
                          │
                    ┌─────▼──────┐    ┌───────────┐
                    │  Qdrant    │    │  Ollama   │
                    │  :6333     │    │  :11434   │
                    │  vector DB │    │  bge-m3   │
                    └────────────┘    └───────────┘
```

### Multi-Repo Support

Serena's `--project-from-cwd` flag auto-detects which repository you're working
in by walking up from the current directory and finding `.git`. All 35 repos
have been pre-indexed with language servers downloaded — no repeated setup.

```
C:\Users\mauls\Documents\Code\
├── 2fast2mouse/       cd here → Serena sees 2fast2mouse
├── DeepLabCut/        cd here → Serena sees DeepLabCut
├── AnimalClass/       cd here → Serena sees AnimalClass
└── ...                (35 repos, all pre-indexed)
```

### Mem0 Project Isolation

All memories are partitioned by `MEM0_USER_ID=mauls`. The agent skill
(`agent-skills/skills/mcp-servers-setup/SKILL.md`) instructs the agent to
**always include the repo name** in memory operations — preventing ambiguity
between projects.

## Repository Layout — File Tree with Explanations

```
mcp-servers/                          # Root: self-contained MCP server stack
│
├── README.md                         # This file — overview & quick start
├── docker-compose.yml                # Qdrant vector database (Docker container).
│                                     # Mem0 stores embeddings here. Port 6333.
│                                     # Native Ollama (outside Docker) provides
│                                     # embeddings via bge-m3 on port 11434.
├── .env.example                      # Template for environment overrides.
│                                     # Copy to .env and adjust.
├── TODO.md                           # Claude Code migration plan (5 phases).
│                                     # Step-by-step from "run both" to "only MCP".
│
├── windows/                          # Windows PowerShell scripts (run from pwsh.exe)
│   ├── setup.ps1                     # One-command setup: starts Qdrant, pulls bge-m3,
│   │                                 # installs Serena + Superpowers, deploys MCP config.
│   │                                 # Run once. Then run init-serena-projects.ps1.
│   ├── start.ps1                     # Start Qdrant + check Ollama + auto-index new repos.
│   │                                 # Run daily or on reboot before CodeWhale.
│   ├── stop.ps1                      # Gracefully stop Qdrant (data preserved).
│   ├── test.ps1                      # 5-test suite: Qdrant health, Ollama models,
│   │                                 # Serena CLI, Superpowers, MCP config validity.
│   ├── init-serena-projects.ps1      # Scan all 35 repos under C:\Users\mauls\Documents\Code,
│   │                                 # create Serena project configs, download language
│   │                                 # servers (pyright, typescript-ls, etc.).
│   │                                 # Run once after setup; re-run when adding new repos.
│   └── migrate.ps1                   # Migrate knowledge from Claude Code plugins
│                                     # into the new MCP server stack (Serena indices
│                                     # are shared, Mem0 gets bootstrap memories).
│
├── linux/                            # Linux/macOS counterparts (Bash)
│   ├── setup.sh                      # Same logic as windows/setup.ps1
│   ├── start.sh                      # Qdrant + Ollama check + auto-index
│   ├── stop.sh                       # Stop Qdrant
│   ├── test.sh                       # 5-test suite (curl-based)
│   ├── init-serena-projects.sh       # Scan ~/Documents/Code, index all repos
│   └── migrate.sh                    # Claude Code → Mem0 bootstrap (Unix)
│
├── config/
│   ├── mcp.json                      # ⚠ ACTIVE CONFIG — deployed to ~/.codewhale/mcp.json.
│   │                                 # Defines 3 MCP servers for CodeWhale:
│   │                                 #   serena: uvx serena-agent with --project-from-cwd
│   │                                 #   mem0:   uvx mem0-mcp-selfhosted (env-var config)
│   │                                 #   superpowers: node build/index.js
│   │                                 # All config via env vars, no YAML files.
│   │                                 # After editing: Copy-Item to ~/.codewhale/mcp.json.
│   ├── mcp-claude-code.json          # Same 3 servers, but formatted for Claude Code's
│   │                                 # .claude/mcp.json format (mcpServers key instead of servers).
│   │                                 # Used in Phase 4 of TODO.md migration.
│   ├── mem0-config.yaml              # ⚠ DEPRECATED (kept for reference).
│   │                                 # mem0-mcp-selfhosted uses env vars only.
│   │                                 # See mcp.json "env" block for active settings.
│   └── serena-project.yml            # Optional per-repo Serena config template.
│                                     # Copy to any repo's .serena/project.yml to add
│                                     # additional_workspace_folders (cross-repo refs),
│                                     # language overrides, or custom ignore patterns.
│
├── superpowers/                      # Cloned + built Node.js MCP server.
│   ├── src/                          # TypeScript source (read-only reference)
│   ├── build/index.js                # The compiled server binary. CodeWhale spawns
│   │                                 # this via "node build/index.js" on demand.
│   │                                 # Discovered 14 skills from Claude Code cache.
│   ├── package.json                  # Superpowers-mcp v0.1.0, MIT license
│   └── node_modules/                 # Dependencies (not tracked in git)
│
├── docs/
│   ├── ARCHITECTURE.md               # System architecture: how Serena, Mem0, Superpowers
│   │                                 # connect, their data flow, and component details.
│   ├── TOKEN_SAVINGS.md              # Detailed analysis: ~50% token reduction,
│   │                                 # with before/after examples for common tasks.
│   ├── TROUBLESHOOTING.md            # All known issues: port conflicts, PATH issues,
│   │                                 # timeout fixes, GPU detection, reset procedures.
│   └── INSTALL-GUIDE.md              # Manual step-by-step guide for human setup
│                                     # when automated scripts can't be used.
│                                     # Includes a manual TODO checklist.
│
├── data/                             # Persistent data (auto-created, not in git)
│   ├── qdrant/                       # Qdrant vector database storage (memories)
│   └── mem0/                         # Mem0 SQLite history + bootstrap files
│
└── repository-starters/              # Install files to enable MCP setup in new repos
    └── mcp-servers/
        ├── AGENTS.md                 # MCP tool instructions for AGENTS.md-aware tools
        ├── CLAUDE.md                 # Instructions for Claude Code agents
        └── README.md                 # How to use the starter pack
```

## Requirements

- **Docker Desktop** (for Qdrant)
- **uv** (Python package manager — `winget install --id=astral-sh.uv -e`)
- **Node.js 18+** (for Superpowers — already installed: v24.16.0)
- **Native Ollama** (for embeddings — already running with bge-m3)
- **12 GB GPU** (optional — GPU acceleration for Ollama; CPU fallback works)
- **CodeWhale 0.8+** or **Claude Code**

## Documentation

| Document | Description |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Full system architecture and data flow |
| [TOKEN_SAVINGS.md](docs/TOKEN_SAVINGS.md) | How much tokens each server saves |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues and fixes |
| [INSTALL-GUIDE.md](docs/INSTALL-GUIDE.md) | Manual step-by-step installation |
| [TODO.md](TODO.md) | Claude Code migration plan |

## Agent Skill

The `agent-skills/skills/mcp-servers-setup/SKILL.md` skill teaches agents how to:

- Use Serena tools for code navigation (not file reads)
- Tag Mem0 memories with project names for isolation
- Activate Superpowers workflows for complex tasks
- Ensure proper project initialization

Load the skill with: `load_skill("mcp-servers-setup")`

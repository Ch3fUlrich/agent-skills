# MCP Server Stack — Self-Hosted, No API Keys

A combined MCP server stack for CodeWhale that reduces token usage by
40–60% on code-heavy tasks through semantic navigation, disciplined
coding workflows, and filesystem operations.

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

## Active Servers (3 of 4)

| MCP Server | Transport | Purpose | Token Savings | Status |
|-----------|-----------|---------|:---:|:------:|
| [Serena](https://github.com/oraios/serena) | stdio (`uvx`) | LSP semantic code navigation — find symbols, references, structure without reading files | ~40–60% | ✅ Working |
| [Superpowers](https://github.com/erophames/superpowers-mcp) | stdio (`node`) | Disciplined workflow skills — TDD, debugging, planning, brainstorming | Quality | ✅ Working |
| [Filesystem](https://github.com/modelcontextprotocol/servers) | stdio (`cmd /c npx`) | Recursive `directory_tree`, batch reads, file metadata | ~5% | ✅ Working |
| **Mem0** ([elvismdev](https://github.com/elvismdev/mem0-mcp-selfhosted)) | stdio | Persistent cross-session memory — store and recall facts across sessions | Context reuse | ❌ Disabled |

## ❌ Mem0 — Disabled: CodeWhale Hardcoded Timeout

### The Problem

CodeWhale has a **hardcoded 120-second MCP stdio timeout** that cannot be
overridden by `execute_timeout` in `mcp.json` or `[mcp]` timeouts in
`config.toml`. Every `tools/call` for mem0 times out at exactly 120s
regardless of the configured value (tried 300s, 600s, and 999s).

The binary itself works perfectly — CLI tests confirm `add_memory` completes
in 26.5s (with pre-warmed models) or 110.7s (cold start), both within the
120s window. But CodeWhale's stdio transport never receives the response.

### All Attempted Fixes (None Worked)

| # | Attempt | Result |
|---|---------|--------|
| 1 | Increase `execute_timeout` to 300s, 600s, 999s | Still times out at 120s — hardcoded |
| 2 | Set `[mcp]` global timeouts in `config.toml` | Still times out at 120s — ignored |
| 3 | Set `PYTHONUNBUFFERED=1` (Python stdout buffering theory) | Still times out |
| 4 | Use `uvx --from local-patched` instead of installed binary | Still times out |
| 5 | Use `uvx --from git+https://...` (original unpatched) | Still times out |
| 6 | Switch to Streamable HTTP transport (persistent daemon) | Server crashes on connection |
| 7 | PowerShell wrapper with baked-in env vars | Still times out |
| 8 | Set all `MEM0_*` env vars at Windows User level | Still times out |
| 9 | Pre-warm Ollama models (bge-m3 + qwen2.5:1.5b) | Faster binary (26.5s) but still times out |
| 10 | Rebuild corrupted Qdrant collection | Collection healthy, still times out |
| 11 | Try alternative mem0 MCP server (olk/mem0-mcp, AsyncMemory) | Installed but returns empty response |
| 12 | Try ChromaDB+SQLite alternative (syyunn/mcp-memory-toolkit) | Repository deleted/not found |
| 13 | Kill stale process, force respawn | Process alive, times out anyway |

### Infrastructure Retained

The Qdrant vector database, Ollama models, and patched mem0 binary remain in
place for when CodeWhale supports per-server MCP timeouts:

| Component | Status |
|-----------|--------|
| Qdrant v1.18.2 on `:6333` | ✅ Running |
| Ollama bge-m3 + qwen2.5:1.5b on `:11434` | ✅ Pre-warmed |
| Patched `mem0-mcp-selfhosted` binary | ✅ Installed at `~/.local/bin/` |
| `OLLAMA_KEEP_ALIVE=24h` | ✅ Persistent env var |
| `MEM0_USER_ID=mauls` | ✅ Persistent env var |

### Recommended Alternative: Serena Memories

Use **Serena's `write_memory` / `read_memory`** for project-scoped persistent
notes. This is already verified working across 5+ repos with instant response:

```
mcp_serena_activate_project(project="agent-skills")
mcp_serena_write_memory(memory_name="setup", content="MCP stack has 3 working servers...")
mcp_serena_read_memory(memory_name="setup")
```

Backed by CodeWhale's built-in `note` tool for session-level memory.

## How It Works

```
                    stdio (per-session)
  CodeWhale ────────────▶ serena-agent        ── LSP tools (51 tools)
  (or Claude Code) ─────▶ superpowers-mcp     ── workflow tools (14 skills)
                    ─────▶ filesystem MCP      ── file tools (14 tools)
                               │
             Docker (persistent)│
             ┌─────────────────┘
             ▼
       ┌──────────┐
       │ Qdrant   │     ← Retained for future mem0 support
       │ :6333    │
       │ vector   │
       │ store    │
       └──────────┘
```

### Multi-Repo Support

All 3 servers work with **any repository** under `C:\Users\mauls\Documents\Code`:

| Server | How Per-Repo Scoping Works | Tested Repos |
|--------|---------------------------|--------------|
| **Serena** | Per-repo `.serena/project.yml` index, auto-loaded via project activation | agent-skills, MaxEntBNew, DeepLabCut, MARBLE, Server |
| **Superpowers** | Stateless — same 14 skills, context-aware recommendations | All repos |
| **Filesystem** | Path-scoped to `C:\Users\mauls\Documents\Code` | All repos |

### Project Isolation

- **Serena**: Automatic per-repo via `.serena/project.yml`. Each repo gets its own language server indices. No configuration needed.
- **Superpowers**: Stateless — no persistent data, no isolation concerns.
- **Filesystem**: Path-scoped — only accesses paths under the allowed root.

## Requirements

| Component | Check | Install |
|-----------|-------|---------|
| Docker Desktop | `docker info` | `winget install Docker.DockerDesktop` |
| Native Ollama | `curl :11434` | `winget install Ollama.Ollama` |
| uv (Python) | `uv --version` | `winget install --id=astral-sh.uv -e` |
| Node.js 18+ | `node --version` | `winget install OpenJS.NodeJS.LTS` |
| CodeWhale 0.8+ | `codewhale-tui --version` | — |

## Directory Structure

```
agent-skills/mcp-servers/
├── README.md                           ← You are here.
├── TODO.md                             ← Full Claude Code migration plan.
├── docker-compose.yml                  # Qdrant container (mem0 vector store retained for future use).
├── .env.example                        # Template for environment variables.
│
├── config/
│   ├── mcp.json                        # ACTIVE — defines 3 servers for CodeWhale.
│   │                                   #   serena: uvx serena-agent with --enable-gui-log-window false
│   │                                   #   superpowers: node build/index.js
│   │                                   #   filesystem: cmd /c npx @modelcontextprotocol/server-filesystem
│   │                                   #   mem0: DISABLED (hardcoded CodeWhale timeout).
│   ├── mcp-claude-code.json            # Alternative config for Claude Code (if migrating).
│   ├── mem0-config.yaml                # Mem0 config reference (no longer used).
│   └── serena-project.yml              # Per-repo template for Serena.
│
├── windows/                            # PowerShell scripts for Windows.
│   ├── setup.ps1                       # One-time: install tools, start Docker, set env vars,
│   │                                   #   pull Ollama models, configure CodeWhale.
│   ├── start.ps1                       # Daily: start Qdrant, pre-warm Ollama models,
│   │                                   #   initialize new Serena repos.
│   ├── stop.ps1                        # Stop Docker services, preserve data.
│   ├── test.ps1                        # Full test suite: 5 tests covering all components.
│   ├── init-serena-projects.ps1        # Pre-index all 35 repos with Serena.
│   ├── migrate.ps1                     # Migrate data from Claude Code plugins.
│   └── run-mem0.ps1                    # PowerShell wrapper for mem0 (retained for future use).
│
├── linux/                              # Bash scripts for Linux/macOS.
│   ├── setup.sh, start.sh, stop.sh, test.sh
│   └── init-serena-projects.sh, migrate.sh
│
├── mem0-patched/                       # Patched mem0-mcp-selfhosted source (retained).
│   ├── patch.py                        # Fixes search_memories + get_memories for mem0ai v2.x.
│   ├── src/mem0_mcp_selfhosted/        # Patched source code.
│   │   ├── server.py                   # Main MCP server (patched: user_id/agent_id in filters).
│   │   ├── config.py                   # Env-var based configuration.
│   │   ├── helpers.py                  # Utility functions (list_entities, safe_bulk_delete).
│   │   └── env.py                      # Env var reader.
│   └── pyproject.toml                  # uv project definition.
│
├── superpowers/                        # Node.js MCP server for coding workflows.
│   ├── build/index.js                  # Compiled server binary (CodeWhale spawns this).
│   │                                   # Discovers 14 skills from Claude Code cache.
│   ├── src/                            # TypeScript source (read-only reference).
│   ├── package.json                    # v0.1.0, MIT license.
│   └── node_modules/                   # Node.js dependencies (not tracked in git).
│
├── docs/
│   ├── ARCHITECTURE.md                 # Full system architecture: data flow, component
│   │                                   # details, security model.
│   ├── TOKEN_SAVINGS.md                # Detailed analysis: ~50% reduction, before/after
│   │                                   # examples for common coding tasks.
│   ├── TROUBLESHOOTING.md              # All known issues: port conflicts, PATH problems,
│   │                                   # timeout fixes, GPU detection, reset procedures.
│   └── INSTALL-GUIDE.md                # Manual step-by-step setup for humans.
│
├── data/                               # Persistent runtime data (auto-created, not in git).
│   ├── qdrant/                         # Qdrant vector database (retained for future mem0).
│   └── mem0/                           # Mem0 SQLite history + bootstrap memory files.
│
└── repository-starters/                # Copy these into new repos to enable MCP setup.
    └── mcp-servers/
        ├── AGENTS.md                   # MCP tool instructions for AGENTS.md-aware tools.
        ├── CLAUDE.md                   # Instructions for Claude Code agents.
        └── README.md                   # How to use the starter pack.
```

## Ollama Models

| Model | Size | Purpose |
|-------|------|---------|
| `bge-m3:latest` | 566 MB | Embedding generation (retained for future mem0) |
| `qwen2.5:1.5b` | ~1 GB | LLM-based memory extraction (retained for future mem0) |
| `gemma4:e4b` | 9.6 GB | General-purpose (available but not used by MCP) |

Models are pre-warmed at startup (`start.ps1`) and kept in VRAM via
`OLLAMA_KEEP_ALIVE=24h` (persistent system env var).

## Environment Variables

| Variable | Value | Set By |
|----------|-------|--------|
| `MEM0_USER_ID` | `mauls` | `setup.ps1` — persistent user env var (retained) |
| `OLLAMA_KEEP_ALIVE` | `24h` | `setup.ps1` — keeps models in VRAM |

## Documentation

| Document | Description |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System architecture and data flow |
| [TOKEN_SAVINGS.md](docs/TOKEN_SAVINGS.md) | Token reduction analysis |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues and fixes |
| [INSTALL-GUIDE.md](docs/INSTALL-GUIDE.md) | Step-by-step manual setup |
| [TODO.md](TODO.md) | Claude Code migration plan |

## Verification

```powershell
cd agent-skills\mcp-servers
.\windows\test.ps1
```

Inside CodeWhale:
```
/mcp                                    # Should show serena, superpowers, filesystem connected
mcp_serena_activate_project(project="agent-skills")
mcp_serena_find_symbol(name_path_pattern="setup")
mcp_superpowers_list_skills()
mcp_filesystem_directory_tree(path="agent-skills/mcp-servers")
```

## Tool Deduplication

To reduce context bloat, Serena tools that duplicate CodeWhale built-ins
are excluded in `~/.serena/serena_config.yml`:

| Excluded (Serena) | Use Instead (CodeWhale) |
|---|---|
| `create_text_file` | `write_file` |
| `read_file` | `read_file` |
| `execute_shell_command` | `exec_shell` |
| `list_dir` | `list_dir` |
| `search_for_pattern` | `grep_files` |
| `find_file` | `file_search` |
| `replace_content` | `edit_file` / `apply_patch` |

**Filesystem server is kept** despite some duplicate tools (`read_file`,
`write_file`, `edit_file`, `list_directory`, `search_files`) because its
unique tools are valuable:
- `directory_tree` — recursive JSON tree (no CodeWhale equivalent)
- `read_multiple_files` — batch file reads
- `get_file_info` — file metadata (size, dates, permissions)
- `move_file` — rename/move (no CodeWhale equivalent)
- `create_directory` — recursive mkdir (no CodeWhale equivalent)
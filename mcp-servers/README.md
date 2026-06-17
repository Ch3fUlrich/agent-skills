# MCP Server Stack — Self-Hosted, No API Keys

A combined MCP server stack for CodeWhale that reduces token usage by
40–60% on code-heavy tasks through semantic navigation, disciplined
coding workflows.

All servers are **fully self-hosted** — no cloud API keys, no external services.
Runs on your own hardware with Docker + uv + Node.js.

## Quick Start

```powershell
cd C:\Users\mauls\Documents\Code\agent-skills\mcp-servers
.\scripts\windows\setup.ps1
.\scripts\windows\init-serena-projects.ps1   # Pre-index all repos (one-time)
# Restart CodeWhale
```

Then run `.\scripts\windows\start.ps1` each session or after reboot to start Qdrant
and pre-warm Ollama models.

See [INSTALL-GUIDE.md](docs/INSTALL-GUIDE.md) for manual step-by-step setup.

## Active Servers (2 of 4)

| MCP Server | Transport | Purpose | Token Savings | Status |
|-----------|-----------|---------|:---:|:------:|
| [Serena](https://github.com/oraios/serena) | stdio (`uvx`) | LSP semantic code navigation — find symbols, references, structure without reading files | ~40–60% | ✅ Working |
| [Superpowers](https://github.com/erophames/superpowers-mcp) | stdio (`node`) | Disciplined workflow skills — TDD, debugging, planning, brainstorming | Quality | ✅ Working |
| ~~[Filesystem](https://github.com/modelcontextprotocol/servers)~~ | ~~stdio~~ | ~~file I/O~~ | ~~~5%~~ | ❌ Disabled — all 14 tools redundant with CodeWhale built-ins |
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

**All diagnostic files preserved in `.aitk/` for investigation.**

### Infrastructure Retained

All Mem0 infrastructure is fully installed and working at the binary level,
ready to activate the moment CodeWhale fixes the timeout:

- ✅ **Qdrant** (Docker) — vector database on `localhost:6333`
- ✅ **Ollama** — running `bge-m3:latest` (567M, embeddings) + `qwen2.5:1.5b` (986M, LLM)
- ✅ **Patched source** — `servers/mem0-patched/` with fixes for mem0ai v2.x API
- ✅ **MCP config** — ready in `config/mcp.json` (commented out)
- ✅ **Bootstrap memory** — pre-loaded `data/mem0/` with starter memories

## Server Architecture

### Data Flow

```
CodeWhale Agent
  │
  ├── Serena (uvx, stdio)
  │     ├── LSP servers (per-language) ──► Project source code
  │     └── Memories (JSON, local disk) ──► ~/.serena/memories/
  │
  └── Superpowers (Node.js, stdio)
        └── Skills (discovered from Claude Code cache)
              ├── brainstorming
              ├── test-driven-development
              ├── systematic-debugging
              ├── writing-plans / executing-plans
              └── ... 14 skills total
```

### Infrastructure Stack (Retained for Future Mem0)

```
Qdrant (vector DB)          ← Docker, port 6333
  │
Ollama                      ← Local, port 11434
  ├── bge-m3:latest          (embeddings)
  └── qwen2.5:1.5b           (LLM)
  │
Mem0 Python library         ← pip/uv, local
  │
sqlite3                     ← Memory metadata, local disk
```

## Directory Structure

```
mcp-servers/
├── config/                              # CodeWhale MCP configs
│   ├── mcp.json                         # Production config (Serena + Superpowers, no Mem0)
│   ├── mcp-claude-code.json             # Claude Code equivalent config (not used)
│   ├── mem0-config.yaml                 # Mem0 server config (retained, models + providers)
│   └── serena-project.yml               # Per-repo template for Serena
│
├── scripts/                             # Platform scripts
│   ├── windows/                         # PowerShell scripts for Windows
│   │   ├── setup.ps1                    # One-time: install tools, start Docker, set env vars,
│   │   │                                #   pull Ollama models, configure CodeWhale
│   │   ├── start.ps1                    # Daily: start Qdrant, pre-warm Ollama models,
│   │   │                                #   initialize new Serena repos
│   │   ├── stop.ps1                     # Stop Docker services, preserve data
│   │   ├── test.ps1                     # Full test suite: 5 tests covering all components
│   │   ├── init-serena-projects.ps1     # Pre-index all repos with Serena
│   │   └── migrate.ps1                  # Migrate data from Claude Code plugins
│   └── linux/                           # Bash scripts for Linux/macOS
│       ├── setup.sh, start.sh, stop.sh, test.sh
│       └── init-serena-projects.sh, migrate.sh
│
├── servers/                             # MCP server source packages
│   ├── mem0-patched/                    # Patched mem0-mcp-selfhosted source (retained)
│   │   ├── patch.py                     # Fixes search_memories + get_memories for mem0ai v2.x
│   │   ├── src/mem0_mcp_selfhosted/     # Patched source code
│   │   │   ├── server.py                # Main MCP server (patched: user_id/agent_id in filters)
│   │   │   ├── config.py                # Env-var based configuration
│   │   │   ├── helpers.py               # Utility functions (list_entities, safe_bulk_delete)
│   │   │   └── env.py                   # Env var reader
│   │   └── pyproject.toml               # uv project definition
│   │
│   └── superpowers/                     # Node.js MCP server for coding workflows
│       ├── build/index.js               # Compiled server binary (CodeWhale spawns this)
│       │                                 # Discovers 14 skills from Claude Code cache
│       ├── src/                         # TypeScript source (read-only reference)
│       ├── package.json                 # v0.1.0, MIT license
│       └── node_modules/                # Node.js dependencies (not tracked in git)
│
├── docs/
│   ├── ARCHITECTURE.md                  # Full system architecture: data flow, component
│   │                                    # details, security model
│   ├── TOKEN_SAVINGS.md                 # Detailed analysis: ~50% reduction, before/after
│   │                                    # examples for common coding tasks
│   ├── TROUBLESHOOTING.md               # All known issues: port conflicts, PATH problems,
│   │                                    # timeout fixes, GPU detection, reset procedures
│   └── INSTALL-GUIDE.md                 # Manual step-by-step setup for humans
│
├── data/                                # Persistent runtime data (auto-created, not in git)
│   ├── qdrant/                          # Qdrant vector database (retained for future mem0)
│   └── mem0/                            # Mem0 SQLite history + bootstrap memory files
│
├── docker-compose.yml
├── .env.example
├── TODO.md
└── README.md                            # This file
```

## Token Savings — Evidence

Measured on a moderately complex refactoring task (5 files, 12 symbol lookups),
comparing before/after Serena:

| Metric | Before (file reads) | After (Serena) | Reduction |
|--------|---------------------|----------------|-----------|
| `read_file` calls | 24 | 1 | **-96%** |
| Token consumption | ~45K | ~18K | **-60%** |
| Turn count | 18 | 8 | **-56%** |
| Time | ~3 min | ~1 min | **-67%** |

See [TOKEN_SAVINGS.md](docs/TOKEN_SAVINGS.md) for detailed cases.

## Per-Repository Starter

To enable MCP servers in a new repository, copy the starter pack from the parent repository:

```
starters/mcp-servers/
```

This installs `AGENTS.md` and `CLAUDE.md` files that teach the agent how to activate
Serena, run onboarding, and use semantic code navigation from the first turn.

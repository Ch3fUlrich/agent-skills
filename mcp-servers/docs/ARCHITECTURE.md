# MCP Server Stack — Architecture

## Overview

Three self-hosted MCP servers work together to give CodeWhale (and later
Claude Code) semantic code understanding, persistent memory, and disciplined
coding workflows — all without cloud API keys or external services.

```
                      CodeWhale TUI (DeepSeek V4)
                      or Claude Code CLI
                              │
              ┌───────────────┼───────────────────┐
              │ stdio         │ stdio             │ stdio
              ▼               ▼                   ▼
     ┌──────────────┐ ┌──────────────┐  ┌──────────────────┐
     │  serena      │ │  mem0        │  │  superpowers     │
     │  (LSP tools) │ │  (memory)    │  │  (workflows)     │
     └──────────────┘ └──────┬───────┘  └──────────────────┘
                             │ HTTP API
                    ┌────────┴────────┐
                    ▼                 ▼
            ┌──────────┐     ┌──────────────┐
            │ Qdrant   │     │  Ollama      │
            │ :6333    │     │  :11434      │
            │ (vector  │     │  (bge-m3     │
            │  store)  │     │   embeddings)│
            └──────────┘     └──────────────┘
```

## Component Details

### Serena MCP Server

**What it does**: Exposes Language Server Protocol (LSP) capabilities to the
AI agent. Instead of reading entire files, the agent uses semantic tools:

| Serena Tool | What the agent asks | Without Serena (cost) |
|---|---|---|
| `find_symbol` | "Where is `process_batch` defined?" | Reads whole file (500+ tokens) |
| `find_references` | "Who calls `process_batch`?" | Reads 3–5 files (2000+ tokens) |
| `get_file_structure` | "What's in this module?" | Reads file tree recursively |
| `get_code_context` | "Show me the code around X" | Reads file + guesses boundaries |
| `search_for_pattern` | "Find all error handlers" | Grep + read each match |

**How it works**: Serena starts language servers (pyright for Python,
typescript-language-server for TS, etc.) and queries them via LSP. The
results are precise and token-efficient because the agent gets exactly
what it asked for — not the whole file.

**Token savings**: 40–60% on code-heavy tasks. Most impactful when the agent
needs to understand a codebase it hasn't seen before.

**Installation**: `uv tool install serena-agent` — a single Python package
that bundles all language server logic.

**Multi-repo support**: `--project-from-cwd` auto-detects the active
repository by walking up from the current directory and finding `.git`.
Each repo gets its own language server instance.

### Mem0 MCP Server (Self-Hosted)

**What it does**: Persistent, cross-session memory. The agent can store
facts, decisions, and patterns it learns, then recall them in future
sessions. Without Mem0, every new session starts from zero context.

**How it works**:
1. Agent says `remember("User prefers type hints in Python")`
2. Mem0 embeds the text using bge-m3 (local Ollama)
3. Embedding stored in Qdrant (local vector DB)
4. Next session: agent asks `recall("Python coding preferences")`
5. Mem0 searches Qdrant for similar embeddings, returns relevant memories

**Infrastructure**:
- Qdrant (Docker): Vector database, stores embeddings
- Ollama (Docker): Local LLM, runs bge-m3 for embedding generation
- mem0-mcp-selfhosted (uv): MCP server that wraps the Mem0 Python library

**Why self-hosted**: No Mem0 Cloud API key needed. All data stays on your
machine. Unlimited usage, no rate limits.

**Connection flow**:
```
mem0-mcp-selfhosted (uv process)
  → reads config/mem0-config.yaml
  → connects to Qdrant (localhost:6333) for vector storage
  → connects to Ollama (localhost:11434) for embeddings
```

### Superpowers MCP Server

**What it does**: Provides structured coding workflows as MCP tools:
- TDD (test-driven development) workflow
- Systematic debugging (hypothesis → test → verify)
- Brainstorming and planning frameworks
- Code review checklists

**Without Superpowers**: The agent improvises workflows, sometimes skipping
steps or jumping to conclusions. With Superpowers, it has access to proven
workflow templates that enforce discipline.

**Token savings**: Quality improvement — fewer wasted cycles debugging,
fewer rewrites. Not directly measurable in tokens, but observably faster
completion of complex tasks.

**Installation**: `uv tool install --from git+https://github.com/erophames/superpowers-mcp superpowers-mcp`

## Docker Infrastructure

The Docker Compose stack runs two persistent services:

```
agent-skills/mcp-servers/
├── docker-compose.yml     ← Defines services
├── data/
│   ├── qdrant/            ← Qdrant storage (persistent)
│   ├── ollama/            ← Ollama models (persistent, includes bge-m3)
│   └── mem0/              ← Mem0 history DB
```

### Qdrant
- Image: `qdrant/qdrant:latest`
- Ports: `6333` (HTTP API), `6334` (gRPC)
- Web dashboard: `http://localhost:6333/dashboard`
- Storage mounted at `./data/qdrant` — survives container restarts

### Ollama
- Image: `ollama/ollama:latest`
- Port: `11434` (HTTP API)
- GPU: NVIDIA GPU passed through for faster inference (falls back to CPU)
- Model: `bge-m3` (~2 GB) — pulled on first start via `ollama-pull-model` helper
- Storage mounted at `./data/ollama` — survives container restarts

### bge-m3 Model Choice
- **Size**: ~2 GB, fits easily on 12 GB GPU
- **Quality**: Best open-source embedding model (MTEB leaderboard)
- **Capabilities**: Dense + sparse hybrid embeddings, multilingual (100+ languages)
- **Dimension**: 1024-dimensional vectors
- **Why not smaller models**: Smaller models (nomic-embed-text, all-minilm) give lower
  quality memories. The 2 GB cost is worth it for accurate retrieval.

## Data Flow: Typical Session

```
User: "Add error handling to the batch processing pipeline"

1. CodeWhale → Serena: find_symbol("batch_process")
   Serena → CodeWhale: { file: "src/pipeline.py", line: 42, signature: "def batch_process(items: list)" }

2. CodeWhale → Serena: get_code_context("batch_process", context_lines=20)
   Serena → CodeWhale: [just the 20 lines around line 42]

3. CodeWhale → Mem0: recall("error handling patterns for batch processing")
   Mem0 → CodeWhale: "User prefers try/except with specific exception types, uses logging.error()"

4. CodeWhale → Superpowers: use_skill("tdd")
   Superpowers → CodeWhale: [TDD workflow: write test → run (fail) → implement → run (pass) → refactor]

5. Agent edits code, runs tests, records decision:
   CodeWhale → Mem0: remember("Batch processing now uses custom BatchError with retry logic")

6. Next session, another agent asks:
   CodeWhale → Mem0: recall("batch processing")
   Mem0 → CodeWhale: "Batch processing uses custom BatchError with retry logic (added 2026-06-16)"
```

## Configuration Files

### `~/.codewhale/mcp.json` (CodeWhale)
Loaded on startup by CodeWhale. Defines three stdio MCP servers.
Tools exposed as `mcp_serena_*`, `mcp_mem0_*`, `mcp_superpowers_*`.

### `config/mem0-config.yaml` (Mem0)
Points Mem0 to local Qdrant and Ollama. No API keys needed.

### `config/serena-project.yml` (Optional per-repo)
Copy to `.serena/project.yml` in any repo to customize Serena's behavior
(language overrides, additional workspace folders for cross-repo refs).

## Token Consumption Analysis

See `docs/TOKEN_SAVINGS.md` for detailed estimates.

Quick summary:
- **Serena**: Saves ~40-60% of code-reading tokens (the biggest category in most sessions)
- **Mem0**: Avoids re-explaining context each session (10-20% total token savings across sessions)
- **Superpowers**: Quality improvement, fewer wasted cycles (harder to measure but observable)
- **Combined**: Estimated 50-70% token reduction on code-heavy multi-session work

## Security

- All services bind to `127.0.0.1` only — no network exposure
- No API keys stored or transmitted
- Qdrant and Ollama are not exposed to the internet
- Mem0 memory data stays in `./data/mem0/` (SQLite) and Qdrant
- Serena's project indices are per-repo `.serena/` directories

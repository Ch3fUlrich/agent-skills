# MCP Server Stack — Architecture

## Overview

Three self-hosted MCP servers give CodeWhale (and Claude Code) semantic code
understanding, persistent memory, and disciplined coding workflows.

```
                      CodeWhale TUI (DeepSeek V4)
                      or Claude Code CLI
                              │
              ┌───────────────┼───────────────────┐
              │ stdio         │ SSE               │ stdio
              ▼               ▼                   ▼
     ┌──────────────┐ ┌──────────────┐  ┌──────────────────┐
     │  serena      │ │  mem0-mcp    │  │  superpowers     │
     │  (LSP tools) │ │  (bridge)    │  │  (workflows)     │
     └──────────────┘ └──────┬───────┘  └──────────────────┘
                             │ HTTP (Docker network)
                             ▼
                    ┌──────────────────┐
                    │  mem0 REST API   │
                    │  (official img)  │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │  PostgreSQL 17   │
                    │  + pgvector      │
                    └──────────────────┘
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

### Mem0 — Official Self-Hosted Docker Stack

**What it does**: Persistent, cross-session memory. The agent stores facts,
decisions, and patterns it learns, then recalls them in future sessions.

**Architecture**: Three Docker containers on a shared bridge network:

```
mem0-mcp (Python, :8001)     ← MCP SSE bridge — agents connect here
    │ HTTP
mem0-api (FastAPI, :8888)    ← Official mem0/mem0-api-server image
    │ PostgreSQL
postgres (pgvector, :5432)   ← Vector embeddings + metadata
```

**How it works**:
1. Agent calls `add_memory("User prefers type hints in Python")` via SSE
2. MCP bridge forwards to mem0 REST API: `POST /memories`
3. Mem0 API calls DeepSeek V4 for fact extraction and Ollama for embeddings
4. Embeddings stored in PostgreSQL with pgvector extension
5. Later: `search_memories("Python coding preferences")` → semantic search
6. Returns ranked memories with similarity scores

**Why SSE instead of stdio**: The previous stdio-based mem0 MCP server hit
CodeWhale's hardcoded 120-second MCP timeout. SSE transport runs as a
persistent HTTP service inside Docker — no stdio timeout applies. The
bridge waits as long as the mem0 API takes to respond.

**Provider support**: Configured with DeepSeek (`deepseek-chat` for extraction)
and Ollama (`bge-m3` for embeddings). Can be swapped via the Configuration page
or `.env` overrides to OpenAI, Anthropic, or Gemini.

### Superpowers MCP Server

**What it does**: Provides structured coding workflows as MCP tools:
- TDD (test-driven development) workflow
- Systematic debugging (hypothesis → test → verify)
- Brainstorming and planning frameworks
- Code review checklists

**Without Superpowers**: The agent improvises workflows, sometimes skipping
steps or jumping to conclusions. With Superpowers, it has access to proven
workflow templates that enforce discipline.

**Installation**: Cloned from `github.com/erophames/superpowers-mcp` and
built with `npm install && npm run build`.

## Docker Infrastructure

The Docker Compose stack runs three Mem0 services plus Serena's backend:

```
mcp-servers/
├── docker-compose.yml     ← Mem0 stack definition
├── .env                   ← Secrets (DEEPSEEK_API_KEY, POSTGRES_PASSWORD, JWT_SECRET)
├── data/
│   ├── postgres/          ← PostgreSQL data (persistent, survives restarts)
│   └── mem0-history/      ← Mem0 request history logs
└── servers/
    └── mem0-mcp/          ← MCP bridge source + Dockerfile
```

### PostgreSQL + pgvector
- Image: `pgvector/pgvector:pg17`
- Port: `5432` (bound to 127.0.0.1 only)
- Extension: pgvector 0.8.0 for vector similarity search
- Storage: `./data/postgres` — persists across container restarts
- Credentials: driven by `POSTGRES_USER` / `POSTGRES_PASSWORD` env vars

### Mem0 REST API
- Image: `mem0/mem0-api-server:latest`
- Port: `8888` → internal `8000` (bound to 127.0.0.1)
- Runs Alembic migrations on startup (`alembic upgrade head`)
- OpenAPI docs: `http://localhost:8888/docs`
- Bundled providers: deepseek, openai, anthropic, gemini (for LLM); ollama, openai, gemini (for embedder)
- Auth: JWT-based by default (set `ADMIN_API_KEY` and `JWT_SECRET`)

### Mem0 MCP Bridge
- Custom Python server using `mcp` library (FastMCP)
- Port: `8001` (bound to 127.0.0.1)
- SSE endpoint: `http://localhost:8001/sse`
- Connects to mem0 API via internal Docker network: `http://mem0:8000`
- Tools: `add_memory`, `search_memories`, `get_memories`, `delete_memory`, `health`

## Data Flow: Typical Session

```
User: "Add error handling to the batch processing pipeline"

1. CodeWhale → Serena: find_symbol("batch_process")
   Serena → CodeWhale: { file: "src/pipeline.py", line: 42 }

2. CodeWhale → Serena: get_code_context("batch_process", context_lines=20)
   Serena → CodeWhale: [20 lines around line 42]

3. CodeWhale → Mem0: search_memories("error handling patterns for batch processing")
   Mem0 → CodeWhale: "User prefers try/except with specific exception types"

4. CodeWhale → Superpowers: use_skill("tdd")
   Superpowers → CodeWhale: [TDD workflow]

5. Agent edits code, runs tests, records decision:
   CodeWhale → Mem0: add_memory("Batch processing now uses custom BatchError")

6. Next session, another agent asks:
   CodeWhale → Mem0: search_memories("batch processing")
   Mem0 → CodeWhale: "Batch processing uses custom BatchError (added 2026-06-18)"
```

## Configuration Files

### `~/.codewhale/mcp.json` (CodeWhale)
Loaded on startup. Defines three MCP servers: Serena (stdio), Mem0 (SSE),
Superpowers (stdio). Tools exposed as `mcp_serena_*`, `mcp_mem0_*`, `mcp_superpowers_*`.

### `.env` (Mem0 secrets)
Contains `DEEPSEEK_API_KEY`, `POSTGRES_PASSWORD`, `JWT_SECRET`, `ADMIN_API_KEY`.
Never committed to git. Template at `.env.example`.

### `config/serena-project.yml` (Optional per-repo)
Copy to `.serena/project.yml` in any repo to customize Serena's behavior.

## Security

- All services bind to `127.0.0.1` only — no network exposure
- Mem0 `.env` contains API keys — never committed (`.gitignore` enforced)
- JWT authentication on the mem0 REST API
- Docker internal network (`mem0-net`) isolates service-to-service traffic
- PostgreSQL credentials scoped to the compose stack

## Token Consumption Analysis

See `docs/TOKEN_SAVINGS.md` for detailed estimates.

Quick summary:
- **Serena**: Saves ~40-60% of code-reading tokens
- **Mem0**: Avoids re-explaining context each session (10-20% savings across sessions)
- **Superpowers**: Fewer wasted cycles from structured workflows
- **Combined**: Estimated 50-70% token reduction on code-heavy multi-session work

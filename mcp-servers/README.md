# MCP Server Stack — Self-Hosted

A combined MCP server stack for CodeWhale that reduces token usage by
40–60% on code-heavy tasks through semantic navigation, disciplined
coding workflows, and persistent cross-session memory.

Runs on your own hardware with Docker + uv + Node.js. Mem0 uses
**DeepSeek V4** for fact extraction and **Ollama with bge-m3** for
embeddings — no OpenAI API key required.

## Quick Start

```powershell
cd C:\Users\mauls\Documents\Code\agent-skills\mcp-servers
# 1. Edit .env — set DEEPSEEK_API_KEY + POSTGRES_PASSWORD
# 2. Run setup
.\scripts\windows\setup.ps1
.\scripts\windows\init-serena-projects.ps1   # Pre-index all repos (one-time)
.\scripts\windows\init-graphify-projects.ps1  # Build repo graphs (one-time)
# 3. Register servers into Claude Code's own config (per server, deliberately —
#    see "Graphify + local Ollama - known gotchas" below for why this isn't automatic)
.\scripts\windows\register-claude-code-mcp.ps1 -Server graphify
# 4. Restart CodeWhale / Claude Code — MCP servers only load at session start
```

Then run `.\scripts\windows\start.ps1` each session or after reboot to start the
Mem0 Docker stack.

See [docs/INSTALL-GUIDE.md](docs/INSTALL-GUIDE.md) for manual step-by-step setup.

## Active Servers (5 of 6)

| MCP Server | Transport | Purpose | Token Savings | Status |
|-----------|-----------|---------|:---:|:------:|
| [Serena](https://github.com/oraios/serena) | stdio (`uvx`) | LSP semantic code navigation | ~40–60% | Working |
| [Playwright](https://github.com/microsoft/playwright-mcp) | stdio (`npx`) | Full browser automation — navigate, click, type, screenshots | Browser | Working |
| [Graphify](https://github.com/safishamsi/graphify) | stdio (`uv` or Docker) | Queryable project graph for code, docs, and relationships | Graph reasoning | Working |
| **Mem0** (official) | SSE (`docker`) | Persistent cross-session memory — REST API + pgvector + MCP bridge | Context reuse | Working |
| [Superpowers](https://github.com/erophames/superpowers-mcp) | stdio (`node`) | Disciplined workflow skills — TDD, debugging, planning, brainstorming | Quality | Working |
| ~~Filesystem~~ | ~~stdio~~ | ~~file I/O~~ | ~~~5%~~ | Disabled — redundant with CodeWhale built-ins |

## Graphify Visualizations
Graphify provides built-in tools to visualize your project graph. After extraction, you can generate:
- **Hierarchical Tree:** `uv run --with graphifyy[mcp] graphify tree` (generates `GRAPH_TREE.html`)
- **Call-flow Diagrams:** `uv run --with graphifyy[mcp] graphify export callflow-html` (generates mermaid flowcharts)
- **Custom Force-Directed Graphs:** Because the graph is exported as a standard `graph.json`, you can use standard Python libraries (like `networkx` or `vis.js` templates) to render interactive physics-based graphs.

## Graphify as a Docker Container

If you don't want a host-level `uv`/Python toolchain, `servers/graphify-mcp/`
builds a Docker image with `graphifyy[mcp]` preinstalled and runs the same
stdio server (`graphify.serve`) — see `servers/graphify-mcp/README.md` for
build, graph-generation, handshake-testing, and registration instructions.
It's registered in `config/mcp-claude-code.json` as `graphify-docker`
alongside the default `uv`-based `graphify` entry (register whichever one
you actually built/want with `register-claude-code-mcp.ps1 -Server
graphify-docker`). Because `graphify.serve` is stdio-only, this is a
`docker run -i --rm` subprocess per session, not a long-running compose
service like `serena`/`mem0`.

## Graphify + Local Ollama — Known Gotchas

Everything below was learned the hard way building graphs for three real
repos on a local RTX 3060. `init-graphify-projects.ps1` and
`patch-graphify-ollama-bugs.py` already encode all of this — read this
section if something still goes wrong, or before changing those scripts.

**The MCP server needs `graphifyy[mcp]`, not bare `graphifyy`.** The
`config/mcp-claude-code.json` template used to omit the extra; the server
would crash on the first request with `ModuleNotFoundError: No module named
'mcp'`. Always test a graphify MCP server change with a raw handshake before
trusting it:
```powershell
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | uv run --with "graphifyy[mcp]" python -m graphify.serve graphify-out/graph.json
```
A working server replies with a `serverInfo` block on stdout, not silence
or a traceback on stderr.

**`extract --backend ollama` needs the `[ollama]` extra too** (`graphifyy[ollama]`,
for the `openai` package it uses to talk to Ollama's OpenAI-compatible
endpoint) — otherwise every chunk fails with *"the 'openai' package is
required for this backend"*.

**graphify's own ollama default model, `qwen2.5-coder:7b`, is not pulled by
anything in this stack** and isn't code you actually want here anyway — it's
a *coding* model, not a *structured-output* model, and the extraction schema
graphify asks for is closer to a function-call/JSON-mode task. In testing,
**`hermes3:8b`** (Nous Research, tuned for reliable tool-call/JSON output)
produced noticeably fewer malformed responses than `qwen2.5-coder:7b` on
identical repos, at a similar ~5GB VRAM footprint. `init-graphify-projects.ps1`
defaults to it and auto-pulls it via the Ollama REST API if missing.

**The default 5-minute client timeout is too short.** `docker logs ollama`
will show `500 | 5m0s` entries for requests that were still legitimately
generating — the client gives up and graphify retries with a smaller,
bisected chunk, wasting the work already done. Use `--api-timeout 1200`
(20 min) for local models; a healthy chunk usually finishes in 5-30s, but a
handful of harder ones can run long even on a good model.

**`--token-budget 6000 --max-concurrency 1`** keeps per-chunk requests small
enough for an 8B-class model to stay coherent, and avoids queuing multiple
requests against a single-GPU Ollama instance that can only serve one at a
time anyway (`OLLAMA_NUM_PARALLEL` doesn't help if there's only one GPU).

**Local models will still produce plenty of invalid JSON** — expect roughly
30-40% of semantic chunks to get skipped or partially truncated even with a
good model and the tuning above. graphify's adaptive bisection retries and
keeps partial results, so the graph is usable (AST/code-structure data,
which is deterministic, dominates the graph anyway) but not exhaustive on
the LLM-derived semantic layer. Rebuild with a real API-backed model
(`--backend openai`/`claude`/`gemini`/`deepseek` with a key) if you need
higher recall.

**`--force` bypasses graphify's semantic cache, not just the output file.**
A `--force` rebuild always redoes the full LLM extraction pass (can be
~1h per repo on a local 8B model), even if nothing changed. Don't add
`-Force` to `init-graphify-projects.ps1` out of habit.

**graphify v0.9.4 (latest on PyPI) crashes on its own malformed-response
recovery path** in three places — a noisy local model occasionally returns
`"nodes": "some string"` instead of a list of node objects, and graphify's
`.extend()`/`.get()` calls don't guard against that, so the crash happens
*after* a full ~1h extraction pass completes, right at the final write/merge
step. `scripts/patch-graphify-ollama-bugs.py` patches all three sites
defensively (skip non-dict entries, coerce IDs to `str`) directly in the uv
cache; `init-graphify-projects.ps1` runs it automatically before every
extraction. It's idempotent and safe to re-run. These are real upstream
robustness gaps worth reporting to the graphify maintainer, not local-LLM-
specific hacks — the patches don't change behavior for well-formed data.

**uv may extract graphify into multiple different cache directories** — one
per resolved environment, which can differ per target repo if it has its
own `pyproject.toml`/lockfile. The patch script scans and patches every copy
it finds (`uv cache dir` + `archive-v0/*/**/graphify/{__main__,ids}.py`), so
this is handled automatically, but it's why you can't just patch "the"
graphify install once and be done.

## Mem0 — Official Self-Hosted Docker Stack

Mem0 runs as a three-container Docker stack using the official `mem0/mem0-api-server`
image, PostgreSQL with pgvector for embeddings, and a custom MCP SSE bridge that lets
CodeWhale and Claude Code connect without the stdio timeout issue.

### Architecture

```
CodeWhale / Claude Code
  │
  │ SSE (http://localhost:8001/sse)
  ▼
┌──────────────────┐
│  mem0-mcp bridge │  ← Custom Python MCP server (Docker, port 8001)
│  (FastMCP + SSE) │    Translates MCP tools ↔ REST API calls
└────────┬─────────┘
         │ HTTP (internal Docker network)
         ▼
┌──────────────────┐
│  mem0 REST API   │  ← Official mem0/mem0-api-server (Docker, port 8888)
│  (FastAPI)       │    Fact extraction, embedding, memory CRUD
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  PostgreSQL 17   │  ← pgvector/pgvector:pg17 (Docker, port 5432)
│  + pgvector      │    Vector embeddings + memory metadata
└──────────────────┘
```

### Why This Fixes the Old Problem

The previous setup used a third-party MCP server (`mem0-mcp-selfhosted` by elvismdev)
over stdio transport. CodeWhale's hardcoded 120-second MCP stdio timeout killed every
`tools/call` before mem0 could respond. The new approach:

- **SSE transport** — the MCP bridge runs as a persistent Docker service with an HTTP
  SSE endpoint. No stdio timeout applies.
- **Official images** — uses `mem0/mem0-api-server:latest` and `pgvector/pgvector:pg17`,
  the same stack documented at docs.mem0.ai.
- **Separation of concerns** — the mem0 REST API handles fact extraction and vector
  storage; the MCP bridge only translates tool calls. If the API is slow, the bridge
  waits (no 120s deadline).

### Available MCP Tools

| Tool | Description |
|------|-------------|
| `add_memory` | Store text or conversation as a memory |
| `search_memories` | Semantic search across memories with scores |
| `get_memories` | List all memories for a user |
| `delete_memory` | Delete a memory by ID |
| `health` | Check bridge and API health |

### Quick Verification

```powershell
# Check the REST API
curl http://localhost:8888/health

# Check the MCP bridge
curl http://localhost:8001/sse

# Add a test memory
curl -X POST http://localhost:8888/memories `
  -H "Content-Type: application/json" `
  -d '{"messages":[{"role":"user","content":"Test memory"}],"user_id":"mauls"}'
```

### Why Mem0 over Serena for Memory?

While Serena includes basic local memory capabilities, **Mem0 is the designated single source of truth for all cross-session memory in this stack.** 

1. **Intelligence:** Mem0 automatically extracts entities, handles summarization, and uses vector search natively. It removes the cognitive overhead of manually formatting knowledge graphs.
2. **Project Isolation:** Mem0 supports strict project isolation natively via the `user_id` parameter (mapping to your repository folder name), which is crucial for preventing memory spillover across different projects.
3. **Reliability:** Mem0 is a production-grade infrastructure layer that reliably persists data and scales.

To prevent agent confusion and overlapping functionality, Serena's memory tools (`write_memory`, `read_memory`, etc.) are explicitly **disabled** using the `excludeTools` configuration in all provided JSON setup files. Do not re-enable them.

## Server Architecture

### Data Flow

```
CodeWhale Agent
  │
  ├── Serena (uvx, stdio)
  │     ├── LSP servers (per-language) ──► Project source code
  │     └── Memories (JSON, local disk) ──► ~/.serena/memories/
  │
  ├── Mem0 (Docker, SSE)
  │     └── mem0-mcp bridge ──► mem0 REST API ──► PostgreSQL + pgvector
  │
  └── Superpowers (Node.js, stdio)
        └── Skills (discovered from Claude Code cache)
              ├── brainstorming
              ├── test-driven-development
              ├── systematic-debugging
              ├── writing-plans / executing-plans
              └── ... 14 skills total
```

### Docker Stack

```
docker compose ps
NAME              STATUS                    PORTS
mem0-postgres     running (healthy)         127.0.0.1:5433→5432
mem0-api          running (healthy)         127.0.0.1:8888→8000
mem0-mcp          running (healthy)         127.0.0.1:8001→8001
```

## MCP Endpoints

| Server | Access URL / Method |
|--------|--------------------|
| **Serena** | `uvx` stdio — no web UI |
| **Playwright** | `npx` stdio — headed browser, no API key needed ([docs](https://playwright.dev/docs/getting-started-mcp)) |
| **Mem0 REST API** | [http://localhost:8888/docs](http://localhost:8888/docs) (OpenAPI), `/health` |
| **Mem0 MCP Bridge** | [http://localhost:8001/sse](http://localhost:8001/sse) (SSE), `/health` |
| **Superpowers** | `node` stdio — no web UI |
| **PostgreSQL** | `localhost:5433` (pgvector, credentials in `.env`) |

## Playwright — Browser Automation for DeepSeek

DeepSeek cannot browse the web. [Playwright MCP](https://github.com/microsoft/playwright-mcp)
(34k+ stars, Microsoft) gives the agent full browser automation — navigate pages,
click elements, type text, take screenshots, mock APIs, and run arbitrary
Playwright scripts. No API key required.

**Why Playwright over search-only MCPs:**
- **Real browser** — renders JavaScript, handles logins, submits forms
- **Accessibility snapshots** — understands page structure without vision models
- **Network monitoring** — inspect and mock API responses
- **Storage state** — persists cookies/localStorage across sessions
- **Multi-browser** — Chrome, Firefox, WebKit, Edge
- **No rate limits** — no API key, no quota, runs locally

**Setup:**
1. Playwright MCP auto-installs on first `npx` run. No manual steps needed.
2. Restart CodeWhale — tools appear as `mcp_playwright_*` (40+ tools).
3. Try: *"Go to example.com, take a screenshot, and describe what you see."*

**Configuration options** (add to `args` in `mcp.json`):
- `--headless` — run without visible browser window
- `--browser=firefox` — use Firefox instead of Chromium
- `--port 8931` — run as standalone HTTP server
- `--isolated` — fresh session each time (no persistent cookies)

## Mem0 Dashboard — Web UI

The self-hosted dashboard runs at **[http://localhost:3000](http://localhost:3000)**.

### Authentication

| Mode | When | How |
|------|------|-----|
| **Open access** (current) | `AUTH_DISABLED=true` in `docker-compose.yml` | Dashboard loads without login. All API endpoints are open. Production: set to `false`. |
| **Authentication enabled** | `AUTH_DISABLED=false` | Visit `/setup` to create the first admin account, then log in with email + password. |

### Enabling auth (production)

1. Set in `.env`:
   ```
   ADMIN_API_KEY=<random-string-16+-chars>
   JWT_SECRET=<openssl-rand-base64-48>
   ```
2. Change `AUTH_DISABLED=false` in `docker-compose.yml` (mem0 service `environment:` block)
3. Rebuild: `docker compose up -d --build mem0`
4. Visit `http://localhost:3000/setup` → create admin account
5. Use `X-API-Key: <ADMIN_API_KEY>` header for admin API operations

### Creating API keys for agents

Once auth is enabled:
1. Log into the dashboard
2. Go to **API Keys** → **Create Key**
3. Give it a label (e.g. "CodeWhale")
4. Copy the generated key
5. Pass it to the MCP bridge or REST API calls as `X-API-Key` header

### Default credentials

There are **no default credentials**. The setup wizard at `/setup` creates the first admin account. Until then, with `AUTH_DISABLED=true`, the dashboard is open.

## Directory Structure

```
mcp-servers/
├── config/                              # CodeWhale MCP configs
│   ├── mcp.json                         # Production config (Serena + Mem0 + Superpowers)
│   ├── mcp-claude-code.json             # Claude Code equivalent config
│   └── serena-project.yml               # Per-repo template for Serena
│
├── scripts/                             # Platform scripts
│   ├── test_mcp_tools.py                # Python tool-level test (via stdio client connection)
│   ├── windows/                         # PowerShell scripts for Windows
│   │   ├── setup.ps1                    # One-time: install tools, validate .env,
│   │   │                                #   pull Docker images, start stack
│   │   ├── start.ps1                    # Daily: start Docker stack, verify health
│   │   ├── stop.ps1                     # Stop Docker services, preserve data
│   │   ├── test.ps1                     # Health test suite (checks Docker containers + API ports)
│   │   ├── init-serena-projects.ps1     # Pre-index all repos with Serena
│   │   ├── init-graphify-projects.ps1    # Build or refresh repo graphs with Graphify
│   │   └── migrate.ps1                  # Migrate data from Claude Code plugins
│   └── linux/                           # Bash scripts for Linux/macOS
│       ├── setup.sh, start.sh, stop.sh, test.sh
│       └── init-serena-projects.sh, migrate.sh
│
├── servers/                             # MCP server source packages
│   ├── mem0-mcp/                        # MCP SSE bridge for mem0 REST API
│   │   ├── server.py                    # FastMCP bridge (5 memory tools)
│   │   ├── Dockerfile                   # Python 3.12 slim image
│   │   └── requirements.txt            # mcp>=1.6.0
│   │
│   └── superpowers/                     # Node.js MCP server for coding workflows
│       ├── build/index.js               # Compiled server binary
│       ├── src/                         # TypeScript source
│       ├── package.json
│       └── node_modules/
│
├── docs/                                # Documentation files
│   ├── ARCHITECTURE.md                  # Full system architecture
│   ├── TOKEN_SAVINGS.md                 # Detailed token savings analysis
│   ├── TROUBLESHOOTING.md               # Known issues and fixes
│   └── INSTALL-GUIDE.md                 # Manual step-by-step setup
│
├── data/                                # Persistent runtime data (auto-created)
│   ├── postgres/                        # PostgreSQL data (pgvector embeddings)
│   └── mem0-history/                    # Mem0 request history
│
├── docker-compose.yml                   # Mem0 stack (postgres + mem0 API + MCP bridge)
├── .env                                 # Secrets (DEEPSEEK_API_KEY, POSTGRES_PASSWORD, etc.)
├── .env.example                         # Template (safe to commit)
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
Serena, run onboarding, build a Graphify graph, and use semantic code navigation from the first turn.

## Google Antigravity Setup

For Google Antigravity, configuration is loaded from the global `mcp_config.json` file. A complete, optimized template is provided at [mcp-servers/config/mcp_antigravity.json](file:///c:/Users/mauls/Documents/Code/agent-skills/mcp-servers/config/mcp_antigravity.json).

### 1. Configuration Location
On Windows, Antigravity reads its config from:
`C:\Users\<username>\.gemini\config\mcp_config.json` (which is symlinked to `C:\Users\<username>\.gemini\antigravity\mcp_config.json`).

### 2. Transport Optimization
While CodeWhale uses SSE transport for Mem0 to bypass its 120s stdio timeout, Antigravity has native SSE client issues that cause `Method Not Allowed` (405) errors. To resolve this, **Mem0 is run as a stdio process** for Antigravity using `uv run`, connecting to the same running Mem0 Docker containers on port `8888`.

### 3. Tool Filtering (excludeTools)
To prevent agent confusion and tool redundancy (e.g., memory tools exposed by both Serena and Mem0), we filter out unused/unneeded tools using the client-side `excludeTools` property:

*   **Serena**: Memory tools (`write_memory`, `read_memory`, `list_memories`, `delete_memory`, `rename_memory`, `edit_memory`) and GUI/setup tools (`onboarding`, `open_dashboard`, `initial_instructions`) are **excluded**, leaving Serena focused on LSP semantic search, refactoring, and project switching. `activate_project`/`get_current_config` are **kept** — Serena runs in multi-project mode (see `docs/ARCHITECTURE.md`), and excluding those two would strand a session on whichever repo activates first with no way to switch to another.
*   **Mem0**: The `health` check tool is **excluded**, leaving only the 4 core memory storage and search tools.
*   **Superpowers**: All workflow tools are left active.

---
name: mcp-servers-setup
description: Configure and use the self-hosted MCP server stack (Serena, Graphify, Omnigraph memory, Superpowers, Playwright) for token-efficient coding, and publish container images to the private Harbor registry.
---

# MCP Servers Setup

This skill ensures proper configuration and usage of the self-hosted MCP server
stack across all repositories under your `${CODE_ROOT}` (the parent directory of
your projects).

## First Action — Always

**On every session start (first prompt), activate the Serena MCP server, recall
structured project memory from Omnigraph, and use Graphify when the repo already
has a graph:**

```
mcp_serena_activate_project → (current project name or path)
# Recall typed memory (rules/decisions/preferences) for this project + global scope:
#   follow skills/structured-memory/SKILL.md (Omnigraph queries)

# If graphify-out/graph.json exists, prefer graph queries for broad structure questions
```

This loads the full project context: module structure, recent decisions,
commands, and constraints. Do this before any code changes — the memory graph is
the ground truth for what exists and how it works. Memory details:
`skills/structured-memory/SKILL.md`.

## Active MCP Servers

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

**Note**: Serena memory tools are disabled. Use Omnigraph (structured memory) for all persistent memory instead.

### Omnigraph — Structured Cross-Project Memory

The default memory layer. Instead of unstructured blobs, write **typed** nodes
(`Decision / Rule / Preference / Convention / Component / Task`) edged to a
`Project`, and recall them via fused graph + vector + full-text queries. MCP tools:
`schema / branches / queries / mutations / ingest`.

| Action | How |
|--------|-----|
| Recall project memory | `query` for rules/decisions/preferences edged to the project |
| Persist a durable fact | `mutate` (a few nodes) or `load` `mode: merge` (bulk), on a branch, then merge |
| Global preferences | `Preference` nodes with `scope: global`, in the shared `memory` graph |

Full protocol and schema: `skills/structured-memory/SKILL.md`. **Each repo has its
own graph** named after the repo folder (`OMNIGRAPH_GRAPH_ID=<repo>`); the shared
`memory` graph holds only global-scope `Preference`s. Isolation is by graph, plus
`Project` edges inside it — never a per-call `user_id`. Omnigraph is the only memory
layer; there is no fallback (ADR 0003).

### Graphify — Project Graphs

| Tool | Purpose |
|------|---------|
| `graphify query` | Ask graph-level questions about the repo |
| `graphify path` | Trace relationships between concepts |
| `graphify explain` | Inspect a node or community in graph terms |

**Usage**:
```
graphify query "what connects the CLI setup to the MCP config?"
graphify path "apply-cluster.sh" "cluster.yaml"
```

**Rule**: Graphify does not replace Serena. Use Serena for symbol-level navigation and Graphify for broader relationship questions when a graph exists.

#### Per-repo setup — THREE gates, and every one fails silently

Graphify is **repo-bound**: the server resolves `graphify-out/graph.json` relative to
its mount, so one server serves exactly one repo. All three gates must be open, and
none of them errors when shut — you get wrong answers or a missing tool, never a
message. Miss gate 1 and another repo's graph answers for yours (this is what happened
to `Invest`/`Server` until 2026-07-19: a user-scope entry pinned to `agent-skills`
answered for every repo).

| # | Gate | Where | Symptom if missed |
|---|------|-------|-------------------|
| 1 | Server declared **project-scoped**, mounting *this* repo | `<repo>/.mcp.json` | another repo's graph answers, silently |
| 2 | Server **approved** | `<repo>/.claude/settings.local.json` → `enabledMcpjsonServers` | tool absent; no prompt, no error |
| 3 | Graph **built** | `<repo>/graphify-out/graph.json` | server starts, serves nothing |

Gate 2 is the one that bites: adding a server to `.mcp.json` is **not** enough — an
unapproved project server is skipped without a word. `.mcp.json` is tracked and cannot
approve itself (deliberate: a repo must not auto-run servers on clone). Approve in the
untracked local settings, or set `enableAllProjectMcpServers: true` there.

```jsonc
// <repo>/.mcp.json — gate 1. Mount THIS repo; the image's WORKDIR is already /repo.
"graphify-docker": {
  "command": "docker",
  "args": ["run","-i","--rm","-v","${CODE_ROOT:-/home/s/code}/<REPO>:/repo","graphify-mcp:latest"]
}
```
```jsonc
// <repo>/.claude/settings.local.json — gate 2 (untracked)
{ "enabledMcpjsonServers": ["omnigraph", "graphify-docker"] }
```
```bash
# gate 3 — deterministic AST graph, no LLM/API key. --user is REQUIRED: the container
# runs as root and bind-mount writes land root-owned, so the next rebuild (and any
# host-side `graphify`/git clean) fails with permission denied on your own files.
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/repo" -w /repo \
  --entrypoint python graphify-mcp:latest -m graphify update .
```

**Never put `graphify-docker` (or `omnigraph`) in user scope** (`~/.claude.json` →
`mcpServers`). Both are repo-bound; one global entry serves one repo's data to all of
them. Keeping user scope empty of them also means no same-named entry can ever compete
with the project one, which sidesteps the precedence question entirely.

Verify all three gates for every repo at once (`--fix`/`-Fix` applies the safe
repairs; both exit non-zero so they work in hooks/CI):
```bash
bash infra/mcp-servers/scripts/linux/check-graphify-scope.sh --fix          # Linux/WSL
```
```powershell
.\infra\mcp-servers\scripts\windows\check-graphify-scope.ps1 -Fix           # Windows
```

**On Windows, set `CODE_ROOT`.** The committed mounts read
`${CODE_ROOT:-/home/s/code}/<repo>:/repo` — that POSIX default is right on Linux
and cannot exist on Windows, so docker mounts nothing and the server answers from
an empty graph. `setx CODE_ROOT "C:/Users/<you>/code"`, then restart Claude Code.
The PowerShell checker flags this case by name. Ownership differs too: Docker
Desktop surfaces container-created files as the host user, so `--user` matters
only on Linux/WSL — the `.ps1` deliberately omits that gate.

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
| omnigraph-server | `:8080` | — | The memory graph (bearer-auth; `/healthz` is open) |
| MinIO | `:9000` API / `:9001` console | — | S3 store backing Omnigraph |
| omnigraph-viewer | `:8090` | — | Read-only web UI (put Authelia in front if exposed) |
| Ollama | `:11434` | `nomic-embed-text` (768-dim, CPU-fine) | Embeddings — **optional** |
| OLLAMA_KEEP_ALIVE=24h | Windows env | — | Keep models in VRAM |

Ollama is optional: without it, recall degrades to graph traversal + full-text rather
than failing. **No Qdrant, no Postgres, no LLM API key** — those were Mem0's, and Mem0
was removed entirely (ADR 0003). `bge-m3` (1024-dim) was Mem0's embedder and is *not*
this graph's: the graph is `Vector(768)`/`nomic-embed-text`, and mixing dimensions makes
`nearest()` return garbage.

### Harbor — Private Container Registry

**Convention: any container image an agent builds to share or deploy goes to
Harbor, never Docker Hub.** Harbor is the homelab registry (web UI, per-project
RBAC/robot accounts, Trivy scanning) at `harbor.ohje.ooguy.com`, backed by the
NFS share on cloud.vm. Local-only throwaway builds (e.g. `docker compose --build`
for a stack that runs in place) do **not** need pushing — only images meant to be
pulled elsewhere.

```bash
# build locally, then publish to Harbor under a project namespace (create the
# project once in the UI: e.g. `agents`, `infra`)
docker build -t myimage:latest .
docker login harbor.ohje.ooguy.com                       # admin / project user / robot token
docker tag  myimage:latest harbor.ohje.ooguy.com/agents/myimage:latest
docker push harbor.ohje.ooguy.com/agents/myimage:latest
# elsewhere: pull instead of rebuilding
docker pull harbor.ohje.ooguy.com/agents/myimage:latest
```

Deployment / admin (installer, storage path, Caddy exposure, secrets) is the
single source of truth in the Server repo: `server/cloud/harbor/README.md`.

## Project Initialization

> ⚠️ **On coding.vm the Omnigraph stack is already deployed from
> `Server/server/coding/mcp-servers/docker-compose.yml`** (canonical, Dockhand,
> viewer bound to `0.0.0.0:8090` for Caddy). The compose below is a **local/dev**
> variant — it binds `127.0.0.1` and shares the project name `mcp-servers`, so
> running it on coding.vm clobbers the live viewer and takes
> `omnigraph-ui.ohje.ooguy.com` down. On coding.vm, manage the stack from the
> canonical Server compose instead. Use the below only for a standalone/dev host.

```bash
cd ${AGENT_SKILLS_ROOT}/infra/mcp-servers
docker compose --env-file .env.shared --env-file .env.server -f docker-compose.server.yml up -d
curl -fsS http://localhost:8080/healthz                  # server up
python3 scripts/_omni_env.py                             # what stack docker actually has
```

## Recommended Workflow

1. Start the server: `docker compose --env-file .env.shared --env-file .env.server -f docker-compose.server.yml up -d`
2. Activate Serena project: `mcp_serena_activate_project(project="repo-name")`
3. Recall memory from Omnigraph (see `skills/structured-memory/SKILL.md`)
4. Build or refresh Graphify graphs when the repo has a graph target
5. Use Serena for navigation, Omnigraph for memory, Graphify for graph queries, and Superpowers for workflows
6. End session: persist durable decisions to Omnigraph; services keep running

## Troubleshooting

```powershell
# Full health check
curl -fsS http://localhost:8080/healthz                  # omnigraph server
curl -fsS -H "Authorization: Bearer $env:OMNIGRAPH_TOKEN" http://localhost:8080/graphs

# Serena
serena project list
serena --version

# Omnigraph (open health probe, then an authenticated call)
curl -fsS http://localhost:8080/healthz
curl -fsS -H "Authorization: Bearer $env:OMNIGRAPH_TOKEN" http://localhost:8080/graphs

# Ollama (optional — embeddings only)
curl http://localhost:11434/api/tags
```

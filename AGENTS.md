# Agent Instructions

Reusable agent skills + per-repo starters + a self-hosted MCP runtime.
**Keep this file and starters as thin pointers — a skill's `SKILL.md` is the source of truth.**

## Start at the router

**`skills/repository-index/SKILL.md`** — maps every MCP server and skill to the trigger that
loads it. Read it first; it tells you which of these to open.
(`skills/SYNC.md` is the vendoring ledger, not a router.)

| Skill | Load when |
|---|---|
| `coding-principles` | **any** implementation, refactor, bugfix |
| `structured-memory` | **every** session — recall at start, persist at end |
| `structured-memory/references/operations.md` | **before** any Omnigraph query/mutate/load/sync |
| `html-working-documents` | plan / research / review / report / diagram / prototype |
| `mcp-servers-setup` | wiring or debugging the stack |
| `swarm-orchestration` | multi-file work (drives `pr-approval-agent`, `qa-swarm`, `review-triage`, `no-mistakes`, `babysit-prs`) |
| `herdr-orchestration` | agent work that must **outlive the session**, be human-supervised, use a non-Claude agent, or wait on a long-running process |

## Memory

- **One graph per repo**, named after the folder. This repo → `agent-skills`.
- Pinned by `OMNIGRAPH_GRAPH_ID` in `.mcp.json`; **no tool takes a graph argument**.
- `memory` graph = 2 global `Preference`s only (already Principles 2 & 6 of
  `coding-principles`). **Never write project data there.**
- Omnigraph is the only memory layer — no fallback (ADR 0003).

Two env vars must exist **before launch** (never committed):

| Var | Unset ⇒ | Get it from |
|---|---|---|
| `OMNIGRAPH_TOKEN` | empty bearer → memory **silently dead** | `infra/mcp-servers/.env.shared` |
| `OMNIGRAPH_NET` | wrong docker network → `fetch failed` | `python3 infra/mcp-servers/scripts/_omni_env.py` |

Both: `infra/mcp-servers/omnigraph-setup/setup-agent-memory.ps1` (or `.sh`) — `-Check` to diagnose.

> **Graph looks empty? Config bug until proven otherwise — do NOT rebuild.**
> `0 rows except 2 Preferences` **is** the `memory` graph. A same-named `omnigraph` in
> `~/.claude.json` (user scope) silently outranks `.mcp.json`. Run `setup-agent-memory -Check`.

**Declared ≠ live.** Verify against the server (`graphs_list`, `schema_get`, `docker inspect`),
never a config file — an unapplied cluster rejects edge types *silently*.

## Infrastructure (`infra/`, see `docs/architecture.md`)

| Path | What | Note |
|---|---|---|
| `mcp-servers/` | the stack + `cluster/` config + `scripts/` + `omnigraph-setup/` | manual: `omnigraph-setup/SYNC-MANUAL.md` |
| `local-ai/` | Ollama, LiteLLM, Open WebUI, OpenHands | **optional except Ollama**: serves `nomic-embed-text` (`:11434`) = Omnigraph's `Vector(768)` recall. Without it recall degrades to traversal + full-text. LiteLLM (`:4000`) = one OpenAI-compatible endpoint → `swarm-orchestration` model routing |
| `remote-access/` | Herdr multiplexer, Antigravity remote UI | |

Memory path needs no Postgres, pgvector, or LLM API key.

**Harbor** = self-hosted registry. Never install locally; push images to the remote instance.

## Hard rules

- **Line endings.** `.gitattributes` pins `*.sh`/`*.py`/units/configs to `eol=lf`; `*.ps1` to
  `crlf`. A CRLF shebang → kernel seeks `bash\r` → script cannot run. Never "fix" a script by
  re-saving as CRLF.
- **Compatibility.** Give each agent its native instruction file; keep adapters short.
  See `docs/agent-compatibility.md`.

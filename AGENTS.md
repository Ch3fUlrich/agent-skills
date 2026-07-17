# Agent Instructions

This repository stores reusable AI-agent skills, per-repo starter adapters, and a
self-hosted MCP runtime. Keep starters and this file as **thin pointers** — a
skill's `SKILL.md` is the single source of truth; never copy its workflow here.

## Skills (source of truth in `skills/`)

**Start at the router:** `skills/repository-index/SKILL.md` maps every MCP server and
skill to the trigger that should load it. Read it first; it tells you which of the below
to open. `skills/SYNC.md` is the vendoring ledger for the borrowed skills, not a router.

- **Coding discipline** — for any implementation, refactor, or bugfix, follow
  `skills/coding-principles/SKILL.md` (DRY, TDD, single responsibility,
  document-the-why, changelog/ADR backtracking, MCP-first navigation).
- **Memory** — at session start and end, follow
  `skills/structured-memory/SKILL.md` to recall and persist typed memory in Omnigraph.
  Before any Omnigraph query/mutate/load/sync, read
  `skills/structured-memory/references/operations.md` — the operational rules and
  gotchas (edge casing, insert-xor-delete, duplicate-edge handling, never overwriting a
  populated `main`, lowercase slugs, embeddings) that keep the graph clean without
  troubleshooting.
- **HTML working documents** — for long planning, research, review, report,
  diagram, prototype, and handoff work, follow
  `skills/html-working-documents/SKILL.md`.
- **MCP stack usage** — `skills/mcp-servers-setup/SKILL.md`.
- **Multi-agent orchestration** — `skills/swarm-orchestration/SKILL.md`, with the
  review-gate skills it drives (`pr-approval-agent`, `qa-swarm`, `review-triage`,
  `no-mistakes`, `babysit-prs`).

## Memory in one paragraph

**Each repo has its OWN Omnigraph graph, named after the repo folder** — this repo's is
`agent-skills`. A bridge is pinned to exactly one graph by `OMNIGRAPH_GRAPH_ID`, and no
tool takes a graph argument, so `.mcp.json` here points at `agent-skills` and nothing else.
The shared **`memory`** graph holds only two global-scope `Preference`s (TDD-by-default,
MCP-first navigation) — both already Principles 2 and 6 of `coding-principles` — so there
is no second bridge to read it. Never write project data to `memory`. Omnigraph is the
only memory layer; there is no fallback (ADR 0003).

`.mcp.json` reads two env vars that must exist before the agent launches — they are
deliberately not committed:

| Var | Why |
|---|---|
| `OMNIGRAPH_TOKEN` | the bearer; a tracked file must never hold it. Unset ⇒ the bridge starts with an empty token and **memory silently does not work** |
| `OMNIGRAPH_NET` | the docker network, which **differs per host** (`mcp-server_mcp-net` locally, `mcp-servers_default` on central). Probe it: `python3 infra/mcp-servers/scripts/_omni_env.py` |

**Declared ≠ live.** Verify against the running server (`graphs_list`, `schema_get`,
`docker inspect`), never by reading a config file. An unapplied cluster rejects edge types
*silently*, which is how five relational edges went missing for weeks.

## Compatibility goal

Prefer broad, plug-and-play compatibility over a single-vendor setup. Provide the
native instruction file each agent expects and keep each adapter short. See
`docs/agent-compatibility.md`.

## Infrastructure

Self-hosted runtime under `infra/` — see `docs/architecture.md`:

- `infra/mcp-servers/` — the MCP stack (Serena, Graphify, Omnigraph memory,
  Superpowers, Playwright, Context7) + the Omnigraph cluster config
  (`cluster/`), its helper scripts (`scripts/`), and the local↔central sync
  (`omnigraph-setup/` — operator manual: `omnigraph-setup/SYNC-MANUAL.md`).
- `infra/remote-access/` — Herdr multiplexer + Antigravity remote UI.
- `infra/local-ai/` — self-hosted LLM inference + UI + agent stack (Ollama, LiteLLM,
  Open WebUI, OpenHands). **Optional, with one exception that matters:** its **Ollama**
  serves `nomic-embed-text` on `:11434`, which is the embedder Omnigraph's `Vector(768)`
  semantic recall depends on. Without it, memory still works — recall just degrades to
  graph traversal + full-text. **LiteLLM** (`:4000`) gives one OpenAI-compatible endpoint
  over many providers, which is how `swarm-orchestration` can route roles to different
  models. **OpenHands** is an alternative agent runtime (compared in
  `skills/swarm-orchestration/CUSTOM_ORCHESTRATION_VS_OPENHANDS.md`).

Nothing in the memory path needs Postgres, pgvector, or an LLM API key.

We also use **Harbor** as a self-hosted container registry. 
- Do **not** install the Harbor registry locally on this device. 
- The container should be pushed to a remote cloud server where it acts as a centralized registry. Agents and deployment scripts can push/pull images to and from the remote Harbor instance whenever needed.

## Line endings — non-negotiable

`.gitattributes` pins `*.sh`/`*.py`/systemd units/configs to `eol=lf` (`*.ps1` stays
`crlf`). A CRLF shebang becomes `#!/usr/bin/env bash\r`, so the kernel looks for an
interpreter literally named `bash\r` and the script cannot run — on Linux or via
`./script`. Do not "fix" a script by re-saving it with CRLF.

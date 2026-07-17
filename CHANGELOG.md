# Changelog

All notable changes to this repository are recorded here, newest first.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added — one-command sync setup (2026-07-17)

`omnigraph-setup/setup-sync.ps1` (Windows) and `omnigraph-setup/setup-sync.sh`
(Linux/macOS/WSL) take a host from "the stack is running" to "memory syncs every 5 minutes":
they read `OMNIGRAPH_TOKEN` from `.env.shared`, detect `DOCKER_NET` from the **running**
`omnigraph-server` (never a config file — it differs per host and a wrong value fails
silently), write `omnigraph-setup/.env`, and register a Scheduled Task / systemd `--user`
timer. `--interval`, `--show`, `--no-schedule`, `-Unregister`.

Two properties worth keeping when editing them:

- **A dry run gates the schedule.** Nothing is scheduled unless a full DRY_RUN sync passes,
  so a broken setup fails at setup time rather than silently every 5 minutes forever.
- **A pre-flight gates the write.** Both servers must answer `200` *before* `.env` is
  touched, so a typo'd `--central-token` cannot replace a working config with a broken one.
  (Found by testing exactly that: the first version wrote first and validated after.)
  Same rule `pull_graph.py` learned: never destroy old state until its replacement works.

Verified on Windows end-to-end: the registered task ran on its own trigger with
`LastTaskResult=0`, and all five graphs stayed identical local↔central with no duplicates.

### Fixed — the sync re-pushed 52 unchanged nodes on every run (2026-07-17)

Every run reported nodes as "changed" that were byte-identical to central — 4 for
agent-skills, 52 of basic-analysis's 135, 6, 13 — and re-pushed them forever.

The count was exactly the number of records containing **non-ASCII bytes**. `pushset` read
the local export from **stdin**, which Python decodes with the *locale* encoding (`cp1252`
here), but read the central export via `open(…, encoding="utf-8")`. The same text became two
unequal strings, so every node with an em dash, arrow or umlaut compared as changed. Nothing
was ever corrupted — a cp1252 decode/encode round-trip is byte-lossless — but each run wrote
to central for no reason. `omnigraph_jsonl.py` now forces UTF-8 stdio itself
(`_force_utf8_stdio`) rather than relying on a `PYTHONIOENCODING` that only one of its three
call sites would have carried. All five graphs now report a **0-node, 0-edge** delta.

The same bug class was latent and **worse** in `sync-windows.ps1`, where it damages payloads
rather than just comparisons: native-command output is decoded with `[Console]::OutputEncoding`
(the OEM code page, cp850) and text piped *into* a native command is encoded with
`$OutputEncoding` (ASCII on Windows PowerShell 5.1, which turns `→` into `?`). It now pins
UTF-8 for all three hand-offs before any data moves. Its `-DryRun` also swallowed the central
verify verdict (`| Out-Null`) and never computed the delta — both fixed, so a dry run can now
be believed and reports what it would push.

Regression tests (`test_omnigraph_jsonl.py`, 9/9) drive the CLI as a subprocess with **raw
bytes** and a legacy child encoding; the previous `text=True` helper could not catch this,
because it encoded and decoded with the same parent locale and the mismatch cancelled out.

### Fixed — the local↔central sync, which was corrupting central (2026-07-17)

Running the sync **duplicated every edge on all four central project graphs** (agent-skills
27→54, basic-analysis 120→221, invest 81→125, homelab-server 18→32) while reporting `rc=0`
and "pulled central main -> local main". The pull had in fact failed on every graph. Central
was repaired (dedup reproduced the git seeds byte-for-byte on all four — two independent
sources agreeing) and the causes fixed:

- **The push sent the whole local export** onto a device branch forked from `main`. Edges
  have no `@key`, so every edge central already had was appended. It now sends a **delta**
  (`omnigraph_jsonl.py pushset`): changed/new nodes only, and only edges central lacks.
- **Pushing an *unchanged* node** still bumps that table's version, so the merge died with
  `Concurrent modification: table version N already exists`. Identical nodes are now
  skipped; an empty delta pushes nothing at all — the common case on a timer.
- **The device branch is gone.** On v0.8.1 `branch create` can hit a Lance internal error
  ("Clone operation should not enter build_manifest") and `branch merge` the above. It
  existed for "review before merge", which is meaningless on an unattended timer; the delta
  push goes straight to central `main`. Safety is the delta + backups + verify gates.
- **The pull no longer uses `load --mode overwrite`** on a populated graph (Lance bug — and
  it can *land while exiting 1*, so even its failure is untrustworthy). New
  `omnigraph-setup/pull_graph.py` purges then loads into the empty graph, pre-flights that
  the load path is reachable **before** purging, and restores from backup on failure.
- **Failures are visible.** A non-zero exit from a native command is not a PowerShell
  terminating error, so the old `try/catch` never fired. Both scripts now check exit codes
  and honour `verify`'s verdict instead of piping it to `Out-Null` / `|| true`.
- `omnigraph-sync.sh` was rewritten to the same logic — it previously could not run on
  Windows at all (bind-mounted a `mktemp -d` path Git Bash mangles) and carried the same
  duplicate-push bug. Both platforms now drive the same two Python helpers.

Verified: repeated full runs, `rc=0`, all five graphs identical central↔local and
duplicate-free, **zero edge growth** across consecutive runs. Operator manual:
`infra/mcp-servers/omnigraph-setup/SYNC-MANUAL.md` (5-minute cadence, config,
troubleshooting, known limits).

### Changed — `infra/mcp-servers/setup/` → `infra/mcp-servers/omnigraph-setup/` (2026-07-17)

`setup/` said nothing about what it holds: the Omnigraph sync/reconcile tooling, not
general project setup. Every reference updated across 26 files, plus the live
`as-sync-automation` node's `location` on both local and central — a rename that leaves
memory pointing at a dead path is the same drift this repo keeps getting bitten by.

### Added — `.gitattributes` (2026-07-17)

The repo had no eol policy, so with `core.autocrlf=true` a Windows checkout rewrote shell
scripts to CRLF; the shebang became `#!/usr/bin/env bash\r` and the script could not run.
`*.sh`/`*.py`/units/configs are now pinned `eol=lf` (`*.ps1` stays `crlf`), and CR was
stripped from 33 tracked files.

### Fixed — graphify clustering on mixed str/int node ids (2026-07-17)

`basic-analysis` (14,275 str + 17 int ids) crashed with `TypeError: '<' not supported
between instances of 'int' and 'str'`, leaving nodes/edges current but community labels
stale (2% coverage). `scripts/patch-graphify-cluster-sort.py` adds `key=str` to the bare
node-id sorts upstream missed — in `build.py` (where the CLI actually dies first) as well as
`cluster.py`. Result: `cluster-only` completes, 934 communities, coverage 2% → 100%.

### Removed — Mem0, entirely (2026-07-16)

Omnigraph is the memory layer, with **no fallback** — see the new
[ADR 0003](docs/decisions/0003-remove-mem0-fallback.md) for why the escape hatch cost
more than it insured (ADR 0001 keeps the original Omnigraph rationale; only its fallback
clause is void). The stack now needs no Postgres/pgvector and no LLM API key.

- Deleted `servers/_fallback/` (mem0-custom, mem0-mcp, mem0-dashboard), the
  `mem0-fallback` Compose profile and its 4 services, and the Mem0/Postgres/DeepSeek env
  vars from `.env.server.example`.
- **Deleted the Mem0-era orchestration scripts** — `scripts/{windows,linux}/{setup,start,
  stop,test,migrate}.*` and `scripts/test_mcp_tools.py`. They were not merely
  mem0-flavoured: they stood up the Mem0 stack, health-checked `localhost:8888`, and
  their bare `docker compose` calls had been failing with "no configuration file
  provided" ever since the server/client compose split. The documented setup path had
  been dead for months. Docs now point at the compose commands that actually work.
- Deleted the legacy `docs/ARCHITECTURE.md` + `docs/TOKEN_SAVINGS.md` — self-declared
  duplicates of `docs/architecture.md`, structurally Mem0 documents.
- Swept every remaining live reference (README, AGENTS, architecture, infra README,
  TODO, runbook, troubleshooting, install guide, server READMEs, ignore files) and
  removed the obsolete `ba-conv-mem0-project-isolation` Convention (`user_id=` on "every
  Mem0 call") from the live `basic-analysis` graph. History — CHANGELOG, ADRs,
  `docs/superpowers/**` — is left intact.

### Changed — Omnigraph rules realigned to the upstream best-practices docs

Checked `skills/structured-memory/` against `omnigraph://best-practices/*` and verified
each claim against the running server rather than adopting it on faith:

- **Corrected a rule that was wrong for our schema.** `operations.md` warned that "blind
  retries duplicate append-only nodes like `Decision`" — that taxonomy is the upstream
  *cookbook's* schema, not ours. Every type in `memory.pg` is `@key(slug)`; verified two
  identical `insert Preference` calls produce **one** node. Nodes are safe to retry;
  **edges** (no `@key`) are the real risk.
- **Documented behaviour worse than upstream describes.** The docs say `load --mode
  merge` leaves an `@embed` vector "stale". Verified: it **erases** it — merging a
  `Decision` whose record omits `embedding` nulls the field, and an unembedded
  `Decision` is *dropped* from `nearest()`, not ranked low. Measured 3/6 `agent-skills`
  and 2/17 `basic-analysis` Decisions silently unsearchable this way.
- **And that the documented fix does not work.** On v0.8.1 *both* re-embed paths fail
  with the same Lance bug on a populated graph (`overwrite` →
  `stage_create_btree_index`; `merge` carrying vectors → `LanceError(Arrow)`), so
  `populate-embeddings.py` only works against a fresh graph. Recorded as a known
  limitation instead of an unfollowable instruction. A failed overwrite can leave Lance
  HEAD ahead of the manifest so all loads to that graph fail while reads work —
  `docker restart omnigraph-server` recovers it, no data lost.
- Added, from upstream: `load --from` forks a review branch in one shot; branches are
  short-lived (create → load → verify → merge → **delete**) and a stray one **blocks
  `schema apply`** (so a leftover `device/<host>` branch breaks `apply-cluster.sh`);
  "scope first, rank second" before `nearest`/`bm25`/`rrf`; `409 manifest_conflict` and
  `429` are always safe to retry; `sync_branch()` is a leaked internal directive, not a
  tool; pick `mutate` over `load` for a handful of records.
- Rewrote `references/schema.md`'s stale framing; `prompts/omnigraph-central-bring-up-to-date.md`
  replaces the two narrower central prompts.

### Fixed — per-project graph isolation actually deployed (2026-07-16)

The isolation model was declared in git but **never applied to a running server**.
Root cause: `scripts/apply-cluster.sh` sourced a `./.env` that never existed (the
convention is `.env.shared` + `.env.server`), so it died on line 15 under `set -e`
and had never run. Everything below followed from that one failure.

- **`apply-cluster.sh` made runnable** — sources the right env files, uses the real
  docker network (`mcp-server_mcp-net`, not `mcp-servers_default`), and converts
  container paths for Git Bash (MSYS rewrote `--config /cluster` to
  `C:/Program Files/Git/cluster`). Cluster converged: 5 graphs + updated schema.
- **Five relational edge types were missing from the live schema** — `Tracks`,
  `Affects`, `Addresses`, `Implements`, `DependsOn`. Every agent following the
  "link richly" rule hit `T4: unknown edge type`, and every seed line using them
  failed **silently**. Now live; 7 orphaned hub edges repaired (4 `Tracks`,
  3 `ConstrainsProject`) — the nodes that had been rendering as "global".
- **Seed loader corrected** (`docker-compose.server.yml`): loads each seed into the
  graph matching its **file name** (it hardcoded `--graph memory`, i.e. actively
  maintained the shared model it was meant to replace), declares the compose
  network (it had none, so it could never resolve `omnigraph-server`), and now
  **exits nonzero** on a failed seed instead of `|| echo WARN`.
- **All 4 projects migrated to their own graphs, `memory` pruned to globals-only.**
  Verified: 160 project nodes + 2 global `Preference`s = 162 = the old `memory`;
  163/163 edges. `memory` is now 2 nodes / 0 edges.
- **Seeds refreshed from live** — they had drifted badly (9 vs 16 decisions; tasks
  marked `planned` that were complete), and the loader merges by `@key(slug)` on
  every boot, so a stale seed **silently overwrites newer live values**.
- **`add-project-graph.sh`** told you to set `OMNIGRAPH_GRAPH` — the *viewer's*
  variable. The bridge reads `OMNIGRAPH_GRAPH_ID`; you would silently stay on
  `memory`.
- **`skills/structured-memory/references/schema.md` rewritten** — it documented kebab-case edge names
  (`decided-in`, `constrains`), a `relates-to (any → any)` edge that does not
  exist, and an `ingest` tool that is actually `load`. Its JSONL example would have
  failed on load.

### Added

- **`scripts/split-project-graph.py`** — carve a project's subgraph out of the
  shared graph (`--source memory --apply`, additive), refresh a seed from live
  (`--write-seed`), or prune the source (`--prune-source`, gated on verifying every
  node is mirrored in its project graph first). No such migration tooling existed.
- **Reading globals needs a second bridge.** `OMNIGRAPH_GRAPH_ID` pins a bridge to
  one graph and no tool takes a graph argument, so a project-scoped agent could not
  reach the global `Preference`s its own skill told it to recall. Repos now declare
  `omnigraph` (own graph) + `omnigraph-globals` (`memory`, read-only) — see this
  repo's `.mcp.json`.
- **Viewer: graph chips + focus-on-click.** The graph dropdown and per-project tabs
  are replaced by chips in the tab bar (graph ≈ project now): click to switch,
  ctrl/⌘/shift-click to show **several graphs at once**, each as its own coloured
  cluster. Clicking a node gathers its 1-hop neighbours at the centre and pushes
  everything unrelated out to a faded ring (`Esc`/click-away/re-click to clear).
  Node ids are namespaced `<graph>::<slug>` so slugs cannot collide across graphs.
- **`prompts/omnigraph-fix-central-server.md`** — handoff prompt to bring the
  central `coding.vm` instance through the same convergence, with gates and the
  sync/dedup warning below.
- **`webpage/orchestration-upgrade-plan.html`** — repo audit, bug register, router
  spec, T0–T3 hardware tiers, the L0–L5 loop architecture, and the
  crowds-vs-experts policy for Best-of-N.

### Known issues

- **Sync and dedup are single-graph and currently unsafe.** `omnigraph-sync.sh`
  (`GRAPH="${GRAPH:-memory}"`) pulls central → local with `load --mode overwrite`,
  so pointing a pruned local at a stale central **restores the pruned data and
  undoes the migration**; the 4 project graphs are never synced at all.
  `dedup-graph.py` hardcodes `--graph memory` in 3 places. **Keep
  `omnigraph-sync.timer` / `dedup-graph.timer` disabled until both iterate graphs.**
- The central `coding.vm` server has not been converged — same un-run
  `apply-cluster.sh`. The project graphs currently exist on one client only.
- **Exposed the stack to the internet** via the OPNsense/Caddy reverse proxy:
  `omnigraph.ohje.ooguy.com` (API, bearer only), `omnigraph-ui.ohje.ooguy.com`
  (viewer) and `omnigraph-minio.ohje.ooguy.com` (MinIO console), the latter two
  behind Authelia (admin-only).
- Interactive **memory viewer**: project tabs (All/Global/per-project), a
  force-directed graph (clickable while animating, zoom/pan, edge details), a
  filterable/sortable table, and search highlighting with match explanations.
- Deployed the Omnigraph memory stack on coding.vm via the single-source
  `Server/server/coding/mcp-servers/docker-compose.yml` (server + MinIO + viewer),
  seeded, with real Ollama `nomic-embed-text` embeddings and working semantic
  search. `search_decisions` stored query.
- Credential-**access** memory (methods + file locations, never secret values)
  stored in the `homelab-server` graph, plus a hard rule against storing secrets
  in the internet-exposed graph.
- `infra/mcp-servers/omnigraph-setup/`: client/server setup guide, `client-setup.sh`,
  and `omnigraph-sync.sh` (+ systemd timer) for automatic device-branch sync.
- `coding-principles` skill + starter: DRY, TDD, single responsibility,
  document-the-why, changelog/ADR backtracking, MCP-first navigation.
- `structured-memory` skill: typed cross-project memory protocol on Omnigraph
  (schema + recall/persist workflow).
- `infra/remote-access/herdr/`: Herdr agent-multiplexer setup for Linux, macOS,
  and Windows, with helper scripts and a remote-access comparison guide.
- Omnigraph + MinIO as the default memory stack in `infra/mcp-servers/`, plus
  `servers/omnigraph/README.md`.
- ADRs: `0001-omnigraph-over-mem0`, `0002-herdr-multiplexer`.
- Restructure spec + implementation plan under `docs/superpowers/`.

### Changed
- **Repository restructured** into three pillars: `skills/` (reusable skills),
  `starters/` (per-repo adapters), `infra/` (self-hosted runtime:
  `mcp-servers/` + `remote-access/`). Loose dirs `Gen/`, `prompt/`,
  `repositories/` consolidated into `prompts/`; `mcp-servers/` and
  `antigravity-remote-ui/` moved under `infra/`.
- Default MCP memory layer switched from Mem0 to Omnigraph. Mem0 retained as an
  off-by-default `mem0-fallback` Compose profile. See
  `docs/decisions/0001-omnigraph-over-mem0.md`.
- Root instruction files (`AGENTS.md`, `CLAUDE.md`, new `GEMINI.md`) reduced to
  thin pointers at the skills.
- Infra scripts/configs de-personalized: hardcoded paths replaced with
  `${AGENT_SKILLS_ROOT}` / `${CODE_ROOT}` / `${SERENA_HOME}` (and PowerShell
  `$env:` equivalents).

### Removed
- Committed generated `graphify-out/` output is no longer tracked.

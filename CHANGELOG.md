# Changelog

All notable changes to this repository are recorded here, newest first.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

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
- `infra/mcp-servers/setup/`: client/server setup guide, `client-setup.sh`,
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

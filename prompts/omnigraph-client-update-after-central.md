# Prompt — update a CLIENT after central was brought up to date

> ## ⚠️ DO NOT SEND THIS — superseded by [`omnigraph-client-make-sync-safe.md`](omnigraph-client-make-sync-safe.md)
>
> Following this prompt on **2026-07-17 damaged central**: task 2 tells the client to run
> the sync, and the sync's push merge-loads the *whole* local export onto a device branch
> forked from central's `main`. Edges have no `@key`, so every edge central already had was
> appended a second time — agent-skills 27→54, basic-analysis 120→221, invest 81→125,
> homelab-server 18→32 — while the script reported `rc=0` and *"pulled central main -> local
> main"*. The pull had in fact failed on every graph. Central has since been repaired and
> re-verified clean.
>
> Two further errors in this prompt: it tells a **Windows** client to run
> `./omnigraph-setup/omnigraph-sync.sh`, which cannot work there (it bind-mounts a `mktemp -d` path
> that Git Bash mangles, so every graph fails with "local export/backup failed" while the
> server is up — `sync-windows.ps1` is the Windows twin); and its task-2 gate ("if sync
> reports duplicates … STOP") trusts the script's own report, which was the thing that lied.
>
> Kept as the record of what went wrong. **Use the superseding prompt.**

Send this to an agent **with shell + docker access on a client machine** (e.g. the
Windows dev box, compose project `mcp-server`, network `mcp-server_mcp-net`). It is the
companion to `omnigraph-central-bring-up-to-date.md`: central (coding.vm) has now been
reconciled, so each client must pull the clean state and drop its Mem0 remnants.

Copy everything below the line.

---

You are on a **client** machine whose local Omnigraph mirrors central
(`omnigraph.ohje.ooguy.com`, API central:8080). On **2026-07-16** central was brought up
to date: schema converged (11 edge types incl. `Tracks/Affects/Addresses/Implements/DependsOn`),
five isolated graphs (`memory` = globals only; `agent-skills`/`basic-analysis`/`invest`/
`homelab-server` = per-project), the Mem0 fallback **removed entirely** (agent-skills
ADR 0003), and every seed re-derived from central's live graphs. Your job: pull that
state down cleanly and remove Mem0 locally. Work top to bottom; **do not proceed past a
failing gate** — you have backups from task 1.

## 1. Pull + back up

- `git pull` the `agent-skills` checkout (gets the mem0 removal + refreshed
  `cluster/seed/*.jsonl` + the multi-graph sync/dedup scripts).
- Confirm your local stack: `cd infra/mcp-servers && python3 scripts/_omni_env.py`
  (expect your LOCAL network/mount, e.g. `network=mcp-server_mcp-net`). Trust its output.
- **Back up every LOCAL graph before syncing:**
  ```bash
  mkdir -p .graph-backup
  for g in $(curl -s http://127.0.0.1:8080/graphs -H "Authorization: Bearer $OMNIGRAPH_TOKEN" \
             | grep -o '"graph_id":"[^"]*"' | cut -d'"' -f4); do
    curl -s -X POST "http://127.0.0.1:8080/graphs/$g/export" \
      -H "Authorization: Bearer $OMNIGRAPH_TOKEN" -H 'content-type: application/json' -d '{}' \
      -o ".graph-backup/local-$g-$(date -u +%Y%m%d-%H%M%S).jsonl"
  done
  ```
  **Gate:** a non-empty backup per graph; you can state your local graphs + counts.

## 2. Reconcile local ↔ central (sync)

The sync is multi-graph aware. **Dry-run first**, confirm it lists all five graphs and
writes nothing, then run it for real:
```bash
DRY_RUN=1 ./omnigraph-setup/omnigraph-sync.sh      # expect: 5 graphs, no writes
./omnigraph-setup/omnigraph-sync.sh
```
It pushes your local onto a `device/<host>` branch on central, native-merges to central
`main`, verifies no duplicates, then **overwrites your local from clean central** (a
local backup + no-dup gate protect you; it restores on failure). Overwrite — not merge —
is used for the pull because merging vector-carrying `Decision` nodes trips a Lance bug on
v0.8.1.

**Gate:** sync exits 0; `curl …/graphs` locally now lists exactly `memory, agent-skills,
basic-analysis, invest, homelab-server`, and `memory` is globals-only (2 nodes / 0 edges).
If sync reports duplicates or a failed pull, STOP — your backup is intact.

## 3. Remove Mem0 locally

Central's `Server` compose already dropped it; your client's own MCP compose
(`agent-skills/infra/mcp-servers/docker-compose*.yml`, project `mcp-server`) and any
`claude mcp` registration may still carry it.
```bash
docker ps -a  | grep -iE 'mem0|postgres|pgvector'      # any stray mem0/pg containers?
claude mcp list | grep -i mem0                          # a lingering mem0 MCP endpoint?
```
Remove the mem0 service/profile/volume + `MEM0_*`/`POSTGRES_*`/`DEEPSEEK_*` env if present,
`docker compose down` the mem0 containers, and `claude mcp remove mem0` if registered.

**Gate:** no mem0/postgres containers; `claude mcp list` has no mem0; only Omnigraph +
serena remain.

## 4. Confirm memory works

Open a new agent session and confirm recall works against the project graph
(`OMNIGRAPH_GRAPH_ID=<project>`): a `graphs_list` shows the five graphs, `schema_get`
shows 11 edge types, and a `Task tracks Project` query parses (0 rows is fine). If a
relational edge still errors `T4: unknown edge type`, your local schema didn't converge —
re-run the sync, and if it persists, report it.

## Report back (with command output as evidence)

- `_omni_env.py` output (your live local network + mount).
- Local before/after: graphs + node/edge counts per graph.
- Sync dry-run + real-run output; confirmation `memory` is globals-only locally.
- Mem0 removal state (containers, compose, `claude mcp list`).
- Anything you could not verify or had to judge. Do not report success on a step you did
  not run and observe.

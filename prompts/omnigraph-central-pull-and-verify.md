# Prompt — pull the latest agent-skills onto CENTRAL and verify it end-to-end

Send this to an agent **with shell + docker access on `coding.vm`** (the host serving
`omnigraph.ohje.ooguy.com`). It is a **verification** pass, not a migration: central was
brought up to date on 2026-07-16 and the client's tooling has been rebuilt since. Your job
is to pull that work, confirm it behaves on **this** host, and fix what does not.

Copy everything below the line.

---

You are on **`coding.vm`**, the authoritative Omnigraph host. The `agent-skills` repo has
changed substantially since central was last touched. Pull it, then **prove** the stack
still works here. Everything below is a check with an expected answer — run it, compare,
and report the real output.

## The rule that governs this whole prompt

**Verify against the live system; never trust a script's own report, a doc, or this
prompt.** Every serious defect in this stack was a component reporting success while doing
the opposite: a sync that logged "pulled central main -> local main" while writing nothing;
a cluster config that was never applied; a seed loader that swallowed every failure. If a
check here disagrees with reality, **reality wins** — say so in your report.

## What changed since central was last touched

- **Mem0 is gone** (ADR 0003). No `mem0-fallback` profile, no Postgres/pgvector, no
  DeepSeek key. Omnigraph is the only memory layer — there is no fallback.
- **`infra/mcp-servers/setup/` was renamed to `infra/mcp-servers/omnigraph-setup/`.**
  Any path you have memorised, scripted, or symlinked is stale.
- **The sync was rebuilt.** `omnigraph-setup/sync-windows.ps1` and
  `omnigraph-setup/omnigraph-sync.sh` now share one implementation via two Python helpers
  (`omnigraph_jsonl.py`, `pull_graph.py`): delta-only push straight to central `main`,
  **no device branch**, purge-then-load pull, and real exit-code checks.
- **Helper scripts auto-detect the stack** (`scripts/_omni_env.py`) — network from
  `docker inspect omnigraph-server`, MinIO mount *and type* from `docker inspect
  omnigraph-minio`. Central no longer needs hand-passed overrides.
- **`.gitattributes` now pins `*.sh`/`*.py`/units to `eol=lf`.** Shell scripts previously
  got CRLF on a Windows checkout, making the shebang `#!/usr/bin/env bash\r` and
  unrunnable. After pulling, confirm nothing on this host regressed to CRLF.
- **Graphify clustering patches** — `scripts/patch-graphify-cluster-sort.py` (mixed
  str/int node ids) and the existing `patch-graphify-ollama-bugs.py`.

## Tasks — each has an expected answer

### 0. Back up first, always

```bash
cd <agent-skills>/infra/mcp-servers
set -a; . ./.env.shared; . ./.env.server; set +a   # central's values
mkdir -p .graph-backup
for g in $(curl -s http://127.0.0.1:8080/graphs -H "Authorization: Bearer $OMNIGRAPH_TOKEN" \
           | grep -o '"graph_id":"[^"]*"' | cut -d'"' -f4); do
  curl -s -X POST "http://127.0.0.1:8080/graphs/$g/export" \
    -H "Authorization: Bearer $OMNIGRAPH_TOKEN" -H 'content-type: application/json' -d '{}' \
    -o ".graph-backup/central-$g-$(date -u +%Y%m%d-%H%M%S).jsonl"
done
```
**Gate:** a non-empty backup per graph. Do nothing else until this passes.

### 1. Pull and see what actually changed

```bash
git -C <agent-skills> log --oneline -1        # note the SHA you are on BEFORE
git -C <agent-skills> pull --ff-only
git -C <agent-skills> log --oneline <old-sha>..HEAD
git -C <agent-skills> diff --stat <old-sha>..HEAD
```
Read the diff — do not skim. Pay attention to `omnigraph-setup/**`, `scripts/**`,
`cluster/**`, and `.gitattributes`.

**Gate:** you can state, in your own words, what changed and what it means for this host.

### 2. Line endings survived the pull

The one thing `.gitattributes` cannot fix retroactively is a file already checked out wrong.

```bash
for f in $(git -C <agent-skills> ls-files '*.sh' '*.py' '*.service' '*.timer'); do
  file "<agent-skills>/$f" | grep -q CRLF && echo "CRLF: $f"
done
```
**Expected:** no output. If anything prints, `git rm --cached -r . && git reset --hard`
(after committing/stashing local work) to re-checkout with the new attributes.
**Also:** `head -1 omnigraph-setup/omnigraph-sync.sh | cat -A` must end `bash$`, not `bash^M$`.

### 3. The stack is what the scripts think it is

```bash
cd <agent-skills>/infra/mcp-servers
python3 scripts/_omni_env.py
```
**Expected on central:** `network=mcp-servers_default bind=/home/s/apps/omnigraph/minio`
(compose project `mcp-servers`; MinIO is a **bind mount**, not a volume). If it prints
something else, **trust the probe, not this prompt** — it read the live stack — and say so.

### 4. The graphs are healthy (this is the real health check)

```bash
for g in memory agent-skills basic-analysis invest homelab-server; do
  echo "--- $g"
  curl -s -X POST "http://127.0.0.1:8080/graphs/$g/export" \
    -H "Authorization: Bearer $OMNIGRAPH_TOKEN" -H 'content-type: application/json' -d '{}' \
    | python3 omnigraph-setup/omnigraph_jsonl.py verify
done
```
**Expected:** every graph `RESULT: clean (no duplicates)`. `memory` must be **2 nodes /
0 edges** (global-scope `Preference`s only — project data lives in the per-project graphs).
As of 2026-07-17 the client and central agreed at: `memory` 2/0, `agent-skills` 18/27,
`basic-analysis` 127/204, `invest` 71/81, `homelab-server` 19/18. Counts drift as agents
write — **`edges` vs `distinct edges` is the check that matters, not the absolute number.**

If any graph shows duplicates, **stop and repair before syncing anything into it**: export →
`omnigraph_jsonl.py dedup` → sanity-check the deduped result against
`cluster/seed/<g>.jsonl` → delete every node (edges cascade) → merge-load the deduped export
→ re-verify. Smallest graph first, to prove the recipe.

### 5. The schema is live, not just declared

```bash
curl -s http://127.0.0.1:8080/graphs -H "Authorization: Bearer $OMNIGRAPH_TOKEN"
```
**Expected:** all five graphs. Then run a query using a *relational* edge — it must
**parse** (0 rows is a pass):
```
match { $t: Task  $p: Project  $t tracks $p } return { $t.slug }
```
**`type error: T4: unknown edge type` means the cluster declaration is not applied** — the
schema knows 6 edge types instead of 11, and every agent following the "link richly" rule is
failing silently. Fix with `./scripts/apply-cluster.sh` (it snapshots, stops the server,
applies, restarts, verifies the node count did not drop, and now reconciles non-main
branches first). Re-run this check afterwards.

### 6. Branches are clean

```bash
for g in memory agent-skills basic-analysis invest homelab-server; do
  echo -n "$g: "; curl -s "http://127.0.0.1:8080/graphs/$g/branches" -H "Authorization: Bearer $OMNIGRAPH_TOKEN"; echo
done
```
**Expected:** `main` only. A stray `device/<host>` branch **blocks `schema apply`** — the
rebuilt sync no longer creates them (and sweeps its own), so any you find are from an older
run. Delete: `DELETE /graphs/<g>/branches/device%2F<host>`.

### 7. The rebuilt Linux sync works **here** — dry run first

`omnigraph-sync.sh` was rewritten and has been verified on the Windows client via Git Bash,
but **not on Linux**. You are its first real Linux run. On this host the defaults should be
right (`DOCKER_NET=host`, `LOCAL_URL_CONTAINER=$LOCAL_URL`).

```bash
cd <agent-skills>/infra/mcp-servers/omnigraph-setup
DRY_RUN=1 ./omnigraph-sync.sh
```
**Expected:** it lists every graph, verifies both sides, reports a delta per graph, and
writes nothing (`rc=0`).

> If central *is* the server this script would sync **to**, there is nothing to reconcile —
> it is a client-side tool. In that case just confirm the dry run parses, discovers graphs,
> and exits 0, and say so. **Do not run it for real on central against itself.**

**Gate:** the dry run exits 0 and no write occurred. If it dies on the shebang, go back to
step 2. If it bind-mount-fails, report it — that bug was supposed to be gone.

### 8. The timers

```bash
systemctl list-timers 'omnigraph*' 'dedup*'
systemctl status omnigraph-sync.timer dedup-graph.timer
```
The intended cadence is **every 5 minutes** (`OnUnitActiveSec=5min`). **Do not enable
`omnigraph-sync.timer` on central if central is the sync target** — it is a client tool.
`dedup-graph.timer`: only arm it once you have confirmed `python3 scripts/dedup-graph.py
--dry-run` walks **all five** graphs and reports them clean, and that its reset path matches
what `_omni_env.py` reported (a `docker volume rm` against a **bind mount** is a silent
no-op, so it would "succeed" while wiping nothing).

**Gate:** state which timers are enabled, at what cadence, and why.

### 9. Mem0 is really gone from this host

```bash
docker ps -a | grep -iE 'mem0|pgvector|postgres'
grep -riE 'MEM0_|POSTGRES_PASSWORD|DEEPSEEK_API_KEY' <Server-repo>/server/coding/mcp-servers/.env
```
Central boots from `Server/server/coding/mcp-servers/docker-compose.yml` — **note that file
lives on the `improve` branch of the `Server` repo, not `main`**. If it still defines
mem0/Postgres services or its `.env` carries those vars, remove them per ADR 0003 and commit
**in the `Server` repo, on the branch it lives on**.

**Gate:** no mem0/postgres containers; central's compose defines only
minio / minio-init / omnigraph-init / omnigraph-server / omnigraph-seed / omnigraph-viewer
(plus serena / mem0-aio if those are genuinely separate concerns you intend to keep — say
which and why).

### 10. The seed loader maps file → graph

```bash
docker compose -f <Server-repo>/server/coding/mcp-servers/docker-compose.yml up omnigraph-seed
```
**Expected:** `seeding /cluster/seed/<g>.jsonl -> graph <g>` for all five, exit 0, and
**node counts unchanged** (merge is idempotent). If it hardcodes `--graph memory`, that is
the old bug — it dumps every project into the shared graph. Fix it in the `Server` repo.

> **Seeds are merge-loaded by `@key(slug)` on every boot, so a seed that has fallen behind
> silently overwrites newer live values.** If the counts move, the seeds are stale: refresh
> with `python3 scripts/split-project-graph.py <g> --write-seed` and commit.

## Known traps — do not rediscover these

- **`load --mode overwrite` on a populated graph** trips a Lance bug
  (`stage_create_btree_index … all columns in a record batch must have the same length`).
  It fails *staged* (data survives) but can leave Lance HEAD ahead of the manifest, after
  which **every** load to that graph fails while reads still work. The server names the fix:
  **`docker restart omnigraph-server`** recovers it, no data lost. It can also *land while
  exiting 1* — so its failure is not trustworthy either. Verify, don't infer.
- **Edges have no `@key`.** Merge-loading an edge that already exists appends a duplicate.
  Never push a whole export at a graph that already has the data.
- **Merged `Decision`s are invisible to `nearest()`.** `merge` does not compute the
  `@embed("rationale")` vector and **erases** it if the record omits one. On v0.8.1 there is
  no working re-embed on a populated graph — `populate-embeddings.py` only works on a fresh
  one. Don't "fix" this by running it against central.
- `OMNIGRAPH_GRAPH_ID` = the MCP **bridge**'s graph; `OMNIGRAPH_GRAPH` = the **viewer**'s.
- Central's bearer ≠ any client's bearer.

## Report back — output, not adjectives

- The commit range you pulled and what materially changed.
- `_omni_env.py` output (the live network + MinIO mount/type).
- Per graph: `nodes / edges / distinct edges`, and the branch list.
- The relational-edge query result (parsed? or `T4`?).
- The `DRY_RUN=1 ./omnigraph-sync.sh` output.
- Timer state + cadence, and which you enabled or deliberately did not.
- Mem0 removal state on this host.
- The seed-loader run: per-graph mapping and whether counts moved.
- **Anything that disagreed with this prompt** — that is the most valuable part of your
  report. Do not report success on a step you did not run and observe.

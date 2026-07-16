# Prompt — bring CENTRAL (coding.vm) fully up to date

Send this to an agent **with shell + docker access on `coding.vm`**. It supersedes the
narrower `omnigraph-fix-central-server.md` and `omnigraph-align-scripts-to-central.md`
— it is the single, current handoff.

**Before sending:** `git -C <agent-skills> log --oneline -1` and make sure the mem0
removal + script auto-detection are pushed, or the agent will pull a stale tree.

Copy everything below the line.

---

You are on **`coding.vm`**, the host running the authoritative Omnigraph instance behind
`omnigraph.ohje.ooguy.com` (API `coding.vm:8080`, bearer; viewer `:8090` behind Authelia).
Everything below has already been done and verified on the Windows client's local stack —
central is expected to still be in the old state. Your job is to bring it level.

Work top to bottom; each task has a gate. **Do not proceed past a failing gate** — a
half-migrated graph is worse than an unmigrated one.

## Background — what was wrong, and why it matters

The memory model is declared as code in `agent-skills/infra/mcp-servers/cluster/`
(`cluster.yaml` = which graphs exist, `memory.pg` = the schema). A one-shot
`omnigraph cluster apply` converges that into the MinIO-backed state ledger the server
boots from. **The declaration was never applied.** Root cause: `scripts/apply-cluster.sh`
sourced a `./.env` that never existed (the convention is `.env.shared` + `.env.server`),
so it died on line 15 under `set -e`. It had never once run. Consequences, all of which
central probably still has:

1. **The schema is stale.** `memory.pg` declares 11 edge types; a server that never
   applied it knows 6. The five *relational* edges — `Tracks`, `Affects`, `Addresses`,
   `Implements`, `DependsOn` — do not exist, so every agent following the skill's
   "link richly" rule gets `type error: T4: unknown edge type`, **silently**, and every
   seed line using them fails.
2. **Per-project isolation isn't real.** `cluster.yaml` declares 5 graphs; the server
   likely has only `memory`, holding every project at once.
3. **Nodes are orphaned.** With no `Tracks` edge, every `Task` lost its hub edge to its
   `Project` and renders as "global" in the viewer.
4. **Mem0 is gone** (ADR 0003). No `mem0-fallback` profile, no Postgres/pgvector, no
   DeepSeek key. Omnigraph is the only memory layer.

**The lesson to carry:** *declared ≠ live.* Verify against the running server
(`graphs_list`, `schema_get`, `docker inspect`), never by reading a config file. That gap
is the whole reason this prompt exists.

Target end state, identical to the client's:

| Graph | Contents |
|---|---|
| `memory` | **globals only** — 2 `Preference {scope: global}`, 0 edges |
| `agent-skills` / `basic-analysis` / `invest` / `homelab-server` | that repo's whole subgraph: `Project` node + satellites |

## ⚠️ First — stop the timers

```bash
systemctl disable --now omnigraph-sync.timer dedup-graph.timer   # names per setup/*.timer
```

Sync and dedup are now multi-graph aware in git, but **do not run them until task 6**.
Sync's step 5 pulls central → local with `load --mode overwrite`; if central is stale and
a client is already migrated, that overwrites the client's clean state.

## Central's wiring differs from local — it is now auto-detected

Local is compose project `mcp-server` (network `mcp-server_mcp-net`). Central is
`mcp-servers` → network `mcp-servers_default`, MinIO on a **bind mount** at
`$APPS_ROOT/omnigraph/minio` (`/home/s/apps/omnigraph/minio`), viewer bound `0.0.0.0:8090`
for Caddy. Central boots from `Server/server/coding/mcp-servers/docker-compose.yml` —
note that file **only exists on the `improve` branch** of the `Server` repo, not `main`.

The scripts no longer assume a host: `scripts/_omni_env.py` derives the network from
`docker inspect omnigraph-server` and the MinIO mount **and its type** from
`docker inspect omnigraph-minio`. **Probe it first — this is your task-0 verification:**

```bash
cd <agent-skills>/infra/mcp-servers
python3 scripts/_omni_env.py     # expect: network=mcp-servers_default bind=/home/s/apps/omnigraph/minio
```

If that prints something else, trust the output over this prompt and say so in your
report — it read the live stack; I only had central's declared compose to go on.
(Mount *type* matters: `docker volume rm` against a bind mount is a silent no-op.)

## Tasks

### 1. Pull, orient, back up

- `git pull` the `agent-skills` checkout.
- Make `.env.shared` / `.env.server` resolve to **central's** `OMNIGRAPH_TOKEN` + MinIO
  creds (they live in `Server/server/coding/mcp-servers/.env`), or `export OMNIGRAPH_TOKEN=…`.
  Central's bearer is **not** the client's — they are different deployments.
- **Back up every graph before touching anything:**

```bash
mkdir -p .graph-backup
for g in $(curl -s http://127.0.0.1:8080/graphs -H "Authorization: Bearer $OMNIGRAPH_TOKEN" \
           | grep -o '"graph_id":"[^"]*"' | cut -d'"' -f4); do
  curl -s -X POST "http://127.0.0.1:8080/graphs/$g/export" \
    -H "Authorization: Bearer $OMNIGRAPH_TOKEN" -H 'content-type: application/json' -d '{}' \
    -o ".graph-backup/central-$g-$(date -u +%Y%m%d-%H%M%S).jsonl"
done
```

**Gate:** a non-empty backup per graph, and you can state central's graphs + node/edge counts.

### 2. Converge the cluster

`./scripts/apply-cluster.sh` — it snapshots `memory`, stops the server (to release the
state lock), applies, restarts, and verifies the node count didn't drop. It auto-detects
the network now; `OMNI_NET=…` overrides if the probe surprised you.

**Gate — verify against the live API, not the file:**
```bash
curl -s http://127.0.0.1:8080/graphs -H "Authorization: Bearer $OMNIGRAPH_TOKEN"
# must list: memory, agent-skills, basic-analysis, homelab-server, invest
```
and run a query using a previously-unknown edge — it must **parse** (0 rows is fine):
```
match { $t: Task  $p: Project  $t tracks $p } return { $t.slug }
```
Still `T4: unknown edge type`? The apply didn't take. **Stop and diagnose.**

> `schema apply` refuses to run while any non-main branch exists. A leftover
> `device/<host>` branch from a failed sync will block it — `branch list`, then merge or
> delete the strays first.

### 3. Repair orphaned hub edges

Find every node with no hub edge (`DecidedIn`/`ConstrainsProject`/`AppliesTo`/`PartOf`/
`Tracks`) to any `Project`. Only `Preference {scope: global}` may legitimately be
unattached; everything else is fallout from the missing schema.

**Derive the list from central's own export — do not copy the client's.** Attach each to
the `Project` you can *justify* (slug prefix `ba-*`/`inv-*`/`as-*`, the node's content,
any existing `ConstrainsComponent` target). Insert-only (the D₂ rule: a mutation is
insert/update-only **or** delete-only, never both), PascalCase edge type:

```
query fix_orphan_hub_edges() {
  insert Tracks { from: "<task-slug>", to: "<project-slug>" }
  insert ConstrainsProject { from: "<rule-slug>", to: "<project-slug>" }
}
```
Don't guess. For reference, the client needed 7 (4 `Tracks`, 3 `ConstrainsProject`).

**Gate:** the only unattached nodes left are `Preference {scope: global}`.

### 4. Split each project into its own graph (additive)

```bash
python3 scripts/split-project-graph.py <project> --source memory            # dry run
python3 scripts/split-project-graph.py <project> --source memory --apply
```
for `agent-skills`, `basic-analysis`, `invest`, `homelab-server`. Additive — `memory` is
left intact, so it is safe to re-run. Report any `WARN: … leaves the project`.

**Gate — the counts must reconcile exactly:**
> sum(nodes over the 4 project graphs) + (global Preferences) == nodes in `memory`
> sum(edges over the 4 project graphs) == edges in `memory`

If not, a node is unattached or double-owned. Find it before continuing.

### 5. Reconcile against the seeds, then prune

`cluster/seed/*.jsonl` were regenerated from the **client's** live graphs on 2026-07-16
and match it exactly. Central may hold nodes the client doesn't (other clients wrote to
it). **Do not blindly load the seeds over central** — diff first, per graph, by slug:
report only-in-central / only-in-seed / same-slug-different-values, and **report anything
ambiguous instead of silently picking**. Then refresh the seeds from central so git
matches reality: `python3 scripts/split-project-graph.py <project> --write-seed`.

Then prune `memory` to globals-only. The script verifies every node is mirrored in its
project graph and refuses otherwise:
```bash
python3 scripts/split-project-graph.py <project> --source memory --prune-source
```

**Gate:** `memory` is exactly 2 nodes / 0 edges; each project graph keeps its full count.

### 6. Re-enable sync + dedup

Both are multi-graph aware now. Verify before arming:
- `DRY_RUN=1 ./setup/omnigraph-sync.sh` reports **all five** graphs and writes nothing.
- `python3 scripts/dedup-graph.py --dry-run` walks all five and reports them clean.

**Gate:** both dry-runs cover 5 graphs. Only then re-enable the timers from the top.

### 7. Confirm Mem0 is gone from central

Central's compose (`Server/server/coding/mcp-servers/docker-compose.yml`, `improve`
branch) may still define mem0/Postgres services, and its `.env` may still carry
`POSTGRES_PASSWORD` / `DEEPSEEK_API_KEY`. Per ADR 0003 they should go. **That file is in
the `Server` repo, not `agent-skills` — commit it there, on the branch it lives on.**
Check `docker ps` for stray `mem0-*` / `*postgres*` containers from the old stack.

**Gate:** no mem0/postgres containers running; central's compose defines only
minio / minio-init / omnigraph-init / omnigraph-server / omnigraph-seed / omnigraph-viewer
(plus serena/mem0-aio if those are genuinely separate concerns you intend to keep —
say which).

## Known limitation you will hit — don't "fix" it blindly

**On v0.8.1 you cannot (re)embed a `Decision` on a populated graph.** Verified on the
client 2026-07-16, both paths fail with the same Lance bug:

| attempt | result |
|---|---|
| `load --mode overwrite` (populated) | `stage_create_btree_index on node:Rule(["id"]) … all columns in a record batch must have the same length` |
| `load --mode merge` carrying hand-supplied vectors | `LanceError(Arrow): … same length` |

Worse, `load --mode merge` of a `Decision` whose record omits `embedding` **erases** the
existing vector, and an unembedded `Decision` is *dropped* from `nearest()` — so editing
a rationale silently un-indexes it. `scripts/populate-embeddings.py` therefore only works
against a **fresh/empty** graph.

Both failures are **staged** — they abort before moving data, so the graph survives. But
a failed overwrite can leave Lance HEAD ahead of the manifest, after which *all* loads to
that graph fail with the same error while reads still work. The server says exactly what
to do:
`table 'node:X' has Lance HEAD version N ahead of manifest version N-1; a pending
recovery sidecar requires rollback — reopen the graph read-write (e.g. restart the
server) to recover`. **`docker restart omnigraph-server` fixes it; no data is lost.**
If a load starts failing right after an overwrite attempt, restart before assuming
corruption.

So: don't run `populate-embeddings.py` against central's populated graphs. If semantic
search matters, raise it — the fix is a server upgrade or a store-reset rebuild
(`dedup-graph.py`), not a retry.

## Report back

With command output as evidence:
- `python3 scripts/_omni_env.py` output — **the live network + MinIO mount/type.**
- Central before/after: graphs, node/edge counts per graph, schema edge types.
- The orphan edges you added and **why you attributed each one**.
- The central↔seed diff and how you resolved each difference.
- Sync/dedup dry-run output; confirmation the timers are back on.
- Mem0 removal state on central (containers, compose, `.env`).
- Anything you could not verify, or where you had to judge.

Do not report success on a step you did not run and observe. If a gate fails, stop and
report — you have backups from task 1.

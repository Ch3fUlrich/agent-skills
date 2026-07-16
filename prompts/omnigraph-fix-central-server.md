# Prompt — converge the CENTRAL Omnigraph server (coding.vm)

Send this to an agent **with shell + docker access on `coding.vm`** (the host running
the authoritative Omnigraph instance behind `omnigraph.ohje.ooguy.com`).

**Before sending:** the fixes this prompt depends on must be committed and pushed from
the `agent-skills` repo — `scripts/apply-cluster.sh`, `scripts/split-project-graph.py`,
`docker-compose.server.yml`, `cluster/seed/*.jsonl`, `cluster/seed/README.md`,
`skills/structured-memory/SKILL.md`, `starters/mcp-servers/*`. If they are still
uncommitted, commit and push first or the agent will pull the broken versions.

Copy everything below the line.

---

You are working on **`coding.vm`**, the host that runs the central self-hosted
**Omnigraph** memory server (`omnigraph.ohje.ooguy.com` → `coding.vm:8080`, bearer-token
auth; viewer on `:8090` behind Authelia). Your job is to bring the central server in line
with the declared configuration, migrate its data to per-project graphs, and make the
sync/dedup automation safe. Work carefully: this server holds the only copy of several
projects' durable memory.

## Background — what is broken and why

The `agent-skills` repo declares the memory model as code:
`infra/mcp-servers/cluster/` holds `cluster.yaml` (which graphs exist), `memory.pg` (the
schema), Cedar policies, and `seed/*.jsonl`. A one-shot `omnigraph cluster apply`
converges that declaration into the MinIO-backed state ledger the server boots from.

**The declaration was never applied.** The root cause: `scripts/apply-cluster.sh` sourced
a `./.env` file that never existed (this repo's convention is `.env.shared` + `.env.server`),
so under `set -euo pipefail` it died on line 15 before doing anything. It had never once
run successfully. Everything below followed from that single failure:

1. **The schema is stale.** `memory.pg` declares eleven edge types, but a server that
   never applied it only knows six. The five *relational* edges —
   `Tracks`, `Affects`, `Addresses`, `Implements`, `DependsOn` — do not exist. Any agent
   following `skills/structured-memory/SKILL.md` ("link richly — a graph, not a star")
   gets `type error: T4: unknown edge type`, and every seed line using them fails.
2. **Those failures were invisible.** The seed loader ended each load with
   `|| echo "WARN: seed failed"`, so a total failure still exited 0. The seed service also
   declared **no docker network**, so it could not resolve `omnigraph-server` even to try.
3. **Per-project isolation was never real.** `cluster.yaml` declares five graphs
   (`memory`, `agent-skills`, `invest`, `basic-analysis`, `homelab-server`), but the server
   only ever had `memory`, holding every project at once — the exact shared-graph model the
   isolation work was meant to replace. The seed loader hardcoded `--graph memory` for
   every file, so it actively maintained the old model.
4. **Nodes were silently orphaned.** Because `Tracks` did not exist, every `Task` lost its
   hub edge to its `Project` and renders as "global" in the viewer — the bug the
   "de-star the graph" commit claims to have fixed. Some `Rule`s lost `ConstrainsProject`
   the same way.

**This has already been fixed and verified on the Windows client's local stack** (2026-07-16).
The repo now contains the corrected scripts. Central is expected to still be in the broken
state. Your job is to bring it to the same place.

The intended end state, for every Omnigraph instance:

| Graph | Contents |
|---|---|
| `memory` | **globals only** — 2 `Preference` nodes with `scope: global`, 0 edges |
| `agent-skills` / `basic-analysis` / `invest` / `homelab-server` | that project's whole subgraph, `Project` node + satellites |

## ⚠️ Do this before anything else

**Stop the sync and dedup timers on `coding.vm` and any client**, and do not run
`setup/omnigraph-sync.sh` / `setup/sync-windows.ps1` until task 6 is done:

```bash
systemctl disable --now omnigraph-sync.timer dedup-graph.timer   # names per setup/*.timer
systemctl status omnigraph-sync.timer dedup-graph.timer
```

Why this is urgent: `omnigraph-sync.sh` syncs exactly one graph (`GRAPH="${GRAPH:-memory}"`)
and its step 5 pulls central into local with **`load --mode overwrite`**. The client's local
`memory` has already been pruned to 2 global nodes; central still has ~162. If sync runs, it
overwrites the client's clean local with central's stale copy and **undoes the migration**.
The same script also never touches the four project graphs at all.

## Tasks

Work top to bottom. Each task has a gate — do not proceed past a failing gate.

### 1. Pull, orient, and back up

- `git pull` in the `agent-skills` checkout on this host.
- Identify how central is actually started: the single source of truth is
  `Server/server/coding/mcp-servers/docker-compose.yml` (in the `Server` repo), which
  references `agent-skills`'s `cluster/` config and the viewer image. **Note its compose
  project name, docker network name, and MinIO container/service name** — they may differ
  from the `agent-skills` `docker-compose.server.yml` defaults
  (`mcp-server_mcp-net`, `omnigraph-minio`). You will need them in task 2.
- **Back up every graph before touching anything:**

```bash
cd <agent-skills>/infra/mcp-servers
set -a; . ./.env.shared; . ./.env.server; set +a   # or wherever central's token lives
mkdir -p .graph-backup
for g in $(curl -s http://127.0.0.1:8080/graphs -H "Authorization: Bearer $OMNIGRAPH_TOKEN" \
           | grep -o '"graph_id":"[^"]*"' | cut -d'"' -f4); do
  curl -s -X POST "http://127.0.0.1:8080/graphs/$g/export" \
    -H "Authorization: Bearer $OMNIGRAPH_TOKEN" -H 'content-type: application/json' -d '{}' \
    -o ".graph-backup/central-$g-$(date -u +%Y%m%d-%H%M%S).jsonl"
done
ls -la .graph-backup/
```

**Gate:** you have a non-empty backup of every graph, and you can state central's node/edge
counts and which graphs exist.

### 2. Converge the cluster

`apply-cluster.sh` snapshots `memory`, stops the server (to release the cluster state lock),
applies, restarts, and verifies the node count did not drop. It defaults to this repo's
compose names; **override them if central differs**:

```bash
OMNI_NET=<central-docker-network> OMNI_S3=http://<central-minio-host>:9000 \
  ./scripts/apply-cluster.sh
```

Note: it sources `.env.shared` + `.env.server` for `OMNIGRAPH_TOKEN`, `MINIO_ROOT_USER`,
`MINIO_ROOT_PASSWORD`, `S3_BUCKET`. Make sure those resolve to **central's** values on this
host. If `apply` fails it restarts the server unchanged — that is by design.

**Gate — verify against the live API, not the config file:**

```bash
curl -s http://127.0.0.1:8080/graphs -H "Authorization: Bearer $OMNIGRAPH_TOKEN"
# must list: memory, agent-skills, basic-analysis, homelab-server, invest
```
and confirm the schema took, by running a query that uses a previously-unknown edge:
```
match { $t: Task  $p: Project  $t tracks $p } return { $t.slug }
```
It must **parse** (0 rows is fine and expected). If you still get
`T4: unknown edge type`, the apply did not take — stop and diagnose; do not continue.

### 3. Repair orphaned hub edges

Find every node that has no hub edge (`DecidedIn`/`ConstrainsProject`/`AppliesTo`/`PartOf`/
`Tracks`) to any `Project`. Only genuinely-global `Preference {scope: global}` nodes may
legitimately be unattached; everything else is a bug from the missing schema.

Attach each orphan to the `Project` it belongs to. **Only add edges you can verify** — slug
prefixes (`ba-*` → `basic-analysis`, `inv-*` → `invest`) plus the node's own content and any
existing `ConstrainsComponent` target are good evidence. Do not guess. Insert with the
PascalCase edge type, delete-free (the D₂ rule: a mutation is insert/update-only **or**
delete-only, never both):

```
query fix_orphan_hub_edges() {
  insert Tracks { from: "<task-slug>", to: "<project-slug>" }
  insert ConstrainsProject { from: "<rule-slug>", to: "<project-slug>" }
}
```

For reference, on the client's stack this was exactly 7 edges: 4 `Tracks`
(`ba-task-intrinsic-overhaul`, `ba-task-suite2p-runner`, `ba-task-twitch-detection` →
`basic-analysis`; `inv-task-finetuning` → `invest`) and 3 `ConstrainsProject`
(`ba-rule-config-ssot-translator`, `ba-rule-fluor-version-keying`,
`ba-rule-store-subsession-isolation` → `basic-analysis`). **Central may differ — derive the
list from central's own export, don't copy this one.**

**Gate:** the only unattached nodes remaining are `Preference {scope: global}`.

### 4. Split each project into its own graph (additive)

```bash
python3 scripts/split-project-graph.py <project> --source memory            # dry run
python3 scripts/split-project-graph.py <project> --source memory --apply
```
for each of `agent-skills`, `basic-analysis`, `invest`, `homelab-server`. This copies the
`Project` node plus everything hub-edged to it, and every relational edge whose endpoints are
both inside that set. It is **additive** — `memory` is left intact — so it is safe to re-run.
Report any `WARN: … leaves the project` lines rather than ignoring them.

**Gate — the counts must reconcile exactly:**
> sum(nodes across the 4 project graphs) + (global Preferences) == nodes in `memory`
> sum(edges across the 4 project graphs) == edges in `memory`

If they do not, a node is unattached or double-owned. Find it before continuing.

### 5. Reconcile central against the seeds, then prune

The repo's `cluster/seed/*.jsonl` were regenerated from the **client's** live graphs on
2026-07-16. Central may hold nodes the client does not, or vice versa. **Do not blindly
load the seeds over central** — first diff them:

- For each project graph, compare central's export against `cluster/seed/<project>.jsonl`
  by slug. Report: only-in-central, only-in-seed, and same-slug-different-values.
- Newer/richer content wins on a per-node basis; use judgement and **report anything
  ambiguous instead of silently picking**. Central having *extra* nodes is expected if other
  clients wrote to it.
- Once central is correct, refresh the seeds from central so git matches reality:
  `python3 scripts/split-project-graph.py <project> --write-seed`
  (defaults to reading the project's own graph; strips embeddings, which are regenerable).

Then prune `memory` to globals-only. The script verifies every node is mirrored in its
project graph and refuses if any is not:

```bash
python3 scripts/split-project-graph.py <project> --source memory --prune-source
```

**Gate:** `memory` is exactly 2 nodes / 0 edges (the two global `Preference`s), and each
project graph still has its full node count.

### 6. Make sync + dedup multi-graph aware — they are currently unsafe

Both automations predate per-project isolation and only know the `memory` graph:

- **`setup/omnigraph-sync.sh`** — `GRAPH="${GRAPH:-memory}"`. It syncs one graph, so the four
  project graphs **never reach central**: no off-device backup, no multi-device memory. Its
  step 5 pulls central → local with `--mode overwrite`, so pointing it at a stale central
  destroys a good local. Same for the Windows twin `setup/sync-windows.ps1`
  (`$GRAPH = ... else 'memory'`).
- **`scripts/dedup-graph.py`** — `--graph memory` is **hardcoded** in three places (export,
  snapshot, and the overwrite-load). Its hourly timer therefore only ever cleans `memory`
  (now 2 nodes) and never the project graphs where duplicate edges actually accumulate.

Make both iterate the graph list (from `cluster.yaml` or `GET /graphs`), looping the existing
per-graph logic. Keep every current guarantee: backup-before-write, the no-duplicates verify
gate before overwriting local, and restore-from-backup on failure. Add a `GRAPHS=` env
override so a single graph can still be targeted.

**Gate:** a `DRY_RUN=1` sync reports **all five** graphs and writes nothing; the dedup timer
lists all five. Only then re-enable the timers from the "Do this before anything else" step.

### 7. Fix the seed loader if central's compose has its own copy

`agent-skills`'s `docker-compose.server.yml` is fixed, but central boots from
`Server/server/coding/mcp-servers/docker-compose.yml`. If that file has its own
`omnigraph-seed` service, apply the same three fixes there:
1. derive the graph from the file name (`g=$(basename "$f" .jsonl)`), never hardcode `memory`;
2. give the service the compose network (it had none, so it could not resolve the server);
3. fail loudly — exit nonzero on a failed seed instead of `|| echo WARN`.

**Gate:** `docker compose up` the seed service and watch it report `seeding …-> graph <name>`
for all five, exit 0, and change no node counts (merge is idempotent).

## Report back

State plainly, with the command output as evidence:
- central's before/after: graphs, node/edge counts per graph, schema edge types;
- the orphan edges you added and **why** you attributed each one;
- the central↔seed diff from task 5 and how you resolved each difference;
- what you changed in sync/dedup, and confirmation the timers are back on;
- anything you could not verify, or where you had to make a judgement call.

Do not report success on any step you did not actually run and observe. If a gate fails,
stop and report — a half-migrated graph is worse than an unmigrated one, and you have
backups from task 1.

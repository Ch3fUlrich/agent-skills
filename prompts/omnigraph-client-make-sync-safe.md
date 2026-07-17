# Prompt — make client sync correct, then arm it

> ## STATUS 2026-07-17: mostly DONE on the Windows client. Only §2 remains.
>
> Fixed and verified on `bz-wg-pdw028` — `setup/sync-windows.ps1` now: pushes a **delta**
> (`omnigraph_jsonl.py pushset` — all changed/new nodes, only edges central lacks), skips
> identical nodes (they caused `Concurrent modification: table version N already exists`),
> uses **no device branch** (`branch create` hits a Lance internal error, `branch merge` the
> above), pulls via `setup/pull_graph.py` (purge-then-load; `overwrite` on a populated graph
> trips a Lance bug and can land while exiting 1), and **checks exit codes** so it fails
> loudly instead of logging success.
>
> **Proof:** 4 consecutive full runs — rc=0 on the last three, all 5 graphs identical
> central↔local, `verify` clean on both sides, **zero edge growth**. Cadence is **5 minutes**
> (not hourly); registration + everything else is in
> [`../infra/mcp-servers/setup/SYNC-MANUAL.md`](../infra/mcp-servers/setup/SYNC-MANUAL.md).
>
> **STILL OPEN — §2 below:** `setup/omnigraph-sync.sh` (Linux) is **unported** and still has
> the whole-export push that duplicated central's edges. Do not enable the Linux timer until
> it matches the PowerShell twin. §3 (the pull) and §4/§5 (proof + scheduling) are done; §6
> (the `OMNIGRAPH_TOKEN` env var) is deferred by the user and documented in the manual.

Send this to an agent **with shell + docker access on a client machine** (the Windows dev
box: compose project `mcp-server`, network `mcp-server_mcp-net`; a Linux client is the
same job with the other script).

It supersedes `omnigraph-client-update-after-central.md` — **that prompt is unsafe as
written**: following it on 2026-07-17 duplicated every edge on all four central project
graphs while reporting success. Central has since been repaired; the bugs behind it are
only half fixed.

**Goal:** sync that runs **every hour, forever**, with **no breakage, no data loss, and no
duplication** — and that *tells you* when it fails instead of lying.

Copy everything below the line.

---

You are on an Omnigraph **client** that mirrors central (`omnigraph.ohje.ooguy.com`).
Your job: make the sync correct, prove it, then schedule it hourly. Do not arm the
schedule until the proof passes — an hourly job that duplicates edges compounds damage
every hour.

## The one rule that matters here

**Verify against the live system; never trust a script's own report.** Every failure
below was a component that reported success while doing the opposite. Concretely: after
any sync, check `edges` vs `distinct edges` on both sides — not the exit code.

## What is broken (verified 2026-07-17 — do not re-derive, but do re-confirm)

1. **The push duplicates edges on central.** Both sync scripts do:
   `branch create device/<host>` (forks central `main`) → `load --mode merge` of the
   **entire local export** onto it → `branch merge → main`. Edges have **no `@key`**, so
   every edge central already had is appended a second time and the branch-merge carries
   the duplicates into `main`. Measured: agent-skills 27→54, basic-analysis 120→221,
   invest 81→125, homelab-server 18→32. This is `operations.md` rule 6 firing exactly as
   documented — the scripts' own docstrings say *"prefer native branches_merge over raw
   `load --merge`"* and then do a raw `load --merge`.
   - **`setup/sync-windows.ps1` is FIXED** — it now sends a delta via
     `omnigraph_jsonl.py pushset` (all nodes — they are `@key(slug)` so merge upserts
     safely — but only the edges central lacks).
   - **`setup/omnigraph-sync.sh` is NOT fixed.** Line ~93 still merge-loads
     `/w/local.jsonl` whole. **A Linux client running it will re-pollute central.**
2. **Failures are invisible.** `sync-windows.ps1`'s `Og`/`OgLoad` swallowed stderr and
   never checked `$LASTEXITCODE`; a non-zero exit from a *native* command is not a
   PowerShell terminating error, so the caller's `try/catch` never fired — a pull that
   failed on all five graphs still logged *"pulled central main -> local main"* and
   returned `rc=0`, while local never moved. **Fixed** via `Invoke-Native` (note: the CLI
   writes its success banner to **stderr**, so `2>&1` under `$ErrorActionPreference='Stop'`
   throws on success — capture with EAP relaxed and judge by `$LASTEXITCODE` only).
   `omnigraph-sync.sh` has the same class of bug (`>/dev/null 2>&1 || …`, `|| true`).
3. **The pull still does not land — OPEN, this is your main debugging task.** After the
   delta fix, `sync-windows.ps1` exits 1 on the load / `branch merge` step with
   *banner-only* output, while the identical commands succeed when run standalone
   (`branch create` → 0, `load --branch … --mode merge` → 0 with `nodes_loaded`,
   `branch merge --into main` → 0, `fast_forward`). It fails **safe** (central verified
   clean afterwards) but **local stays behind central**.
4. **`omnigraph-sync.sh` cannot run on Windows at all.** It bind-mounts
   `-v "$work:/w"` from a `mktemp -d` path; Git Bash mangles it, so the CLI container
   never sees its config and *every graph* fails with "local export/backup failed (is the
   local server up?)" — while the server is up. `sync-windows.ps1` exists precisely
   because of this and pipes over stdin instead. (Its `--network host` note is stale on
   this box: a `--network host` container reaches `127.0.0.1:8080` fine here.)
5. **Nothing is scheduled.** `setup/omnigraph-sync.timer` is systemd-only and set to
   `OnUnitActiveSec=5min`, not hourly. There is **no Windows scheduled task** at all.
6. **`OMNIGRAPH_TOKEN` is not in the environment.** Both `agent-skills/.mcp.json` and
   `basic-analysis/.mcp.json` reference `${OMNIGRAPH_TOKEN}` (correctly — they are tracked,
   so the literal bearer must never be committed). Unset, it resolves to empty and **both
   repos lose Omnigraph on the next agent restart.**

## Invariants — hold these at every step

- **Never lose data.** Back up both sides before any write. Additive before destructive.
- **Never duplicate.** Nodes may be merged freely (`@key(slug)`); **edges may only ever be
  pushed if the target lacks them.**
- **Never `load --mode overwrite` a populated graph.** On v0.8.1 it hits a Lance bug
  (`stage_create_btree_index … all columns in a record batch must have the same length`).
  It fails *staged* (the graph survives) but can leave Lance HEAD ahead of the manifest,
  after which **every** load to that graph fails while reads still work. The server names
  the fix in the error: **`docker restart omnigraph-server`** recovers it, no data lost.
- **A "clean" verify right after a branch-merge is not proof** — the merge can land after
  the read. Re-verify at the end and treat *that* as authoritative.

## Tasks

### 1. Recon + back up both sides

```bash
cd <agent-skills>/infra/mcp-servers && git pull
python3 scripts/_omni_env.py          # trust this over any doc: your live network + MinIO mount
```
Back up **every local and every central graph** to `.graph-backup/` (export per graph).
Record, per graph and per side: `nodes`, `edges`, `distinct edges`
(`… | python3 setup/omnigraph_jsonl.py verify`).

**Gate:** a non-empty backup per graph per side; both sides currently verify **clean**; you
can state the counts. If central is already dirty, repair it before anything else (see
"Repairing central" below) — do not sync into a dirty central.

### 2. Fix `setup/omnigraph-sync.sh` to match the PowerShell twin

Port both fixes:
- **Delta push:** replace the whole-export `load --mode merge` with
  `omnigraph_jsonl.py pushset <central-export.jsonl>` (export central *before* the push,
  pipe the local export through `pushset`, push only that). Log the delta
  (`N node(s), M new edge(s)`) so an hourly run is auditable.
- **Fail loudly:** stop discarding stderr and `|| true`-ing over failures; check exit codes
  and abort that graph with a clear message. Keep the "one graph's failure must not abort
  the others" behaviour, but make the overall exit code non-zero.
- Decide the Windows story explicitly: either make it stdin-based like the `.ps1` (no bind
  mounts) **or** have it refuse to run on MSYS/Git Bash with "use sync-windows.ps1".
  Silently half-working is the current state and is worse than either.

**Gate:** `DRY_RUN=1` on a Linux client lists every graph and writes nothing; the delta log
shows `0 new edge(s)` when local ⊆ central.

### 3. Fix the pull (item 3 above) — the open one

Reproduce, then fix. Suggested attack, in order:
- Capture the **full** stderr+stdout and the real exit code of the failing
  `load`/`branch merge` inside the script (not the truncated banner). The standalone
  command works, so the difference is in *how the script invokes it* — argument quoting,
  the `--branch` value (`device/<host>` contains a slash; the viewer needed `%2F`-encoded
  deletes and body-based merges for exactly this reason — see
  `servers/omnigraph-viewer/app.py::_branch_op`), stdin handling, or `$LASTEXITCODE` being
  read after the wrong command in a pipeline.
- Suspect the **slash in the branch name** first — it is the one thing that already forced
  special handling elsewhere in this repo.
- The pull writes with `load --mode overwrite` into the *local* graph. If that is what
  fails, remember overwrite-on-populated is the known Lance bug: the local graph may need a
  reset (`dedup-graph.py` reloads into an empty store — the one load path that works) or a
  `docker restart omnigraph-server` first.

**Gate:** after a real run, **local == central** per graph (nodes, edges, distinct edges),
and both verify clean.

### 4. Prove it — a round trip, not a hope

Do **not** arm the schedule on a single green run.
1. Write one throwaway node locally (e.g. `Preference {slug: "sync-probe-<date>", scope: "global"}`
   in `memory`), sync, confirm it appears on central and local counts match.
2. **Run the sync three times back to back.** Edge counts on **both** sides must be
   *identical* after each run — this is the duplication regression test and the exact thing
   that failed before.
3. Write a node on central (or from another client), sync, confirm it reaches local.
4. Delete the probe node from both sides; confirm counts return to baseline.

**Gate:** three consecutive syncs, zero edge growth, `verify` clean on both sides, and the
probe made the round trip in both directions.

### 5. Only now: arm it hourly

- **Windows** (this box) — a Scheduled Task running `pwsh -NoProfile -File
  <repo>\infra\mcp-servers\setup\sync-windows.ps1`, hourly, whether or not the user is
  logged on, **not** only on AC power, and with "run task as soon as possible after a
  missed start". Log stdout+stderr to a rotating file under `setup/backups/` or a `logs/`
  dir. Prefer `Register-ScheduledTask` with a repetition interval of 1 hour and an
  indefinite duration.
- **Linux** — set `setup/omnigraph-sync.timer` to hourly (`OnUnitActiveSec=1h`,
  `Persistent=true` so a missed run fires on boot) and enable it.
- Make the job **idempotent and non-overlapping**: if a run is still going, skip rather
  than stack (a lock file, or the task's "do not start a new instance" policy).
- The job must be **quiet on success, loud on failure** — non-zero exit + a log line that
  names the graph.
- `dedup-graph.timer`: only arm it if you have confirmed it is multi-graph aware and its
  reset path is right for **this** host's MinIO mount (`_omni_env.py` tells you bind vs
  volume; `docker volume rm` against a bind mount is a silent no-op).

**Gate:** `schtasks /query` (or `systemctl list-timers`) shows it hourly; force one run and
watch the log; then verify both sides still clean.

### 6. Unblock the MCP bridges (item 6) — do this or memory stays dead

`OMNIGRAPH_TOKEN` must exist in the environment the agent launches from. On Windows that
means a **User** environment variable (persisted), sourced from
`infra/mcp-servers/.env.shared`. **Ask the user before writing a credential into their OS
environment store** — do not do it silently. Then confirm in a *new* shell:
`[Environment]::GetEnvironmentVariable('OMNIGRAPH_TOKEN','User')` is set, and after an
agent restart `graphs_list` returns five graphs and `schema_get` shows 11 edge types.

## Repairing central, if it is dirty

Nodes are `@key(slug)` and are never the problem — only edges duplicate. Per graph:
export → `omnigraph_jsonl.py dedup` → **verify the deduped result matches
`cluster/seed/<graph>.jsonl`** (it did, byte-for-byte, on 2026-07-17 — two independent
sources agreeing is your proof the target is right) → delete every node (edges cascade) →
`load --mode merge` the deduped export into the now-empty graph → verify
`edges == distinct edges`. Do the smallest graph first to prove the recipe. Delete any
stray `device/<host>` branches afterwards (`DELETE …/branches/device%2F<host>`), or they
will block `schema apply`.

## Known traps (do not rediscover these)

- **Merged `Decision`s are invisible to semantic search.** `load --mode merge` does not
  compute the `@embed("rationale")` vector and **erases** it if the record omits it. On
  v0.8.1 there is no working re-embed on a populated graph (both `overwrite` and
  vector-carrying `merge` hit the Lance bug), so `populate-embeddings.py` only works on a
  fresh graph. Do not run it against a populated one to "fix" this.
- `OMNIGRAPH_GRAPH_ID` = the MCP **bridge**'s graph. `OMNIGRAPH_GRAPH` = the **viewer**'s.
  Different variables.
- Central's bearer ≠ the local bearer. `setup/.env` carries `CENTRAL_TOKEN` separately.
- The `GRAPH=memory` in `setup/.env` is a legacy single-graph var; the scripts auto-discover
  all graphs unless `GRAPHS` is set. Leave it alone unless you mean it.

## Report back — with command output, not claims

- `_omni_env.py` output; both sides' per-graph `nodes / edges / distinct edges` before and
  after.
- What you changed in `omnigraph-sync.sh` (and anything further in the `.ps1`).
- **The root cause of the exit-1 pull** and how you proved the fix.
- The three-consecutive-runs evidence (edge counts per run, both sides).
- The scheduling entry, and the log of one forced run.
- Whether the token env var was set, and whether the user approved it.
- Anything you could not verify or had to judge. **Do not report success on a step you did
  not run and observe** — that failure mode is the whole reason this prompt exists.

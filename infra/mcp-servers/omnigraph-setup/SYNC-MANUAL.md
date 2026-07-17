# Omnigraph sync — operator manual

Everything you need to run, schedule, edit, and trust the local↔central memory sync.
Written 2026-07-17, after the sync was rebuilt (see "How it works" for why it is shaped
this way).

**Default cadence: every 5 minutes.** Change it in one place — see [Scheduling](#scheduling).

---

## TL;DR

```powershell
# Windows client — one run, right now
cd <repo>\infra\mcp-servers
pwsh -NoProfile -File .\setup\sync-windows.ps1            # real run
pwsh -NoProfile -File .\setup\sync-windows.ps1 -DryRun    # look, don't touch
```

```bash
# check what docker actually has (never trust a doc over this)
python3 scripts/_omni_env.py          # -> network=… bind=…/volume=…
```

Exit code is the truth: **0 = synced**, non-zero = something failed and said so.

---

## Scheduling (every 5 minutes)

### Windows — Scheduled Task

Not registered by default. Run this **once**, in an elevated PowerShell (adjust the path):

```powershell
$repo = 'C:\Users\mauls\Documents\Code\agent-skills'
$act  = New-ScheduledTaskAction -Execute 'pwsh.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -File `"$repo\infra\mcp-servers\setup\sync-windows.ps1`"" `
        -WorkingDirectory "$repo\infra\mcp-servers"
$trg  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes 5)          # <-- THE CADENCE. Edit here.
$set  = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
        -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
Register-ScheduledTask -TaskName 'omnigraph-sync' -Action $act -Trigger $trg -Settings $set `
        -Description 'Reconcile local Omnigraph with central every 5 minutes' -Force
```

- `-MultipleInstances IgnoreNew` — if a run overruns 5 minutes the next is skipped, not stacked.
- `-StartWhenAvailable` — a missed run (laptop asleep) fires when you come back.
- Runs as you, so it inherits your env. It needs **docker running**; if Docker Desktop is
  down the run fails loudly and the next one picks up — nothing is lost.

**Change the cadence:** edit `-RepetitionInterval`, re-run the block (`-Force` replaces it).
Or in Task Scheduler GUI → `omnigraph-sync` → Triggers → Repeat every.

```powershell
Get-ScheduledTask omnigraph-sync | Get-ScheduledTaskInfo    # last run, last result, next run
Start-ScheduledTask omnigraph-sync                          # force one now
Unregister-ScheduledTask omnigraph-sync -Confirm:$false     # remove
```

Logging is not on by default. To keep one:

```powershell
-Argument "-NoProfile -WindowStyle Hidden -Command `"& '$repo\infra\mcp-servers\setup\sync-windows.ps1' *>&1 | Tee-Object -FilePath '$repo\infra\mcp-servers\setup\backups\sync.log' -Append`""
```

### Linux — systemd timer

`omnigraph-setup/omnigraph-sync.timer` is already `OnUnitActiveSec=5min`:

```bash
sudo cp omnigraph-setup/omnigraph-sync.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now omnigraph-sync.timer
systemctl list-timers omnigraph-sync.timer
journalctl -u omnigraph-sync.service -n 50
```

**Change the cadence:** edit `OnUnitActiveSec=` in the `.timer`, then `daemon-reload` +
`restart`. Add `Persistent=true` if you want missed runs to fire at boot.

> **Both scripts are now the same logic.** `omnigraph-sync.sh` (Linux/macOS) and
> `sync-windows.ps1` (Docker Desktop) both drive the same two Python helpers
> (`omnigraph_jsonl.py`, `pull_graph.py`): delta push straight to central `main`, no device
> branch, purge-then-load pull, real exit codes. Verified 2026-07-17 on the Windows box via
> Git Bash (`rc=0`, all 5 graphs clean and identical both sides).
>
> On Linux the defaults (`DOCKER_NET=host`, `LOCAL_URL_CONTAINER=$LOCAL_URL`) are right. On
> Docker Desktop set `DOCKER_NET=mcp-server_mcp-net` and
> `LOCAL_URL_CONTAINER=http://omnigraph-server:8080` — or just use the `.ps1`.

---

## Configuration — `omnigraph-setup/.env`

| Var | Meaning |
|---|---|
| `CENTRAL_URL` | `https://omnigraph.ohje.ooguy.com` |
| `CENTRAL_TOKEN` | central's bearer — **different from the local one** |
| `LOCAL_TOKEN` | the local server's bearer (same as `.env.shared`'s `OMNIGRAPH_TOKEN`) |
| `LOCAL_URL` | local API **as seen from this host** (`http://127.0.0.1:8080`) |
| `LOCAL_URL_CONTAINER` | local API **as seen from inside the CLI container** (`http://omnigraph-server:8080`) |
| `GRAPHS` | optional: `"a,b"` to sync a subset. Unset = every graph central exposes |
| `GRAPH` | legacy single-graph var. Ignored unless set to something other than `memory` |
| `DEVICE` | hostname; only used to name a leftover branch to sweep |
| `DRY_RUN` / `KEEP_DEVICE_BRANCH` | same as the `-DryRun` / `-KeepDeviceBranch` switches |

**Those two local URLs are not interchangeable.** The script talks to the server both
directly (from the host) and through a throwaway CLI container (on the docker network).
`127.0.0.1` inside a container is the *container* — using it for the container-side call
gives `Connection refused` at exactly the wrong moment.

---

## The missing `OMNIGRAPH_TOKEN` (agent memory, not sync)

**This does not affect the sync** — the sync reads tokens from `omnigraph-setup/.env`. It affects the
**MCP bridges**: `agent-skills/.mcp.json` and `basic-analysis/.mcp.json` reference
`${OMNIGRAPH_TOKEN}`, deliberately, because those files are tracked and must never hold a
bearer. With the variable unset, the bridge starts with an empty token and **the agent has
no memory** in those repos.

Set it once per machine (the value is `OMNIGRAPH_TOKEN` in `infra/mcp-servers/.env.shared`):

```powershell
# Windows — persists for future sessions; restart the agent afterwards
[Environment]::SetEnvironmentVariable('OMNIGRAPH_TOKEN', '<token from .env.shared>', 'User')
[Environment]::SetEnvironmentVariable('OMNIGRAPH_BASE_URL', 'http://localhost:8080', 'User')
```

```bash
# Linux/macOS — in ~/.bashrc / ~/.zshrc, or a systemd user env
export OMNIGRAPH_TOKEN=<token from .env.shared>
export OMNIGRAPH_BASE_URL=http://localhost:8080
```

Verify in a **new** shell, then restart the agent:

```powershell
[Environment]::GetEnvironmentVariable('OMNIGRAPH_TOKEN','User')   # non-empty
```
then in a fresh agent session `graphs_list` should return 5 graphs and `schema_get` should
show 11 edge types. If you would rather not put the bearer in your OS environment, the
alternative is a per-project `.mcp.json` under `~/.claude.json` (user-scope, untracked)
holding the literal token — never in the repo's `.mcp.json`.

---

## How it works (and why it is shaped this way)

Per graph, every run:

1. **Back up** local `main` → `omnigraph-setup/backups/local-<graph>-<ts>.jsonl`.
2. **Verify** local for duplicates.
3. **Push the delta** to central `main` — `omnigraph_jsonl.py pushset` emits every node
   whose payload differs from central's (ignoring `id`/`embedding`) plus **only the edges
   central lacks**. If the delta is empty it pushes nothing at all (the common case).
4. **Verify** central.
5. **Pull** via `pull_graph.py`: purge local, then merge-load central's deduped export into
   the now-empty graph. Restores from the backup if the load fails.
6. **Verify** local, sweep any stale `device/<host>` branch.

Four design choices, each bought with an incident:

- **Delta push, never the whole export.** Edges have no `@key`, so merge-loading an edge
  central already has *appends a duplicate*. Pushing everything is what gave central 2×
  edges on every project graph (2026-07-17). Nodes are `@key(slug)` and upsert safely.
- **Skip identical nodes.** Pushing a node that matches central still bumps that table's
  version, and the merge then dies with `Concurrent modification: table version N already
  exists for node:<Type>`.
- **No device branch.** On v0.8.1 `branch create` can hit a Lance internal error
  (`Clone operation should not enter build_manifest`) and `branch merge` the concurrent-
  modification error above. The branch existed for "review before merge", which buys
  nothing on an unattended 5-minute timer. Safety comes from the delta + backups + verify.
- **Purge-then-load for the pull, not `overwrite`.** `load --mode overwrite` into a
  *populated* graph trips a Lance bug (`stage_create_btree_index … all columns in a record
  batch must have the same length`) — and can *land anyway while exiting 1*, so you cannot
  even trust its failure. Loading into an **empty** graph is the one reliable write path.

**The rule behind all of it: verify against the live system, never trust a component's own
report.** Every failure here was something reporting success while doing the opposite. After
a sync, check `edges` vs `distinct edges` — not the exit code alone.

---

## Verifying / troubleshooting

```bash
cd infra/mcp-servers; set -a; . ./.env.shared; . ./omnigraph-setup/.env; set +a

# duplicates on either side (the check that matters)
curl -s -X POST "http://127.0.0.1:8080/graphs/<g>/export" -H "Authorization: Bearer $OMNIGRAPH_TOKEN" \
  -H 'content-type: application/json' -d '{}' | python3 omnigraph-setup/omnigraph_jsonl.py verify
curl -s -X POST "$CENTRAL_URL/graphs/<g>/export" -H "Authorization: Bearer $CENTRAL_TOKEN" \
  -H 'content-type: application/json' -d '{}' | python3 omnigraph-setup/omnigraph_jsonl.py verify
```

| Symptom | What it means / do |
|---|---|
| `edges` > `distinct edges` | duplicates. **Do not sync into it.** Repair: export → `omnigraph_jsonl.py dedup` → compare against `cluster/seed/<g>.jsonl` → delete every node (edges cascade) → merge-load the deduped export → re-verify. Smallest graph first. |
| `all columns in a record batch must have the same length` | the Lance bug. The load failed *staged*, so the graph survives — but it can leave Lance HEAD ahead of the manifest, after which **every** load to that graph fails while reads still work. **`docker restart omnigraph-server`** recovers it; no data lost. |
| `Concurrent modification: table version N already exists` | something pushed an unchanged table. Should not happen now — if it does, `pushset` let an identical node through. |
| `Connection refused` from the CLI container | `LOCAL_URL_CONTAINER` is wrong (probably `127.0.0.1`). `pull_graph.py` pre-flights this and refuses to purge. |
| Sync exits non-zero | read the message — it names the graph and the failing command. Your backup is in `omnigraph-setup/backups/`. Central is only ever touched by a delta, so a failed run leaves it consistent. |
| A `device/<host>` branch lingers | it blocks `schema apply`. `DELETE /graphs/<g>/branches/device%2F<host>`. The sync sweeps its own. |

## Known limitations

- **Merged `Decision`s are invisible to semantic search.** `load --mode merge` does not
  compute the `@embed("rationale")` vector and **erases** it if the record omits one, and an
  unembedded `Decision` is *dropped* from `nearest()` — not ranked low. On v0.8.1 there is
  no working re-embed on a populated graph, so `populate-embeddings.py` only works against a
  fresh one. The nodes stay findable by traversal and full-text.
- **The Linux `omnigraph-sync.sh` is unfixed** (see the warning above).
- **Conflict resolution is last-writer-wins per node**, decided by payload difference. There
  are no timestamps in the schema, so a genuine two-sided edit of the same node cannot be
  merged intelligently — local wins on the push, then the pull makes local match central.

# Setup — Server & Clients

How to run the Omnigraph memory stack (the **server**) and connect **clients**
(your workstation, laptop, other agents), including offline use and automatic
sync.

## Roles

```
                         ┌──────────────────────────────────────┐
   coding.vm (SERVER) ── │ omnigraph-server + MinIO + viewer     │
   always-on            │ authoritative `main` branch           │
                         │ exposed: omnigraph.ohje.ooguy.com     │
                         └──────────────────────────────────────┘
        ▲ HTTPS + bearer (online)          ▲ sync when online
        │                                  │
  ┌───────────────┐                 ┌──────────────────────────┐
  │ CLIENT online │                 │ CLIENT offline-capable   │
  │ MCP → central │                 │ local omnigraph + sync   │
  │ writes `main` │                 │ writes local `main`      │
  └───────────────┘                 └──────────────────────────┘
```

- **Server** = the single-source stack in
  `Server/server/coding/mcp-servers/docker-compose.yml` on `coding.vm`. It owns
  the authoritative `main` branch.
- **Client, online** = points its `omnigraph` MCP straight at
  `https://omnigraph.ohje.ooguy.com` with the bearer token and works on `main`.
  Nothing to sync — this is the smartest thing when connected.
- **Client, offline-capable** = runs a *local* copy of the stack and works on its
  local `main`; a sync timer reconciles with the server whenever the internet is
  back. See "Offline & sync" below.

## Server setup (coding.vm)

Already deployed. To (re)create:

```bash
cd Server/server/coding/mcp-servers
cp .env.example .env         # fill MINIO_ROOT_PASSWORD + OMNIGRAPH_TOKEN (openssl rand -hex 32)
docker compose up -d
curl -fsS http://127.0.0.1:8080/healthz
```

Expose via OPNsense os-caddy (already in `server/network/opnsense/caddy.d/`):
`omnigraph.ohje.ooguy.com` (API, bearer only) and `omnigraph-ui.ohje.ooguy.com`
(viewer, Authelia).

## Client setup

Use [`client-setup.sh`](client-setup.sh):

```bash
# Online client (default): register the MCP against the central server.
./client-setup.sh --mode online \
  --url https://omnigraph.ohje.ooguy.com --token <BEARER>

# Offline-capable client: bring up a local stack + install the sync timer.
./client-setup.sh --mode offline \
  --url https://omnigraph.ohje.ooguy.com --token <BEARER>
```

Online mode just prints/creates the MCP registration (e.g. for Claude Code:
`claude mcp add ... omnigraph`, pointing `OMNIGRAPH_URL` at the central URL).

## Offline & sync (device branches, automatic merge)

**Goal:** agents never manage branches by hand. They always talk to one stable
local endpoint; the automation reconciles with the server.

**When online** there is nothing to do — the client uses the central `main`
directly (online mode). **When a client may go offline**, it runs a local stack
and [`omnigraph-sync.sh`](omnigraph-sync.sh) on a timer
([`omnigraph-sync.timer`](omnigraph-sync.timer)). Each run:

1. Probes the server (`/healthz`). Offline → exit quietly (agent keeps working
   on the local `main`).
2. Online → merges the device's changes onto the server under a per-device
   branch `device/<host>`, then merges that branch into `main`, then pulls
   `main` back to local. Node conflicts resolve by **slug-keyed upsert**
   (last-writer-wins per node); the merge is idempotent for nodes.

So agents write to local `main` and stay dumb about branches; the sync creates
`device/<host>`, merges, and reconciles automatically.

### Honest caveats

- **Edges are not slug-keyed**, so a naive cross-store `export → load --merge`
  can duplicate edges over repeated syncs. `omnigraph-sync.sh` therefore prefers
  Omnigraph's **native `branch merge`** (correct, de-duplicating) when both sides
  share a store, and de-duplicates edges by `(type,from,to)` on the export/merge
  path. For heavy multi-writer use, consider adding `@unique` to edge endpoints
  in `memory.pg` (a schema migration) so edge merges are truly idempotent.
- **True disconnected multi-writer** (two devices editing the same node offline)
  is last-writer-wins on reconnect. For review instead of auto-resolve, keep the
  `device/<host>` branch and merge it manually (visible in the viewer's branch
  nav). This is the escape hatch when automation shouldn't decide.
- **Storage sync alternative:** instead of a local server, mirror the MinIO
  bucket with `mc mirror` / bucket replication for a read cache. Do **not** point
  two live servers at one blindly-replicated bucket (Lance manifest conflicts).

### Sync helpers & the remote test

- [`omnigraph-sync.sh`](omnigraph-sync.sh) (Linux, `--network host`) and
  [`sync-windows.ps1`](sync-windows.ps1) (Docker Desktop: compose network +
  stdin, no `--network host`) run the reconcile with a **local backup first** and
  a **no-duplicates guarantee** — nodes dedupe by slug, edges are de-duplicated
  and verified via [`omnigraph_jsonl.py`](omnigraph_jsonl.py); the local pull is
  an `overwrite` of a deduped central export.
- `-DryRun` / `DRY_RUN=1` snapshots + verifies **both** sides without writing.
- Backups land in `omnigraph-setup/backups/local-main-<ts>.jsonl` (gitignored).
- The full production send/merge procedure — canary-first, the embedding
  reconciliation (standardize on CPU-capable `nomic-embed-text`), risks and
  rollback — is in
  [`../../../docs/REMOTE-SYNC-TEST-PLAN.md`](../../../docs/REMOTE-SYNC-TEST-PLAN.md).

See [`../servers/omnigraph/README.md`](../servers/omnigraph/README.md) and the
[`structured-memory`](../../../skills/structured-memory/SKILL.md) skill.

## Automatic dedup (server-side)

Omnigraph auto-merges nodes that share a slug (@key), but two things it cannot
collapse on its own: (a) the same node under DIFFERENT slugs (a case variant like
`Invest` vs `invest`, or slug drift), and (b) **duplicate edges** — edges are not
slug-keyed, so any cross-store `export → load --merge` (a device-branch merge, or
reconciling two clients) APPENDS them, and the GQ API has **no way to delete an
individual edge** (edges expose no queryable `id`, and `where from=.. and to=..`
does not parse). [`../scripts/dedup-graph.py`](../scripts/dedup-graph.py) fixes
both: it groups nodes by `(type, casefold(slug))` (add `--by-name` for same-label
too), picks a canonical slug, redirects the duplicates' edges, merges fields, and
**de-dupes edges by `(type,from,to)`**, then rebuilds (export → reset store →
`load --mode overwrite`, the one reliable write path on v0.8.1). It triggers on
node **or** edge duplicates, so the hourly timer keeps the graph clean after any
device sync. It is **idempotent** and a **cheap no-op when clean** (only rebuilds
when duplicates exist — a brief outage then). Preview with `--dry-run`.

> **This is the only way to remove duplicate edges** — a client (Windows/laptop)
> cannot, because the fix needs a store reset (MinIO volume) on the server host.
> After a cross-store merge leaves dup edges on central, the client sync's
> `verify` gate correctly **refuses to pull** (protecting the clean local copy)
> until this server-side sweep runs.

Run it on the **memory server host** on a timer (not on clients — one authority
dedups). Install [`dedup-graph.service`](dedup-graph.service) +
[`dedup-graph.timer`](dedup-graph.timer):

```bash
mkdir -p ~/.config/systemd/user
cp dedup-graph.service dedup-graph.timer ~/.config/systemd/user/
systemctl --user enable --now dedup-graph.timer     # hourly sweep
```

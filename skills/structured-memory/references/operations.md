# Omnigraph operations & gotchas

Hard-won operational rules for the self-hosted **Omnigraph** memory graphs — **one graph
per project** (`agent-skills`, `basic-analysis`, …) plus the shared **`memory`** graph,
which holds only global-scope `Preference`s. Following these avoids the failure modes we
already debugged (duplicate edges, corrupted merges, un-rankable search, silently-rejected
edges, a broken `main`). Read this before querying, mutating, loading, or syncing.

Server: `omnigraph-server` v0.8.1 · MCP bridge `@modernrelay/omnigraph-mcp`
(tools `schema_get`, `query`, `mutate`, `load`, `branches_*`, `commits_list`,
`snapshot`, `health`, `graphs_list`). Central: `https://omnigraph.ohje.ooguy.com` (bearer).

## The rules

0. **Declared ≠ live.** `cluster.yaml` and `memory.pg` are a *declaration*; nothing is
   real until `scripts/apply-cluster.sh` converges it into the server's state ledger.
   Verify against the server — `graphs_list` for graphs, `schema_get` for edge types —
   never by reading the config. This is not hypothetical: the declaration went unapplied
   for a long time, so five edge types (`Tracks`, `Affects`, `Addresses`, `Implements`,
   `DependsOn`) did not exist and **every write using them failed silently**, orphaning
   nodes that then rendered as "global".

1. **Read the schema first.** Call `schema_get` (or read `omnigraph://schema`)
   before any query/mutate/load. It declares node/edge types, `@key` fields,
   non-nullable props, and edge directions. Writing blind lint-fails or silently
   corrupts data. Also consult `omnigraph://best-practices/{queries,data,search}`.

   A bridge is **pinned to one graph** by `OMNIGRAPH_GRAPH_ID`, and no tool takes a graph
   argument — so `schema_get`/`query`/`mutate` always act on that graph. Reading a second
   graph (e.g. global `Preference`s in `memory`) requires a **second** MCP server entry.

2. **Edge GQ casing is asymmetric.** `insert`/`delete` use the **PascalCase edge
   TYPE** name; **match/traversal** uses **lowerCamelCase**.
   - write: `insert DecidedIn { from: $d, to: $p }` · `delete AppliesTo where ...`
   - read: `match { $d: Decision  $d decidedIn $p }`
   - `insert decidedIn { ... }` fails with `parse error: expected type_name`.
   - Edge `data` block is `{}` when the edge has no properties — just `from`/`to`.

3. **D₂ rule — a mutation is insert/update-only OR delete-only, never both.**
   Mixing a `delete` with an `insert`/`update` in one query is rejected at parse
   time. Split delete-then-insert into two separate `mutate` calls.

4. **Parameterize; never string-interpolate.** `query q($slug: String) { ... }`
   with `params: {slug: ...}`. Ranking ops (`nearest`/`bm25`/`rrf`) require a
   trailing `limit N` — they order, they don't filter.

5. **Verify every write.** `commits_list` head before/after, or re-export and
   diff. A 504 is **not** failure — the server may commit after the proxy drops
   the response; check the head before retrying (blind retries duplicate
   append-only nodes like `Decision`).

6. **Duplicate edges are the classic trap.** Edges are **not** slug-keyed, so a
   cross-store `load --mode merge` (device-branch merge, reconciling two clients)
   **appends** them → duplicates. There is **no API to delete an individual edge**
   (edges expose no queryable `id`; `where from=.. and to=..` doesn't parse).
   Two fixes:
   - **Client-side:** deleting a **node cascades its edges** (verified). To fix a
     node's dup edges, `delete <Type> where slug=$s` then `load --mode merge` the
     node back with its correct single edges — a fresh load onto an edge-free node
     makes no dups.
   - **Server-side (bulk):** `infra/mcp-servers/scripts/dedup-graph.py`
     (edge-aware — triggers on node OR edge dups; export → dedup by
     `(type,from,to)` → reset store → overwrite-load). Needs docker on the server
     host; runs hourly by timer on coding.vm.
   - **Prevent it:** prefer native `branches_merge` (edge-de-duplicating) over raw
     `load --merge` for cross-store reconciliation.

7. **Never `overwrite` a shared `main`.** It clobbers other projects' data, and
   overwrite-on-a-populated graph hits a Lance index bug on v0.8.1. Use
   `merge` / `branches_merge` on `main`; `overwrite` is only safe on a fresh store
   or a throwaway branch you own.

8. **Replace one project's subgraph on a shared `main` cleanly** (the proven
   recipe, e.g. pushing a repo's refreshed memory up): (a) `delete <Type> where
   slug=..` every child node of that project (edges cascade); (b) `load --mode
   merge` the project's node+edge subset exported from the source (fresh → zero
   dup edges). Keep the `Project` node; select the subset by slug prefix. Verify
   the two sides' node+edge sets are then identical.

9. **Slugs: lowercase kebab-case, stable.** Auto-merge keys on `slug`; a case
   variant (`Invest` vs `invest`) or drift creates a **duplicate node** it can't
   collapse on its own (then needs `dedup-graph.py`). Reuse the same slug to make
   re-writes idempotent.

10. **Embeddings = `nomic-embed-text` (768-dim), CPU-capable.** That is the
    Omnigraph provider on local and central. `bge-m3` (1024-dim) is **only** the
    mem0-fallback embedder — not this graph. New `Decision` nodes can arrive
    **unembedded**; embed rationales via local Ollama and merge-load the nodes
    (`scripts/populate-embeddings.py`, or embed 768-dim vectors and `load --merge`
    the nodes only — no edge changes, so no dup risk). Mixed embedding spaces make
    `nearest()` ranking inconsistent — standardize on `nomic-embed-text`.

11. **You do not manage device branches.** Write durable memory to `main`; the
    sync automation (`setup/omnigraph-sync.sh` / `sync-windows.ps1` on a timer)
    creates `device/<host>`, merges to central `main`, and reconciles back. The
    sync **verify gate refuses to pull a central that has duplicates** — that is
    correct (it protects a clean local); clean central (rule 6) then re-sync.

12. **Remote ops from a client** use the CLI-in-container (bearer + public URL),
    e.g. `docker run --rm -i --network <compose-net> -e OMNIGRAPH_BEARER_TOKEN=…
    --entrypoint omnigraph <image> query|mutate|load|export --server <URL>
    --graph memory`. Destructive remote writes need `--yes`. You **cannot** reset
    the central store from a client (needs coding.vm docker access).

## Quick reference — safe write patterns

| Goal | Do |
|---|---|
| Upsert nodes idempotently | `load --mode merge` (keyed by slug) |
| Add an edge | `insert <PascalEdge> { from, to }` (once — re-running dups it) |
| Change a Decision | new `Decision` + `insert Supersedes {from:new,to:old}`; set old `status: superseded` |
| Remove a node's dup edges | `delete <Type> where slug=$s` → `load --merge` node + correct edges |
| Push a repo's memory to central | delete its child nodes on `main` → `load --merge` its fresh subset |
| Bulk clean dups | run `scripts/dedup-graph.py` on the server host |

See also: [schema.md](schema.md), `infra/mcp-servers/setup/README.md`,
`docs/REMOTE-SYNC-TEST-PLAN.md`.

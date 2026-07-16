---
name: structured-memory
description: Store and retrieve durable, cross-project, cross-agent memory as typed nodes in the self-hosted Omnigraph graph — decisions, rules, preferences, conventions, components, and tasks. Use at session start to load what was already decided, and at session end (or when a durable decision is made) to persist it. Replaces Mem0's automatic fact extraction with an explicit, reviewable protocol. Do not use for transient scratch notes or single-session state.
---

# Structured Memory (Omnigraph)

The self-hosted memory layer is **Omnigraph** — a graph store with combined
graph-traversal + vector + full-text retrieval. Unlike Mem0, Omnigraph does not
auto-extract memories from conversation. **You** decide what is durable and write
it as a typed node. This is deliberate: typed, reviewable memory keeps rules and
decisions integrated across future builds.

Schema (node/edge types, `.pg` declaration, JSONL ingest examples):
[references/schema.md](references/schema.md).

**Operational rules & gotchas — read before any query/mutate/load/sync:**
[references/operations.md](references/operations.md) (edge casing, the D₂
insert-xor-delete rule, duplicate-edge handling, never-overwrite-shared-`main`,
lowercase slugs, `nomic-embed-text` 768-dim embeddings, remote CLI ops). These
capture failure modes already debugged — honoring them avoids re-troubleshooting.

MCP server: `@modernrelay/omnigraph-mcp`. Tools: `schema_get` (read schema
first), `query` (read GQ), `mutate` (write GQ, insert/update/delete), `load`
(bulk NDJSON upsert by `@key`), `branches_create` / `branches_merge` /
`branches_delete`, `commits_list` (verify writes), `snapshot`, `health`.

## First action every session — recall

Before editing code, load prior memory for the current project:

1. Identify the project slug (the repository folder name, e.g. `agent-skills`).
2. Query the project subgraph for `Rule`, `Decision`, `Preference`, `Convention`
   nodes edged to that `Project`, plus global `Preference` nodes (`scope: global`).
   Use a fused query (graph + vector + full-text) via the `query` tool, e.g.
   ask "rules and decisions for project `<slug>`" and "conventions applying to
   `<slug>`".
3. Treat the returned `Rule (must)` nodes as hard constraints and `Decision`
   nodes as settled context. Do not re-litigate accepted decisions.

If the graph has no `Project` node for the current repo yet, create one (see
Persist) — that is the signal this repo hasn't been onboarded to memory.

## When to persist

Write a node when something is **durable** — true beyond this session:

- A decision with a rationale → `Decision` (+ `DecidedIn` → `Project`).
- A hard constraint the team must follow → `Rule` (+ `ConstrainsProject`).
- A soft, overridable inclination → `Preference` (`scope: global` or project).
- A repeatable pattern → `Convention` (+ `AppliesTo`).
- A notable system part → `Component` (+ `PartOf` → `Project`).
- Planned/ongoing work worth remembering → `Task` (+ `Tracks` → `Project`).

Do **not** persist: transient reasoning, one-off file paths, or anything already
captured in code, `CHANGELOG.md`, or an ADR (link to those instead).

## Link richly — make it a graph, not a star

Two edge rules keep the graph correct and navigable:

1. **Always attach a project-specific node to its `Project`** (the hub edge above).
   A node with **no** edge to a `Project` renders as **"global"** — and *global is
   reserved for genuinely cross-project facts* (a handful of `Preference`s like
   "prefer TDD"). A project-specific `Rule`/`Decision`/`Task` showing as global is
   a **bug**: it means you forgot the hub edge. Never mark project-specific info
   global.
2. **Also link a node to the specific nodes it relates to** — not only the hub.
   Most memory is a star (everything → `Project`) because agents add just the hub
   edge; that graph is unnavigable. When you add a node, ask *"what existing
   component/decision does this touch?"* and add the relational edge too:
   - `ConstrainsComponent`: Rule → the Component it governs
   - `Affects`: Decision → the Component it changes
   - `Addresses`: Task → the Component it works on · `Implements`: Task → the Decision it realizes
   - `DependsOn`: Component → Component · `Supersedes`: Decision → the Decision it replaces

   Smell test: a new node whose **only** edge is to the `Project` is probably
   under-linked. Aim for at least one relational edge where a real relationship
   exists.

## How to persist — branch, write, merge

Memory writes are reviewable like code:

1. Create a working branch off `main` with `branches_create`
   (e.g. `mem/<project-slug>/<short-topic>`).
2. Write typed nodes/edges with `load` (bulk NDJSON, `mode: merge`) or `mutate`
   (single GQ writes), using stable **lowercase** kebab-case slugs so re-writes
   are idempotent. Mind the edge-casing and D₂ rules in
   [references/operations.md](references/operations.md).
3. Merge the branch into `main` with `branches_merge` (edge-de-duplicating —
   prefer it over a raw cross-store `load --merge`, which appends duplicate
   edges). Prefer many small, self-describing writes over one large dump.

Supersede, don't overwrite, an accepted `Decision`: write the new `Decision` and
a `Supersedes` edge to the old one; set the old one's `status` to `superseded`.
Never `overwrite` the shared `main`.

## You do not manage device branches — sync is automatic

Always read/write the memory server your client is configured with, on `main`.
**Do not create or merge device branches yourself.** When your device is online
it uses the central `main` directly; when it is offline it uses a local `main`,
and a background service (`infra/mcp-servers/setup/omnigraph-sync.sh` on a timer)
creates a `device/<host>` branch, merges it into central `main`, and reconciles
back — resolving node conflicts by slug-keyed upsert. So just write durable
memory to `main`; the automation handles branching, pushing, and merging. See
`infra/mcp-servers/setup/README.md`.

## Cross-project model — one graph per project (hard isolation)

**Each project's memory lives in its OWN Omnigraph graph, named after the repo**
(`agent-skills`, `invest`, `basic-analysis`, `homelab-server`, …). Projects are
never merged into one shared store — a `load mode: overwrite` or a bad write in
one project's graph can't touch another's. The shared **`memory`** graph now
holds **only** global-scope `Preference`s (house style, TDD-default) — never
project data.

- **Point your agent at its project graph**: set `OMNIGRAPH_GRAPH_ID=<repo>` for
  the omnigraph MCP bridge (a project-scoped `.mcp.json` env, or export it before
  launching). If it is still `memory`, you are on the globals graph — switch it.
  **Never write project-specific nodes to the shared `memory` graph.**
- **Inside your project graph, still scope + link:** every project-specific node
  is a `Project` node's satellite — edge it to the `Project` (slug = repo folder
  name) and add relational edges (see "Link richly" above). Recall global
  `Preference`s from the `memory` graph when you need house style.
- **Add a new project graph**: `infra/mcp-servers/scripts/add-project-graph.sh
  <name>` then `./scripts/apply-cluster.sh` (declared in `cluster/cluster.yaml`,
  converged into the live cluster with a snapshot + node-count verify).
- **Seeds** (`cluster/seed/<name>.jsonl`) load into the graph matching the file
  name, so a rebuild stays isolated — never re-merged. `memory.jsonl` = globals.
- **Browse any graph**: the viewer's **graph** selector switches between them.

## Multi-user

- **Humans** log in via **Authelia (SSO through Caddy)** in front of the viewer —
  that is the multi-user login. The viewer itself has no auth; never expose it
  without the proxy.
- **Agents / API** are identified by their **bearer token → named actor**. Give
  each user their own token and a personal graph (e.g. `u-alice`) that only they
  can read/write, plus read-only access to shared `memory`. Scope it with Cedar
  policy — see `cluster/users.policy.yaml.example`. Minting tokens is an admin /
  `apply-cluster.sh` step (tokens are cluster secrets, never committed).

## Fallback

If Omnigraph is unavailable, the `mem0-fallback` Docker Compose profile can be
started (see `infra/mcp-servers/`). When on the fallback, apply the same protocol
conceptually — store typed statements as memory text and scope by `user_id` =
project slug — but prefer restoring Omnigraph. See
`docs/decisions/0001-omnigraph-over-mem0.md`.

## Checklist

- [ ] Recalled project + global memory before editing.
- [ ] Honored `Rule (must)` nodes as hard constraints.
- [ ] Persisted new durable decisions/rules/conventions as typed nodes.
- [ ] Used a branch, stable slugs, and `supersedes` for changed decisions.

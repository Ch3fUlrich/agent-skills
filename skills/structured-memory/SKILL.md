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

MCP server: `@modernrelay/omnigraph-mcp`, tools `schema`, `branches`, `queries`,
`mutations`, `ingest`.

## First action every session — recall

Before editing code, load prior memory for the current project:

1. Identify the project slug (the repository folder name, e.g. `agent-skills`).
2. Query the project subgraph for `Rule`, `Decision`, `Preference`, `Convention`
   nodes edged to that `Project`, plus global `Preference` nodes (`scope: global`).
   Use a fused query (graph + vector + full-text) via the `queries` tool, e.g.
   ask "rules and decisions for project `<slug>`" and "conventions applying to
   `<slug>`".
3. Treat the returned `Rule (must)` nodes as hard constraints and `Decision`
   nodes as settled context. Do not re-litigate accepted decisions.

If the graph has no `Project` node for the current repo yet, create one (see
Persist) — that is the signal this repo hasn't been onboarded to memory.

## When to persist

Write a node when something is **durable** — true beyond this session:

- A decision with a rationale → `Decision` (+ `decided-in` → `Project`).
- A hard constraint the team must follow → `Rule` (+ `constrains`).
- A soft, overridable inclination → `Preference` (`scope: global` or project).
- A repeatable pattern → `Convention` (+ `applies-to`).
- A notable system part → `Component` (+ `part-of`).
- Planned/ongoing work worth remembering → `Task`.

Do **not** persist: transient reasoning, one-off file paths, or anything already
captured in code, `CHANGELOG.md`, or an ADR (link to those instead).

## How to persist — branch, write, merge

Memory writes are reviewable like code:

1. Create a working branch off `main` with the `branches` tool
   (e.g. `mem/<project-slug>/<short-topic>`).
2. Write typed nodes/edges with `ingest` (JSONL) or `mutations` (single writes),
   using stable kebab-case slugs so re-writes are idempotent.
3. Merge the branch into `main`. Prefer many small, self-describing writes over
   one large dump.

Supersede, don't overwrite, an accepted `Decision`: write the new `Decision` and
a `supersedes` edge to the old one; set the old one's `status` to `superseded`.

## You do not manage device branches — sync is automatic

Always read/write the memory server your client is configured with, on `main`.
**Do not create or merge device branches yourself.** When your device is online
it uses the central `main` directly; when it is offline it uses a local `main`,
and a background service (`infra/mcp-servers/setup/omnigraph-sync.sh` on a timer)
creates a `device/<host>` branch, merges it into central `main`, and reconciles
back — resolving node conflicts by slug-keyed upsert. So just write durable
memory to `main`; the automation handles branching, pushing, and merging. See
`infra/mcp-servers/setup/README.md`.

## Cross-project model

- One shared graph. Every project is a `Project` node; project-specific memory
  edges back to it. A move between repos is just a different project scope, not a
  different store.
- Global facts (user preferences, house style) are `Preference` nodes with
  `scope: global`; recall them in every project.
- This replaces Mem0's `user_id` isolation: scope by `Project` edges and the
  `scope` field, not by a per-call user id.

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

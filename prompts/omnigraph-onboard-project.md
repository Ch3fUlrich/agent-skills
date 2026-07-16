# Prompt — onboard a project onto Omnigraph memory

Send this to a coding agent working **inside a specific project repo** (Claude
Code, Codex, Gemini, …). It makes the agent (1) add the Omnigraph handling rules
to that repo's own agent-instruction files, and (2) pull this project's memory
from the remote Omnigraph server and reconcile it.

Replace nothing — the agent resolves `<repo>` from its own working directory.
Copy everything in the block below:

---

You have a self-hosted **Omnigraph** memory server available via MCP (tools:
`schema_get`, `query`, `mutate`, `load`, `branches_*`, `commits_list`). It is the
single source of truth for this project's durable memory. Do two things.

**A. Record how to handle Omnigraph in this repo's agent-instruction files.**

1. Identify this repo's instruction files that exist: `CLAUDE.md`, `AGENTS.md`,
   `GEMINI.md`, `.github/copilot-instructions.md` (create the ones your agent
   uses if absent).
2. Into each, add (or update) a short **"Memory — Omnigraph"** section stating:
   - Omnigraph is the memory layer, and **this repo has its OWN graph, named after
     the repo folder** (per-project isolation — projects are never merged). Point
     the omnigraph MCP bridge at it with **`OMNIGRAPH_GRAPH_ID=<repo-folder-name>`**
     (a project-scoped `.mcp.json` env, or exported before launching the agent). If
     the bridge still says `memory`, you are on the shared globals graph — switch it.
   - The shared **`memory`** graph holds ONLY global-scope `Preference`s. **Never
     write this project's data to `memory`.** If any Mem0 / `user_id` instructions
     remain, replace them.
   - **Recall at session start**, **persist durable facts** (typed
     `Decision/Rule/Preference/Convention/Component/Task` nodes), and
     **link richly — a graph, not a star**: attach every node to its `Project`
     (slug = repo folder name) AND add at least one relational edge
     (`ConstrainsComponent`, `Affects`, `Addresses`, `Implements`, `DependsOn`,
     `Supersedes`). A project-specific node with no `Project` edge is a bug (shows
     as "global").
   - **Never `load --mode overwrite` a populated graph / shared `main`**; supersede
     accepted decisions; verify writes with `commits_list`.
   - Point to the full protocol: `~/code/agent-skills/skills/structured-memory/SKILL.md`
     (and `~/code/agent-skills/starters/mcp-servers/AGENTS.md` for the copy-ready
     section). Keep the repo's section a short pointer; don't duplicate the skill.

**B. Pull this project's memory from remote and reconcile it.**

1. Confirm the bridge targets your project graph (`OMNIGRAPH_GRAPH_ID=<repo>`), then
   read `omnigraph://schema` first (never query/mutate without it).
2. Ensure a `Project` node exists in **your project graph** with
   `slug = <this repo's folder name>`. If missing, create it
   (`insert Project { slug, name, path, summary }`).
3. **Recall**: query every `Rule/Decision/Preference/Convention/Component/Task` in
   your project graph edged to this `Project`. (Global house-style `Preference`s
   live in the shared `memory` graph — read them there if you need them.) Treat the
   result as ground truth; note anything that conflicts with the current code.
4. **Reconcile / update**: for durable facts about this repo that are true now but
   missing, persist them as typed nodes **in your project graph**, edged to the
   `Project`, with the relational edges from rule A. Stable lowercase kebab-case
   slugs so re-runs are idempotent (`load --mode merge`, never `overwrite`).
5. **Verify**: `commits_list` head before/after each write; if unchanged, the write
   did not land — retry. Report a short summary: graph used, nodes recalled, nodes
   added, and any conflicts between the graph and the code.

Do not invent relationships you are not confident about; only add edges that
reflect real, verifiable relationships in this repo.

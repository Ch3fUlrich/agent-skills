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
   - Omnigraph is the memory layer. **Isolate this project by edging every node
     to a `Project` node whose slug is this repo's folder name** — NOT a per-call
     `user_id`. If any Mem0 / `user_id` instructions remain, replace them.
   - Cross-project facts are `Preference` nodes with `scope: global`.
   - **Recall at session start**, **persist durable facts** (typed
     `Decision/Rule/Preference/Convention/Component/Task` nodes), and
     **link richly — a graph, not a star**: attach every node to its `Project`
     AND add at least one relational edge (`ConstrainsComponent`, `Affects`,
     `Addresses`, `Implements`, `DependsOn`, `Supersedes`) to the node it touches.
     A project-specific node with no `Project` edge is a bug (it shows as "global").
   - **Never `load --mode overwrite` the shared `main`**; supersede accepted
     decisions; verify writes with `commits_list`.
   - Point to the full protocol: `~/code/agent-skills/skills/structured-memory/SKILL.md`
     (and to `~/code/agent-skills/starters/mcp-servers/AGENTS.md` for the copy-ready
     section). Keep the repo's section a short pointer; don't duplicate the skill.

**B. Pull this project's memory from remote and reconcile it.**

1. Read `omnigraph://schema` first (never query/mutate without it).
2. Ensure a `Project` node exists with `slug = <this repo's folder name>`. If it
   is missing, create it (`insert Project { slug, name, path, summary }`).
3. **Recall**: query every `Rule/Decision/Preference/Convention/Component/Task`
   edged to this `Project`, plus global `Preference`s (`scope: global`). Treat the
   result as ground truth for how this repo works; note anything that conflicts
   with the current code.
4. **Reconcile / update**: for durable facts about this repo that are true now but
   missing from the graph (key decisions-with-rationale, hard rules, build/test
   commands, main components), persist them as typed nodes edged to the `Project`,
   with the relational edges from rule A. Use stable lowercase kebab-case slugs so
   re-runs are idempotent (`load --mode merge`, never `overwrite`).
5. **Verify**: `commits_list` head before/after each write; if unchanged, the write
   did not land — retry. Report a short summary: nodes recalled, nodes added, and
   any conflicts you found between the graph and the code.

Do not invent relationships you are not confident about; only add edges that
reflect real, verifiable relationships in this repo.

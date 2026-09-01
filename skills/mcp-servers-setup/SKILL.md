---
name: mcp-servers-setup
description: Configure and use the self-hosted MCP server stack (Serena, Graphify, Omnigraph memory, Superpowers, Playwright) for token-efficient coding, and publish container images to the private Harbor registry.
---

# MCP Servers Setup

This skill ensures proper configuration and usage of the self-hosted MCP server
stack across all repositories under your `${CODE_ROOT}` (the parent directory of
your projects).

## First Action — Always

**On every session start (first prompt), activate the Serena MCP server, recall
structured project memory from Omnigraph, and use Graphify when the repo already
has a graph:**

```
mcp_serena_activate_project(project="<ABSOLUTE path to the repo root>")   # never a bare name
# Recall typed memory (rules/decisions/preferences) for this project + global scope:
#   follow skills/structured-memory/SKILL.md (Omnigraph queries)

# If graphify-out/graph.json exists, prefer graph queries for broad structure questions
```

This loads the full project context: module structure, recent decisions,
commands, and constraints. Do this before any code changes — the memory graph is
the ground truth for what exists and how it works. Memory details:
`skills/structured-memory/SKILL.md`.

## Active MCP Servers

### Serena — Semantic Code Navigation (LSP)

| Tool | Purpose | Token Savings |
|------|---------|:---:|
| `mcp_serena_find_symbol` | Find definitions | 90%+ vs file read |
| `mcp_serena_find_referencing_symbols` | Find all call sites | 80%+ vs multi-file read |
| `mcp_serena_get_symbols_overview` | Module structure | 95%+ vs full file read |
| `mcp_serena_find_declaration` | Find where symbol is defined | 90%+ vs file read |

#### Wiring — user scope only. Serena is graphify-shaped, not omnigraph-shaped

**Define Serena once, in user scope, and never give it a per-repo project-scope entry.**
It is selected by **path** at call time (`activate_project(<absolute path>)`), and its
per-repo configuration is `.serena/project.yml`, which is **tracked in the repo**. A
project-scope `.mcp.json` entry therefore pins nothing the tracked file does not already
say — it only adds a second definition.

**Contrast with omnigraph — do not apply one's rule to the other.** Omnigraph *is*
per-repo/project-scoped (pinned by `OMNIGRAPH_GRAPH_ID`) because each repo is a distinct
graph on a shared server. Serena, like graphify, is selected at runtime and needs no
per-repo pin.

**A duplicate definition does not resolve to one winner — both run.** Measured in
`gen-analysis`, 2026-09-01: **five** Serena servers alive, one carrying `--context
claude-code` (the user-scope entry) and four without it (the project-scope entry, one per
open session). The session's `mcp__serena__*` calls landed on a *project-scope* process:

```
Active context: desktop-app          ← not claude-code
Available projects: gen-analysis     ← one; the real home registers eleven
```

Running in `desktop-app` context re-adds the tools the `claude-code` context exists to
strip, so their schemas are paid for twice — and the project roster is wrong besides.

> **Every path in an MCP `env` block must be absolute.** Claude Code expands `${VAR}` in MCP
> env values — the same `.mcp.json` relies on that for `${OMNIGRAPH_TOKEN}` — but it does
> **not** expand a leading `~`. So `"SERENA_HOME": "~/.serena"` is a *relative directory
> name*, and Serena builds a complete second home at `./~/.serena/` inside the working tree:
> its own `serena_config.yml` (so the global `excluded_tools` never applies and
> `execute_shell_command` / `read_file` / `list_dir` / `search_for_pattern` are re-exposed),
> its own `logs/` — where the real diagnostics go instead of `~/.serena/logs/` — and its own
> `language_servers/`, **237 MB** of partial re-download beside the 1,023 MB real home. It
> stayed invisible to `git status` only because that repo's `.gitignore` happened to carry
> `~*` for editor backups. **There is no error.** Use an absolute path, or omit the variable
> and let the tool use its own default. (Measured 2026-08-31; it took Serena down completely.)

**Usage**: activate by absolute path, then use symbolic tools:
```
mcp_serena_activate_project(project="C:/Users/<you>/Documents/Code/agent-skills")  # absolute
mcp_serena_find_symbol(name_path_pattern="function_name")
```

> **"Activation succeeded" is not evidence that Serena works.** `activate_project` returns
> success and lists every declared language as an active language server **even when seven of
> them are dead**. You find out at the first symbol call, which errors with `The language
> server manager is not initialized` — naming neither the language nor the cause. Run the
> health-check below instead of trusting activation.

#### Languages — declare only what has a call graph

**Project isolation & settings**: automatic via `.serena/project.yml` per repo. When you set
the language list, the bar is **not** "does the server start" — they all start.

> **Never list a language whose server is not in the image — `markdown` above all.**
> A missing server does not degrade to "no symbols for that language": its `initialize`
> fails, the language server **manager** fails with it, and every symbol tool for that
> project then errors with `The language server manager is not initialized`. The repo goes
> dark, and the message names neither the language nor the cause. `marksman` is not in the
> serena image, and markdown has no call graph worth an LSP anyway — headings are a grep.
> This took Invest's Serena down completely until 2026-07-20.
>
> After editing `project.yml`, **restart Serena** — it holds the activated project in memory
> and will not re-read the file on its own.

**The rule: declare only programming languages the repo actually contains.** `json`, `yaml`,
`toml` and `markdown` are never candidates, however many matching files there are. A file
count tells you a language is worth *testing*; it never tells you it belongs.

All six of `bash, json, python, rust, toml, yaml` start cleanly, which is exactly why
"proven working" was the wrong bar. Measured with `serena project health-check`, adding one
set at a time against the real (absolute) home, 2026-09-01:

| Languages declared | Symbol the check selected | `find_referencing_symbols` |
|---|---|---|
| `python`, `rust` | `_start_lifecycle_maintenance` — Function, 1 match | **works** — 1 reference |
| `+ json` | `$comment` — from `.mcp.json` | **fails** |
| `+ toml` | `build-system` — from `pyproject.toml` | **fails** |
| `+ yaml` | `name` — String, **13 matches** | **fails** |

Every data-format server floods the symbol namespace with configuration keys, and none
implements `textDocument/references`, so reference lookups break on whatever they surface.
Startup went **5 s → 16 s** with all six declared. Serena's own config agrees — from the
`ls_priorities` comment in `serena_config.yml`: `0` = *"experimental or secondary language
servers, which are never auto-detected … also applies to non-programming languages like
`json`"*.

#### Verify with `health-check` — the failure is invisible without it

```bash
SERENA_HOME=/absolute/path/to/.serena uvx --from serena-agent==1.7.0 serena project health-check .
```

It starts every declared language server, picks a symbol, and exercises `find_symbol` and
`find_referencing_symbols`. Require **both** `Health check completed successfully` **and** a
`FindReferencingSymbolsTool found N references` line — a `failed for symbol` warning sitting
above a "successful" completion is the data-format problem above.

- **On Windows it ends in a `UnicodeEncodeError`** printing `✅` under cp1252 — from
  `cli.py`'s `click.echo("✅ Health check passed…")`, i.e. *after* the check has finished.
  **Do not trust the exit code here**: measured `1` on 2026-09-01 (serena 1.7.0, cp1252), so
  the traceback does propagate. The log body is the verdict, not `$?`.
- **Check *which symbol* it selected, not just that both lines appeared.** Both criteria can
  pass on a symbol that proves nothing. Run against `basic-analysis` (8 languages incl.
  `markdown`), 2026-09-01: `No class or function found, using first available symbol` →
  `AGENTS.md — basic-analysis`, kind **Namespace** — a markdown heading. It then reported
  `FindReferencingSymbolsTool found 1 references` and `Health check completed successfully`
  while never touching Python at all. A pass on a heading is a pass on nothing; if the
  selected symbol is not a Function or Class, the language list is polluted (§ above) and the
  check has not exercised your call graph. Startup there: **34.4 s**.

**Worktrees and parallel agents — three rules, all non-negotiable.**

> **1. Activate by absolute path, never by a bare name.** `get_registered_project`
> (`serena/config/serena_config.py`) compares the argument against every registered
> `project_name` **before** it looks at paths, and raises `Multiple projects found` when two
> match. `.serena/project.yml` is tracked, so every linked worktree checks out a copy carrying
> the *same* `project_name` — the second worktree turns by-name activation into a hard error
> **for every agent at once**, the one in the main checkout included. An absolute path cannot
> equal a project name, so it never reaches that branch. Confirmed in
> `serena/config/serena_config.py:928-945`. Measured 2026-08-31: five `basic-analysis`
> worktrees, five registrations all named `basic-analysis`.
>
> **1b. Better still, omit `project_name` from the tracked `.serena/project.yml`.** This is a
> *configuration-level* fix, and it is stronger than the discipline rule because it holds
> however an agent activates. `serena_config.py:516-517` fills a missing key from the
> **folder name**, in memory, at load: `if "project_name" not in yaml_data: yaml_data
> ["project_name"] = project_folder_name`. The only write-back of `project_name` is
> `_migrate_out_of_project_config_file` (`serena_config.py:907-912`), which operates on a
> legacy *out-of-project* config file, not on `.serena/project.yml` — so nothing persists the
> derived name back into the tracked file. Every linked worktree then self-names by its own
> directory, and two worktrees can never present the same name.
>
> > **Caveat — verified by reading 1.7.0 source, not by running a second worktree.** Treat it
> > as an addition to the absolute-path rule, never a replacement, until someone tests it
> > live. `~/.serena/serena_config.yml` on this machine still registers five `basic-analysis`
> > worktrees all named `basic-analysis`, so that repo is the obvious place to test it.
>
> **2. One Serena = one session = one worktree.** Serena is a *single stdio process per Claude
> Code session* holding exactly one `_active_project`, and `_activate_project` (`serena/agent.py`)
> **shuts the previous project's language servers down** before switching. In-session subagents
> share that one process, so N agents in N worktrees means every activation kills the previous
> agent's LSP mid-flight and whoever activated last silently owns everyone's symbol results.
> This is process architecture, not policy — no configuration fixes it.
>
> **The consequence is NOT that worktree agents lose Serena.** That conclusion was drawn here
> once and it was wrong: trading symbolic navigation for `grep` is a large, permanent cost paid
> to avoid a solvable problem. The real consequence is about *which unit* you put in a worktree.
>
> **The unit of worktree parallelism is a SESSION, not a subagent.** One `claude` process per
> worktree gives each its own Serena process, its own `_active_project`, and — because graphify
> is cwd-relative — its own graph. Nothing is shared, nothing is torn down, and every agent has
> full symbolic navigation. In-session subagents then stay in *their own session's* worktree,
> where they share one correctly-activated Serena and everything works. So: **worktrees get
> sessions; subagents share the session's worktree.** (`skills/herdr-orchestration/SKILL.md`
> panes are how you run one session per worktree.)
>
> Three things must be true for a worktree session to come up at full capability. All three are
> the same failure — an artifact that is untracked, so the worktree never receives it:
>
> | Requirement | Why it bites | Fix |
> |---|---|---|
> | `.serena/project.yml` is **tracked** | absent, Serena *autogenerates* it, and autogeneration picks languages by file count — reintroducing `json`/`markdown`/`yaml` in every worktree, forever | track it: `.serena/*` plus `!.serena/project.yml`, never a bare `.serena/` (a negation cannot re-include a file inside an already-excluded directory) |
> | `project_name` is **omitted** | otherwise every worktree registers the same name and by-name activation raises for all agents at once (rule 1b) | delete the key |
> | `graphify-out/` **exists** there | it is gitignored, and both hooks deliberately skip linked worktrees, so it is never created | link it to the main checkout (below) |
>
> Link graphify's output rather than building a second copy: the hooks maintain exactly one
> graph, and a hand-built one in a worktree goes stale with nothing to tell you.
>
> ```bash
> ln -s "$(git rev-parse --show-toplevel)/graphify-out" "<worktree>/graphify-out"
> ```
> ```
> cmd /c mklink /J "<worktree>\graphify-out" "<main>\graphify-out"    :: Windows, no admin needed
> ```
>
> **Verified it cannot eat the real graph** (2026-09-01): with a canary in the link target,
> `Remove-Item -Recurse -Force <worktree>` deleted the worktree and left the target intact — the
> junction is not followed. Worth checking because a recursive delete that *did* follow it would
> destroy the one maintained graph. Not tested against `git worktree remove` itself (the index
> was locked at the time), so if you want belt and braces, drop the link before removing the
> worktree.
>
> The graphify server only *reads* `graph.json`, so the link is read-only in practice and N
> sessions cannot race over it. Same pattern as `.env` and `launch.json`: **untracked operator
> artifacts resolve to the main checkout.** Accept the matching caveat — the graph describes the
> main checkout's code, which is right for structural questions ("what connects X to Y") and
> wrong for code the branch has restructured. Rebuild on the branch when that starts to matter,
> and say which one you are answering from.
>
> Only when a worktree genuinely cannot have its own session — an in-session subagent you must
> dispatch across worktrees — does the fallback apply: `Glob`/`Grep`/`Read` **and `Edit`**, said
> out loud. Name `Edit` explicitly wherever you write that down: such a subagent cannot use
> Serena *by rule*, so a fallback list omitting the one tool that changes files reads as "I
> cannot work", and a repo that also fences shell edits to source turns it into a hard stop —
> measured 2026-09-01.
>
> **Know the price: N sessions = N Serena processes, each holding its own language servers.**
> Five were alive during the 2026-09-01 measurement, and a duplicate server definition (see
> *Wiring* above) doubles the count for free. This is the real cost of parallel branch work,
> and it is why the answer to "can my subagents each have their own Serena?" is "only by
> paying for another process each".
>
> **3. A worktree holds tracked files only.** `.env`, `.venv/`, build caches and every other
> gitignored operator file are absent *by construction* — `git worktree add` materialises what
> git tracks and nothing more. Code that resolves such a file relative to its own location
> (`Path(__file__).resolve().parents[n]`) therefore finds nothing in a worktree and, if it is
> written to degrade gracefully, **degrades silently**. Resolve untracked config through the
> **main checkout**. A linked worktree's `.git` is a *file* reading
> `gitdir: <main>/.git/worktrees/<name>`, and that directory's `commondir` leads back to the
> shared `.git` — so the main root is two file reads away, with no subprocess and no
> `git`-on-PATH dependency on your import path:
>
> ```python
> def main_worktree_root(root: Path) -> Path | None:
>     """Main checkout behind `root`, or None if `root` is not a linked worktree."""
>     dot_git = root / ".git"
>     if not dot_git.is_file():        # a directory is an ordinary checkout; absent is no repo
>         return None
>     try:
>         pointer = dot_git.read_text(encoding="utf-8").strip()
>         if not pointer.startswith("gitdir:"):
>             return None
>         # split on the FIRST colon only: a Windows pointer is `gitdir: C:/...`
>         gitdir = Path(pointer.split(":", 1)[1].strip())
>         if not gitdir.is_absolute():
>             gitdir = root / gitdir
>         commondir = (gitdir / "commondir").read_text(encoding="utf-8").strip()
>     except OSError:
>         return None
>     return (gitdir / commondir).resolve().parent
> ```
>
> Search the worktree's own locations first, then the main checkout's, so a deliberate
> per-worktree override still wins. Do **not** copy credentials into each worktree instead:
> `git worktree prune` orphans those copies and they drift from the one the services read.
>
> Housekeeping: keep `.claude/worktrees/` in `.gitignore` (not just `.git/info/exclude`, which
> no clone inherits) so Serena does not index N copies of the repo, and drop registry entries
> for worktrees you have removed from `~/.serena/serena_config.yml` → `projects`.

**Note**: Serena memory tools are disabled. Use Omnigraph (structured memory) for all persistent memory instead.

### Omnigraph — Structured Cross-Project Memory

The default memory layer. Instead of unstructured blobs, write **typed** nodes
(`Decision / Rule / Preference / Convention / Component / Task`) edged to a
`Project`, and recall them via fused graph + vector + full-text queries. MCP tools:
`schema / branches / queries / mutations / ingest`.

| Action | How |
|--------|-----|
| Recall project memory | `query` for rules/decisions/preferences edged to the project |
| Persist a durable fact | `mutate` (a few nodes) or `load` `mode: merge` (bulk), on a branch, then merge |
| Global preferences | `Preference` nodes with `scope: global`, in the shared `memory` graph |

Full protocol and schema: `skills/structured-memory/SKILL.md`. **Each repo has its
own graph** named after the repo folder (`OMNIGRAPH_GRAPH_ID=<repo>`); the shared
`memory` graph holds only global-scope `Preference`s. Isolation is by graph, plus
`Project` edges inside it — never a per-call `user_id`. Omnigraph is the only memory
layer; there is no fallback (ADR 0003).

**Discovering repository / project names — token-gated, and the token *is* the access model.**

Graph id == repository folder name == `Project.slug`, by construction, so "which graphs
exist" and "which projects exist" are one question. `cluster.yaml` is **not** the answer:
it is gitignored and purged from history precisely because it had become a roster of every
private project. Ask the live cluster.

| You want | MCP tool | HTTP equivalent |
|---|---|---|
| Every repository / project name | `graphs_list` | `curl -fsS -H "Authorization: Bearer $OMNIGRAPH_TOKEN" http://localhost:8080/graphs` |
| This repo's own record (name + clone URL) | `query whoami() { match { $p: Project } return { $p.slug, $p.name, $p.repository } }` | `POST /graphs/<id>/query` with the same header |

**A bearer token is the only key.** Measured against the live server on 2026-08-31:

| Request | Result |
|---|---|
| no `Authorization` header | **401** |
| wrong token | **401** |
| valid `OMNIGRAPH_TOKEN` | 200 |
| `GET /healthz` | 200 — the only open endpoint, and it returns liveness alone: no names, no data |

`/graphs` is closed by default. It answers at all only because the `cluster-admin` bundle
(`cluster/cluster.policy.yaml`, `applies_to: [cluster]`) grants the `graph_list` action to
the `operators` group. Without that grant the *authenticated* call returns **403
ForbiddenError** — not an empty list, so you cannot mistake "not allowed" for "nothing here".

**Scope — one token, one actor, that actor's graphs.** The token resolves to the single
actor `default` in group `operators`; `project-graphs.policy.yaml` grants it the per-project
graphs and `memory.policy.yaml` grants it `memory`. A holder therefore sees exactly the
graphs that belong to them — today that is all of them, because there is one user. **Treat
it as all-or-nothing: never hand this token to anyone whose data is not already in these
graphs.** Per-user scoping is written but switched off — `cluster/users.policy.yaml.example`
plus the commented `users-access` bundle in `cluster.yaml`. Turning it on needs one bearer
token per user and a `scripts/apply-cluster.sh` run; until then there is no way to give
someone a token that reveals only *part* of the roster.

> An unset `OMNIGRAPH_TOKEN` does **not** surface as "denied" through the MCP bridge — it
> surfaces as `missing bearer token`, and a graph that looks empty is a config bug until
> proven otherwise. Diagnose with `omnigraph-setup/setup-agent-memory.ps1 -Check` (or `.sh --check`).

### Graphify — Project Graphs

| Tool | Purpose |
|------|---------|
| `graphify query` | Ask graph-level questions about the repo |
| `graphify path` | Trace relationships between concepts |
| `graphify explain` | Inspect a node or community in graph terms |

**Usage**:
```
graphify query "what connects the CLI setup to the MCP config?"
graphify path "apply-cluster.sh" "cluster.yaml"
```

**Rule**: Graphify does not replace Serena. Use Serena for symbol-level navigation and Graphify for broader relationship questions when a graph exists.

#### Wiring — ONE definition per machine, cwd-relative

Graphify is **stdio-only** (no shared daemon) and reads a static `graphify-out/graph.json`.
A stdio server inherits its launch directory, so **one entry with the *relative* path
`graphify-out/graph.json` serves whichever repo you started Claude Code in.** Define it
**once, in user scope** — never per repo.

There is **no npx graphify**: the npm package by that name is an unrelated jQuery toy. The
tool is Python-only (`graphifyy[mcp]`, upstream `github.com/safishamsi/graphify`), served as
`python -m graphify.serve <graph.json>`.

- **Workstation / client — this is the way.** A single user-scope entry in `~/.claude.json`:
  ```jsonc
  "graphify": {
    "command": "uv",
    "args": ["run","--with","graphifyy[mcp]","python","-m","graphify.serve","graphify-out/graph.json"]
  }
  ```
  No Docker, no per-repo `.mcp.json` entry, no approval step. `uv` resolves from cache
  (~sub-second warm); a global `pipx install graphifyy[mcp]` + `"command": "python"` is an
  option if you want to shave cold-start.

- **Server** (e.g. `coding.vm` — runs graphify via Docker). MCP args aren't shell-expanded, so
  a raw entry can't inject `$PWD`; the tracked cwd wrapper
  [`infra/mcp-servers/bin/graphify-mcp`](../../infra/mcp-servers/bin/graphify-mcp) does it:
  ```sh
  exec docker run -i --rm -v "$PWD:/repo" graphify-mcp:latest "$@"
  ```
  Setup: build the image (`docker build -t graphify-mcp:latest servers/graphify-mcp`), put the
  wrapper on `PATH` (`ln -s "$PWD/infra/mcp-servers/bin/graphify-mcp" /usr/local/bin/`), then
  register the one user-scope entry `"graphify": { "command": "graphify-mcp" }`.
  If graphify reports **"Failed to connect — Connection closed"**, either the image
  isn't built or its `mcp` SDK resolved to 2.x (which dropped `mcp.types.AnyUrl`, an
  import graphify 0.9.20 makes at startup). The Dockerfile pins `mcp<2` to prevent the
  latter — rebuild the image (`docker build -t graphify-mcp:latest servers/graphify-mcp`)
  to pick up the pin.

**Never give graphify a per-repo project-scope entry.** A cwd-relative single definition
already serves each repo its own graph; a **hardcoded** per-repo mount is exactly what made
one repo's graph answer for every repo (the retired `graphify-docker`, 2026-07-20). With
graphify defined in only one place, the user-vs-project same-name precedence trap cannot
arise for it at all.

**Contrast with omnigraph — do not apply one's rule to the other.** Omnigraph *is*
per-repo/project-scoped (pinned by `OMNIGRAPH_GRAPH_ID`) because each repo is a distinct graph
on a shared server. Graphify is a local static file selected by cwd, so it needs no per-repo
pin and belongs in user scope.

**`enabledMcpjsonServers` never lists graphify — by design, not by omission.** That array
approves *project-scoped* servers declared in a repo's `.mcp.json`; user-scope servers need no
approval because you configured them yourself. Graphify is user-scope only, so it appears in no
`.mcp.json` and there is nothing to approve. A graphify entry in a repo's
`.claude/settings.local.json` is therefore a **defect**, not configuration —
`scripts/{linux,windows}/check-graphify-scope.*` flags it and `--fix` removes it, deliberately
checking for it independently of the server entry, because an approval outlives the server it
approved.

**Worktrees: graphify is a main-checkout tool, and outside one it fails quietly.**
`graphify-out/` is gitignored, so — exactly like `.env` in the Serena worktree rules — a linked
worktree never has one. Two ways that bites, neither of which errors:

- **Session launched *in* the worktree.** `graphify.serve` is stdio and cwd-relative, so it
  looks for `<worktree>/graphify-out/graph.json`, which has never existed there.
- **Session launched in the main checkout while an agent works in a worktree.** A stdio server
  inherits its launch directory *once*, at start, so it keeps answering from the main
  checkout's graph — built from a different branch's code. Confident answers about the wrong
  tree.

**There is no rebuild spillover, though.** Both installed hooks refuse to run in a linked
worktree: `post-commit` and `post-checkout` each compare `git rev-parse --git-dir` against
`--git-common-dir` and `exit 0` when they differ, so N worktrees never produce N rebuilds or N
competing graphs. `post-checkout` also exits when `graphify-out/` is absent, which is always
true in a worktree. Confirmed by reading the installed hooks, 2026-09-01.

So the rule matches Serena's: **in a worktree, treat graphify as unavailable and say so** — the
escape hatch that is not silent. Do **not** hand-build a graph inside a worktree to work around
it; the hooks will not maintain it, so it goes stale with nothing to tell you.

Only the graph **file** is per-repo. Build it (no LLM/API key needed) and keep it fresh:
```bash
uv run --with graphifyy[mcp] graphify update .   # workstation; or init-graphify-projects.*
# server without uv:
docker run --rm -v "$PWD:/repo" -w /repo --entrypoint python graphify-mcp:latest -m graphify update .
```

Verify wiring — single user-scope entry present, **no** project graphify entries, graph built
(`--fix`/`-Fix` applies the safe repairs; both exit non-zero so they work in hooks/CI):
```bash
bash infra/mcp-servers/scripts/linux/check-graphify-scope.sh --fix          # Linux/WSL
```
```powershell
.\infra\mcp-servers\scripts\windows\check-graphify-scope.ps1 -Fix           # Windows
```

### Superpowers — Workflow Skills (14 skills)

| Skill | When to Use |
|-------|------------|
| `systematic-debugging` | Any bug, test failure, unexpected behavior |
| `test-driven-development` | Before writing implementation code |
| `brainstorming` | Before creative work, features, design |
| `writing-plans` | Multi-step tasks with specs |
| `requesting-code-review` | Before merging |
| `subagent-driven-development` | Independent parallel tasks |
| `verification-before-completion` | Before claiming work is done |

**Usage**:
```
mcp_superpowers_use_skill(name="systematic-debugging")
mcp_superpowers_recommend_skills(task="debug a timeout issue")
```

### Playwright — Browser Automation (UI validation, E2E)

Strictly for UI validation, screenshot testing, and E2E browser tasks against sites
you build — **not** a web-search tool. Exposes 24 tools (`browser_navigate`,
`browser_snapshot`, `browser_click`, `browser_take_screenshot`,
`browser_console_messages`, `browser_network_requests`, `browser_fill_form`, …);
screenshots return inline in the tool response, so no output volume is needed.

#### Wiring — ONE user-scope Docker entry, serves every repo

There is **no node/npx on the server** (`coding.vm`), so the usual
`npx @playwright/mcp` transport can't run. Use Microsoft's official image over
Docker instead, defined **once in user scope** (like graphify) so it works from any
repo Claude Code launches in — no per-repo `.mcp.json` entry, no approval step:

```bash
docker pull mcr.microsoft.com/playwright/mcp:latest
claude mcp add -s user playwright -- \
  docker run -i --rm --init --network host mcr.microsoft.com/playwright/mcp:latest
```

- **`--network host`** (Linux) lets the containerized browser reach dev servers on
  the host's `localhost:PORT`, so an agent tests the site it just built with the URL
  it would naturally type. Trade-off: less network isolation; fine on a single-user
  dev host. Portable alternative: `--add-host=host.docker.internal:host-gateway` and
  browse `http://host.docker.internal:PORT`.
- **`--rm`** → ephemeral browser profile per run; **`--init`** reaps zombie browser
  processes.

Verify — authoritative client health check, then a real browser drive:
```bash
claude mcp list                       # → playwright … ✔ Connected
# functional: initialize → tools/call browser_navigate https://example.com → snapshot
```

> **Restart to load it.** MCP servers initialize only at session start, so a running
> session won't see a newly-added `playwright` until it restarts.

## Infrastructure

| Service | Address | Model(s) | Purpose |
|---------|---------|----------|---------|
| omnigraph-server | `:8080` | — | The memory graph (bearer-auth; `/healthz` is open) |
| MinIO | `:9000` API / `:9001` console | — | S3 store backing Omnigraph |
| omnigraph-viewer | `:8090` | — | Read-only web UI (put Authelia in front if exposed) |
| Ollama | `:11434` | `nomic-embed-text` (768-dim, CPU-fine) | Embeddings — **optional** |
| OLLAMA_KEEP_ALIVE=24h | Windows env | — | Keep models in VRAM |

Ollama is optional: without it, recall degrades to graph traversal + full-text rather
than failing. **No Qdrant, no Postgres, no LLM API key** — those were Mem0's, and Mem0
was removed entirely (ADR 0003). `bge-m3` (1024-dim) was Mem0's embedder and is *not*
this graph's: the graph is `Vector(768)`/`nomic-embed-text`, and mixing dimensions makes
`nearest()` return garbage.

### Harbor — Private Container Registry

**Convention: any container image an agent builds to share or deploy goes to
Harbor, never Docker Hub.** Harbor is the homelab registry (web UI, per-project
RBAC/robot accounts, Trivy scanning) at `harbor.ohje.ooguy.com`, backed by the
NFS share on cloud.vm. Local-only throwaway builds (e.g. `docker compose --build`
for a stack that runs in place) do **not** need pushing — only images meant to be
pulled elsewhere.

```bash
# build locally, then publish to Harbor under a project namespace (create the
# project once in the UI: e.g. `agents`, `infra`)
docker build -t myimage:latest .
docker login harbor.ohje.ooguy.com                       # admin / project user / robot token
docker tag  myimage:latest harbor.ohje.ooguy.com/agents/myimage:latest
docker push harbor.ohje.ooguy.com/agents/myimage:latest
# elsewhere: pull instead of rebuilding
docker pull harbor.ohje.ooguy.com/agents/myimage:latest
```

Deployment / admin (installer, storage path, Caddy exposure, secrets) is the
single source of truth in the Server repo: `server/cloud/harbor/README.md`.

## Project Initialization

> ⚠️ **On coding.vm the Omnigraph stack is already deployed from
> `Server/server/coding/mcp-servers/docker-compose.yml`** (canonical, Dockhand,
> viewer bound to `0.0.0.0:8090` for Caddy). The compose below is a **local/dev**
> variant — it binds `127.0.0.1` and shares the project name `mcp-servers`, so
> running it on coding.vm clobbers the live viewer and takes
> `omnigraph-ui.ohje.ooguy.com` down. On coding.vm, manage the stack from the
> canonical Server compose instead. Use the below only for a standalone/dev host.

```bash
cd ${AGENT_SKILLS_ROOT}/infra/mcp-servers
docker compose --env-file .env.shared --env-file .env.server -f docker-compose.server.yml up -d
curl -fsS http://localhost:8080/healthz                  # server up
python3 scripts/_omni_env.py                             # what stack docker actually has
```

## Recommended Workflow

1. Start the server: `docker compose --env-file .env.shared --env-file .env.server -f docker-compose.server.yml up -d`
2. Activate Serena project: `mcp_serena_activate_project(project="<absolute path to the repo>")`
3. Recall memory from Omnigraph (see `skills/structured-memory/SKILL.md`)
4. Build or refresh Graphify graphs when the repo has a graph target
5. Use Serena for navigation, Omnigraph for memory, Graphify for graph queries, and Superpowers for workflows
6. End session: persist durable decisions to Omnigraph; services keep running

## Troubleshooting

```powershell
# Full health check
curl -fsS http://localhost:8080/healthz                  # omnigraph server
curl -fsS -H "Authorization: Bearer $env:OMNIGRAPH_TOKEN" http://localhost:8080/graphs

# Serena
serena project list
serena --version

# Omnigraph (open health probe, then an authenticated call)
curl -fsS http://localhost:8080/healthz
curl -fsS -H "Authorization: Bearer $env:OMNIGRAPH_TOKEN" http://localhost:8080/graphs

# Ollama (optional — embeddings only)
curl http://localhost:11434/api/tags
```

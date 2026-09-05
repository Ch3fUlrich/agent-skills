---
name: unattended-orchestration
description: A portable runner that drives agent sessions unattended for hours or overnight — background sessions in isolated git worktrees, in parallel lanes, surviving usage limits, API outages and early stops, then guard-tested and auto-merged. Copy the folder into any git repository and run -Init; the repo is auto-detected and the agent is a swappable adapter. Load when work must continue with nobody watching, or when adopting unattended orchestration into a repository.
---

# Unattended Orchestration

Long-horizon agent work with **no human present**: an overnight batch, a weekend migration, a
queue of handoffs too large for one sitting. The runner starts each session, watches it, and
recovers it — through the usage limit, a 529, and a session that stops early.

Adopted from `basic-analysis`'s wave-3 runner (2026-09-04) and generalised; see
ADR 0006 in that repository for why it is config-driven.

## Adopting this skill in another repository

**Copy this folder in and run it. Nothing here is specific to the repo it came from.**

```bash
cp -r skills/unattended-orchestration <your-repo>/skills/     # or anywhere you like
cd <your-repo>
pwsh -File skills/unattended-orchestration/run_handoff_sessions.ps1 -Init
```

`-Init` writes `.claude/handoff.config.json`, detecting your git root and your **actual** base
branch. Then edit the sessions, and:

```bash
… -Validate      # repo, branch, lanes, guards, launcher — check before trusting it to a night
… -EmitBriefs    # read the briefs as markdown; launches nothing
… -DryRun        # rehearse preflight and lane dispatch; starts no session
…                # run it
```

Four properties make that work, and each is covered by
[`tests/Portability.Tests.ps1`](tests/Portability.Tests.ps1), which copies the skill into a
throwaway repository and drives the whole path there unedited:

| Property | Why it matters for adoption |
|---|---|
| **The repository is detected**, not configured (`git rev-parse --show-toplevel`) | A committed config carries no machine-specific path, so it works for everyone who clones it. `repo` remains available as an override. |
| **The session tool is an adapter** (`launcher`) | The default describes Claude Code, so an unedited config just runs. A repo driving a different agent replaces only the keys it needs — the block merges key-by-key, so overriding `command` does not silently lose `list`/`logs`/`stop`. |
| **Cross-platform primitives** | Junction on Windows, symlink elsewhere; named mutex on Windows, exclusive lock file elsewhere. A named `System.Threading.Mutex` throws `PlatformNotSupportedException` off Windows, which would kill the first state write. |
| **Guards, subagents and briefs are opt-in** | An unconfigured repo gets a runner that works, not one that assumes pytest, a venv, or a delegation policy. |

The one hard requirement is **PowerShell 7** (`pwsh`), which runs on Windows, Linux and macOS.

**A worktree holds tracked files only.** Everything a session needs that git does not carry has
to be created *per worktree*, in `postWorktree`, or it is silently absent — and "silently" is
the word: a venv whose editable install points at the main checkout imports the **main
checkout's** package from inside the worktree, a cwd-relative code-graph server answers from a
graph that was never built there, a memory tool registers every worktree under one name. The
checklist, all measured while adopting this skill into a second repository (2026-09-05):

| the worktree lacks | what happens if you ignore it | fix, per worktree |
|---|---|---|
| a venv | `python` from the main checkout's venv resolves `import <package>` to the main checkout's `src` (editable `.pth`), so the session tests code it did not write | `postWorktree`: `uv sync --frozen` (24 s with a warm cache); guards and briefs use `{{worktree}}/.venv` |
| the code graph (`graphify-out/`, gitignored) | the cwd-relative MCP server finds nothing, or a junction shares ONE graph that any session's rebuild overwrites for all | build it in `postWorktree` (27 s, no API key) — or `copyDirs` for a snapshot each session may rebuild |
| the gitignored working ledger / SDD workspace | the brief points at files that do not exist | `copyDirs` |
| trust in `~/.claude.json` and MCP approval in `.claude/settings.local.json` | the first tool call blocks on a dialog nobody answers — and the `~/.claude.json` entry alone does **not** suppress the "New MCP server found" dialog (measured: three lanes blocked in three seconds) | `postWorktree`: the bundled `{{skillDir}}/trust_worktree.py --mcpjson <name>`, which writes the worktree's `settings.local.json` with `enableAllProjectMcpServers`; keep that file gitignored |
| a unique memory-tool project name | Serena's tracked `project.yml` names every worktree the same; by-name activation raises for all of them | drop `project_name` from `project.yml` (each worktree self-names by folder) and activate by absolute path |
| the gitignored `.env` (secrets, switches) | the worktree app generates fresh secrets, so archives encrypted by the main checkout cannot be read there - or a fresh key silently becomes the live one | `copyFiles: [".env"]` |
| the live data directory, wanted by ONE lane | every worktree that links it lets a suite run reach real data; every worktree that lacks it makes the data session move nothing and report success | per-session `linkDirs` on exactly the sessions that own the move, nothing global (measured 2026-09-05, gen-analysis: a tracked placeholder would also have pre-empted the link, so keep `data/` untracked) |
| an untracked prior-art drop one lane reads | the port session finds an empty folder and ports from memory | per-session `linkDirs` for that lane only |

## 0. Where each fact lives — read this before editing anything

This file is **normative policy**. It holds no paths, models, timeouts or test commands.

| Fact | Single owner |
|---|---|
| Sessions, models, briefs, lanes | your repo's `handoff.config.json` → `sessions`, `lanes` |
| Subagent tiers, concurrency cap, leaf rule | same file → `subagents` |
| Timeouts, retry and continue caps, poll interval | same file (defaults: `HandoffCore.psm1` → `$HandoffDefaults`) |
| Guard command and its paths | same file → `guards` |
| Tool allowlist, permission mode | same file → `allowedTools`, `permissionMode` |
| Which agent to drive, and how | same file → `launcher` (defaults to Claude Code) |
| Branch, worktree and state locations | same file → `baseBranch`, `branchPrefix`, `worktree*`, `stateDir` |
| Shared vs per-session artifacts | same file → `linkDirs` (one shared copy) / `copyDirs` (one per worktree) / `copyFiles` (single gitignored files, e.g. `.env`); a session adds its own under `sessions.<key>.linkDirs|copyDirs|copyFiles`, merged after the global lists |
| Cross-lane ordering | same file → each session's `dependsOn`; `maxDependencyHours` |
| When a quiet session counts as finished; whether it is stopped after merging; whether its worktree goes | same file → `quietMinutes`, `stopAfterMerge`, `removeWorktreeAfterMerge` |
| Mutual exclusion between running sessions | same file → each session's `resources` |
| The final, pinned test run | same file → a session with `guardsOnly: true` and `dependsOn` the rest |
| The machine budget briefs defer under | same file → `machineBudget`, rendered as `{{machineBudget}}`; `<stateDir>/load.json` |
| The controller's own brief | same file → `controllerBrief` / `controllerBriefFile` |
| Traps every brief must carry | same file → `traps`, rendered as `{{traps}}` |
| The skill's own folder, for bundled helpers | `{{skillDir}}` (set by the runner) → `trust_worktree.py` |
| Shared brief preamble | same file → `briefTemplate` / `briefTemplateFile` |
| Every annotated field | [`handoff.config.example.json`](handoff.config.example.json) |
| Failure→recovery rules, config validation | [`HandoffCore.psm1`](HandoffCore.psm1) (tested) |
| Orchestration itself | [`run_handoff_sessions.ps1`](run_handoff_sessions.ps1) |

If you find a model name, a timeout or a test path in *this* file, that is a bug — replace it
with a pointer.

## 1. When this, and when something else

```mermaid
flowchart TD
    A[Parallel or background agent work] --> B{Is a human present<br/>for the whole run?}
    B -- yes --> C{Finishes inside<br/>one conversation?}
    C -- yes --> D[Agent / Workflow tools<br/>see swarm-orchestration]
    C -- no --> E[herdr-orchestration<br/>supervised, persistent panes]
    B -- no --> F{Hours or overnight,<br/>must survive usage limits?}
    F -- no --> D
    F -- yes --> G[THIS SKILL]
```

The distinction that matters is **who recovers a stopped session**. In-session tooling assumes
you are there; Herdr assumes you can look at a pane. This runner assumes nobody will look until
morning, so every stop must be classified and recovered automatically — or recorded in a state
file precisely enough to be understood cold.

**Do not use it** for work that fits in one sitting. The worktree, guard and merge machinery is
only worth its cost when the alternative is losing a night.

## 2. The model

**Lanes run in parallel; sessions inside a lane run in sequence.** That is the only scheduling
primitive, and it is enough: put sessions that contend for a resource — a database, a store, a
generated artifact — in the *same* lane, and independent ones in different lanes.

Each session gets its **own git worktree on its own branch**, cut from the current base branch.
Isolation is per *session*, not per subagent — see the worktree rules in
the `mcp-servers-setup` skill; a session per worktree is what gives each
one its own Serena process and its own graph.

```mermaid
flowchart LR
    subgraph L1["lane 1 — sequential"]
        E[session E] --> A[session A]
    end
    subgraph L2["lane 2 — sequential"]
        D[session D] --> B[session B]
    end
    L1 & L2 --> G{guards}
    G -- green --> M[["merge --no-ff<br/>under a global mutex"]]
    G -- red --> S[lane stops<br/>branch left for review]
```

Per session: create worktree → start background session with its brief → poll until the turn
ends → classify → recover or continue → run guards → merge. A red guard or a merge conflict
stops **that lane only**; other lanes keep running.

**Exclusion across lanes is `resources`.** Ordering is not exclusion: a read-only session can
starve a writer on a single-holder store while the lanes say nothing is wrong. Each session lists
what it *holds* while running (`"store:write"`, `"store:read"`, a bare name meaning write); the
runner refuses to start a session whose resources conflict with a running one — write excludes
everything on that name, read excludes only write — and says so in the state file.

**Ordering across lanes is `dependsOn`.** A session listing dependencies waits — before its
worktree is cut — until each has *merged*, so it forks from a base branch that already carries
their work; a dependency that ends without merging fails the dependent instead of leaving it
polling until morning. That is what lets one invocation run "B, T11 and T6 in parallel, then C
after all three, then D" without an operator returning to start the second half.

```mermaid
flowchart LR
    B[B] --> C
    T11[T11] --> C
    T6[T6] --> C[C — dependsOn B, T11, T6]
    C --> D[D — same lane, sequential]
```

## 3. Recovery — the part that earns the skill

Every turn that ends is classified from the session log, and the kind decides the response:

| Kind | Response | Why |
|---|---|---|
| `auth` | **stop the lane immediately** | An expired login fails every launch instantly. Retrying burns the whole night for nothing. |
| `limit` | sleep until the reset epoch Claude reports, else a flat wait, then **resume the same session** | The message carries the exact reset time; waiting blind wastes hours. |
| `transient` | short wait, then resume | 500/529/network are self-clearing. |
| `other` + no DONE note | resume with a nudge, up to the continue cap | A session that stopped early has committed work; resuming continues from it. |
| operator's `stop-<key>` marker in `<stateDir>/queue` | **stop the lane at its next decision point** — with a DONE note present, go to the guards; without one, stop | A finished lane used to be killable only with `Stop-Process` on its poller. |
| branch already an ancestor of the base branch (merged by hand or by another runner) | mark `merged`, `finished_by: merged-elsewhere`, skip | Two runners over one state file, or an orchestrator merging by hand, must not re-run a session whose work is already in. |
| DONE note present, branch clean and quiet for `quietMinutes` | **finished** — stop the session, run the guards, merge — even while the agents view still says "working" | Measured twice in one day: a finished session reported `working` for three hours, hit the session-hours cap, and was stopped and *resumed* — a fresh session that read the brief, found the work done, and idled. The evidence of completion is the DONE note, not the turn. |
| permission prompt | **`blocked`**, lane stops | A background session cannot answer. It would sit there until morning. |

The exact patterns and waits live in `Classify-HandoffFailure`; they are covered by
[`tests/HandoffCore.Tests.ps1`](tests/HandoffCore.Tests.ps1), because the alternative way to
test them is to actually hit a usage limit at 03:00.

**Resume, never restart.** The runner keeps one live session per handoff: it stops the finished
one before resuming, so retries never accumulate background sessions holding the same
conversation. Nothing a session committed is ever lost.

## 4. Three layers of orchestration

An unattended run is three levels deep, and each level has a different job. Collapsing them —
one giant session doing everything itself — is the failure this section exists to prevent.

```mermaid
flowchart TD
    O["ORCHESTRATOR<br/>the runner (or a session driving it)"] -->|"claude --bg --remote-control"| S1["SESSION S2<br/>opus · own worktree"]
    O --> S2["SESSION S1<br/>sonnet · own worktree"]
    S1 -->|Agent tool| A1["subagent<br/>sonnet · mechanical"]
    S1 --> A2["subagent<br/>opus · judgement"]
    A1 -.->|leaf rule:<br/>no further spawning| X[" "]
    style X fill:none,stroke:none
```

| Layer | Owns | Never does |
|---|---|---|
| **Orchestrator** | worktrees, launch, recovery, guards, merge | the work itself |
| **Session** | one handoff, start to DONE note; delegates to subagents | merge to the base branch |
| **Subagent** | one scoped task with an explicit return contract | spawn further subagents (*leaf rule*) |

**Sessions stay joinable.** Each launches with a stable `--remote-control` name, so an
"unattended" run is interactive on demand — `claude attach handoff-S2` joins it and lets you
type; `claude logs handoff-S2` reads its output without joining. That name is derived in
`Get-HandoffSessionVars` and printed in the runner log, the state file, and every emitted brief.

**The runner is controllable while it runs.** `<stateDir>/queue/lane-<name>.json`
(`{"sessions": ["F9"]}`) starts another lane child, which re-reads the config — so a session added
to the config after the start is launchable without a second runner over the same state file;
an empty `stop-<key>` file stops that session's lane at its next decision point.
`<stateDir>/load.json` (cpu %, running sessions, refreshed every poll) is what a brief under a
`machineBudget` reads before a heavy run — the budget is *advisory* on purpose: a runner that
blocked lanes on CPU would deadlock behind another project's compute pass. `-Cleanup` stops every
merged session's process, removes its worktree and branch, and prunes its Serena project row.

**The final suite is a lane, never the main checkout.** A `guardsOnly` session with `dependsOn`
every other session cuts a worktree at the merged HEAD and runs the guards there; nothing else
runs the full suite. Measured 2026-09-04: a suite started from the main checkout while five
merges fast-forwarded under it reported 18 red, of which 9 were artefacts of the moving tree.

**The orchestrator may itself be an agent session.** A controller session that launched the
runner in the background watches `<stateDir>/state.json` and `runner.log`, reads each DONE note
as it lands, and adjudicates — it never edits the worktrees. What it cannot do is *answer* a
prompt inside a background session (there is no non-interactive `attach`), which is why
`postWorktree` pre-approval and the refusal rule below matter more, not less, when the operator
is an agent.

**A successor brief is written from the predecessor's DONE note.** Eight re-cuts in one day
converged on the same six blocks, and the sessions that received them lost no time orienting:

```
# Session <N> — <one line: what this pass is>
*Read <previous DONE note> in full first — above all <the one finding it must not re-learn>.*
## Start            worktree + venv/graph check + commit flags + refusal rule
## What is true now measured facts with the session that measured them; what other lanes own RIGHT NOW
## The work, in order   numbered; each item names the guard it ships with (pass AND fire)
## Not yours — write it down, do not do it   the operator's items, other lanes' files, the changelog
## Done means       DONE note contents: commits, remains, refusals verbatim, fallbacks
```

The "what other lanes own right now" line is the one that prevents conflicts. Render the
controller's own brief the same way (`controllerBriefFile`, shown first by `-EmitBriefs`), so a
controller session can be restarted from the same source of truth as its lanes.

**Cross-session memory goes through the memory graph, not through files.** Parallel sessions
each own a worktree copy of every tracked file, so a shared ledger, a shared RESUME note or a
shared changelog section edited by two sessions is a merge conflict waiting for the runner.
Give parallel sessions their own ledger/memory/changelog-fragment files and let the sequential
tail fold them in; put the durable decisions in the structured memory graph, which every session
reads at start.

**Subagent policy is stated once.** The `subagents` block renders into every brief as
`{{subagentPolicy}}`, so all sessions delegate the same way. It is opt-in: a session told to
delegate with no cap and no tier assignment delegates badly. The leaf rule mirrors
the `swarm-orchestration` skill - without it a wave fans out
geometrically and the budget is gone before the work is.

## 5. Choosing a model per session

Route by the **shape** of the work, not its importance. The question that decides the tier is
whether a wrong answer is *visible*: mechanical work fails loudly and cheaply, judgement work
fails quietly and is discovered much later.

| Work shape | Tier | Why |
|---|---|---|
| Pattern-matching an established convention; closed-file edits; scaffolding; renames; doc sweeps | cheaper tier | Structurally verifiable. A guard or a diff catches it immediately. |
| Config with repo-wide blast radius; anything where the recovery is "revert and re-verify" | top tier | Needs the discipline to verify through the real path and back out rather than push through. |
| Deciding what survives a refactor; reconciling two designs; ambiguous requirements | top tier | Fails silently. Nothing goes red when judgement is wrong. |
| Work whose output another session depends on | top tier | Its errors are inherited, not contained. |

Put the chosen model in each session's `model`, and the subagent tiers in `subagents.tiers`.
Neither belongs in this file.

## 6. Flags beyond the adoption path

The four-step path is in *Adopting this skill* above. Beyond it:

| Flag | Effect |
|---|---|
| `-Sessions X,Y` | run just these, as one sequential lane, ignoring configured lanes |
| `-Lanes "X,Y;Z"` | override the configured lanes for this run — one string, `;` between lanes, so it survives `pwsh -File` and `Start-Process`, which flatten an array argument into positional tokens (measured 2026-09-05: `-Lanes 'A' 'L' 'D' 'FINAL'` through Start-Process bound `L` to `-Sessions` and `FINAL` to `-WaitUntil`) |
| `-Fresh` | ignore recorded state; re-run sessions already marked merged |
| `-NoMerge` | stop after the guards; leave branches for review |
| `-WaitUntil "yyyy-MM-dd HH:mm"` | sleep, then start |
| `-FollowUp "…" -FollowUpSessions X` | also schedule a detached second run, so one invocation covers a night *and* a morning |
| `-OutFile <path>` | with `-EmitBriefs`, write instead of printing |
| `-Init -Force` | overwrite an existing config |
| `-Cleanup` | stop, remove and prune every merged session's process, worktree, branch and Serena row |
| `-Status` | print every session's state from `state.json` as one table (status, finished_by, refusals, last error) |

**`-EmitBriefs` is the manual path.** It renders each session as a `### Session` block — model,
branch, worktree, attach command, then the brief in a fenced block — and launches nothing, so one
config serves both an unattended run and a human pasting into interactive sessions. Both call the
same `Build-HandoffBrief`, so pasted text cannot drift from what would have launched; that is the
whole point, and it makes the emitted markdown **generated** — edit the config and re-emit, never
the file. Use it for a session whose blast radius wants a human watching.

Follow a running session with the launcher's own commands (`claude attach <id>`,
`claude logs <id>` by default). Both ids are recorded in `state.json` and the runner log.

## 7. Rules

1. **Validate before every unattended run.** `-Validate` then `-DryRun`. A lane naming a session
   that does not exist used to fail four hours in, inside a detached child whose stdout nobody
   was reading.
2. **Never put secrets in the config** — it is meant to be committed. Tokens are read from
   `envFrom` at preflight and exported to the children; they are never copied into a worktree.
3. **Guards are opt-in, and they gate the merge.** With no `guards` block the runner merges on a
   clean stop alone. Declare them for anything that touches shared state.
4. **A refusal is a signal, not an obstacle.** Sessions run under the auto-mode classifier. The
   brief must tell them to record a refusal in the DONE note and carry on — never to work around
   it. This is the single most important line in `briefTemplate`.
5. **Pre-approve the worktree** via `postWorktree`. A fresh worktree is an unapproved folder; the
   first session in it asks to trust the directory, and a background session cannot answer.
   The skill ships the helper: `'{{skillDir}}/trust_worktree.py' '{{worktree}}' --repo '{{repo}}'`
   (`--mcpjson <name>` also enables a `.mcp.json` server for the worktree).
6. **Keep the machine awake.** The runner cannot change power settings.
7. **Never run a long suite in the main checkout while lanes merge into it.** Modules import
   before a merge and tests collect after it; the reds are artefacts. Use a `guardsOnly` lane.
8. **The tool allowlist must match how your MCP servers are wired.** A user-scope server is
   `mcp__<name>__*`; the same server as a plugin is `mcp__plugin_<plugin>_<server>__*`. Wrong
   prefix = the session silently lacks the tool. See
   `mcp-servers-setup`.

## 8. Changing the runner

Tests are the contract, and both suites must stay green:

```bash
pwsh -File skills/unattended-orchestration/tests/HandoffCore.Tests.ps1   # pure logic
pwsh -File skills/unattended-orchestration/tests/Runner.Smoke.Tests.ps1  # the driver, via -Validate/-DryRun
```

Proposals that came out of real runs but are not built yet — lane control while running,
resource exclusion beyond ordering, a machine-wide compute budget, post-merge worktree cleanup —
are collected in
[`PROPOSALS-2026-09-05-from-the-basic-analysis-orchestrator.md`](PROPOSALS-2026-09-05-from-the-basic-analysis-orchestrator.md),
each with the incident that motivates it. Read it before inventing a feature; the incident may
already be there.

Put anything that is a function of its arguments in `HandoffCore.psm1` so it can be tested
without an overnight run; the driver keeps only what genuinely touches git, `claude` or the
clock. Both bugs found on this runner's first real invocation lived in the driver and were
invisible to the unit tests — which is why the smoke suite invokes the script itself.

> **PowerShell array trap, twice over.** The output stream unrolls one array level. Both a
> `ForEach-Object` over nested arrays and an `if`/`else` **expression** assigned to a variable
> collapsed `[["E","A"]]` into `["E","A"]`, turning one sequential lane into two parallel ones —
> silently, and exactly against the contention lanes exist to prevent. Build nested arrays with
> an explicit loop and `+= ,`, and return them with a leading comma.

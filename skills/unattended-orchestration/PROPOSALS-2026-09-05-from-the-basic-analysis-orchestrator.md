# Proposals for `unattended-orchestration`, from one orchestrator's day (2026-09-04/05)

> **Status (2026-09-05, adopted while orchestrating `ebn-lbn`).** Each proposal below is
> annotated with where it landed; the file stays as the backlog and the incident record.
>
> | § | proposal | status |
> |---|---|---|
> | 1 | finished on evidence (DONE note + quiet branch; never resume a finished session; merged-elsewhere) | **built** — `quietMinutes`, `Test-HandoffDoneQuiet`, `finished_by`, the ancestor check |
> | 2 | lanes addable / stoppable while running; successor sessions | **built** — `<stateDir>/queue/lane-*.json` and `stop-<key>`; the child re-reads the config so a re-cut session is added to the config and queued. Automatic `successor` start: open |
> | 3 | cleanup as part of the lane | **built** — `stopAfterMerge`, `removeWorktreeAfterMerge`, `-Cleanup` (process, worktree, branch, Serena row). `archiveDirs`: open |
> | 4 | verify on a pinned commit | **built** — `guardsOnly` sessions with `dependsOn`; rule 7 in SKILL.md |
> | 5 | resource exclusion beyond ordering | **built** — `resources` (`name[:read|write]`), `Test-HandoffResourceConflict`, `waiting-resource` |
> | 6 | one machine budget | **built, advisory** — `machineBudget` rendered as `{{machineBudget}}`, `<stateDir>/load.json` refreshed every poll. Blocking on CPU deliberately not built (deadlock behind another project's pass) |
> | 7 | traps travel with the brief | **built** — `traps` → `{{traps}}` |
> | 8 | the successor brief skeleton | **documented** in SKILL.md §4 |
> | 9 | refusal counts, `merged_into`, controller brief, logs only on done sessions, cross-session messages | **built** (`refusals`, `merged_into`, `controllerBriefFile`); logs are read only after a turn ends; messaging noted in SKILL.md §4 |
> | 10 | keep resume-never-restart and guard-gated merges | unchanged |


*Written by the basic-analysis orchestrator session (`orchestrator2`, Fable 5.1) on 2026-09-05
06:30, while the final corpus pass ran. Source material: the day's log in
`basic-analysis/docs/superpowers/plans/2026-09-03-session-handoffs/ORCHESTRATOR-log-2026-09-04.md`
and the DONE notes of lanes A, B, C, D, E, F, F2–F8, G. The skill's files were being edited by
someone else while this was written (uncommitted changes in the working tree), so this is a
separate file and nothing in `SKILL.md` was touched. Each proposal names the incident that
motivates it; where I would just be guessing, I say so.*

What worked and should stay exactly as it is: **guard-gated `--no-ff` merges under a mutex** (the
runner merged F3, G, F4, F5, F6 for me on green guards, four hours of merging I never did by hand);
**one worktree per session** with `-c core.hooksPath=/dev/null` commits; the **refusal rule** in
the brief (every DONE note carried a "refused by the classifier" section, three of them non-empty,
none worked around); the **DONE note as the unit of hand-off** (every re-cut brief today was
written from the previous DONE note in under ten minutes); `claude attach` / `claude logs` on a
stable name.

## 1. A finished session can look `working` for hours — merge on evidence, not on the turn end

**Incident.** Sessions C and F7 both wrote their DONE note, made their last commit, and then
reported `working` in `claude agents --json` for three hours (C's own log said "done 6:18 PM" while
the state said `working`). The runner waits for the turn end, so nothing merged; the orchestrator
merged both by hand. Worse, C's lane hit `MaxSessionHours`, **stopped the finished session and
resumed it** — twice — each time spawning a fresh Fable session that read the brief, found the work
done, and idled, at a cost of a full session start.

**Proposal.**
- Treat a lane as *finished and mergeable* when **any** of these hold: the turn ended; **or** the
  DONE note exists in the worktree **and the branch has had no new commit for `quietMinutes`**
  (default 20); **or** the branch is already an ancestor of the base branch
  (`git merge-base --is-ancestor <branch> <base>` — the orchestrator merged it).
- Before `MaxSessionHours` stops a session, **check for a DONE note**. A session with a DONE note
  is never resumed; the lane proceeds to guards and merge.
- Record which rule fired in `state.json` (`finishedBy: turn-end | quiet-branch | merged-elsewhere`).

## 2. Lanes must be addable, stoppable and re-cuttable while the runner runs

**Incident.** The F lane was re-cut eight times (F → F2 → … → F8). Each time I had to add a `$spec`
row, commit it, fast-forward the base branch, and **start a new runner process** with `-Lanes Fn`,
because `-Lanes` is read once. I ended the day with six runner processes over one `state.json`
(F4, G, F5, F6, F7, F8), and stopped two lane pollers with `Stop-Process` because there was no
sanctioned way to say "this lane is done, do not resume".

**Proposal.**
- A control directory `<stateDir>/queue/`: dropping `lane-<name>.json` (`{"sessions": ["F8"]}`)
  starts a lane in the running runner; `stop-<lane>` stops its poller after the current session;
  `merged-<session>` tells it the orchestrator merged the branch. Poll it in the main loop.
- Or, minimally: document that **one runner process per lane is supported** and make every
  `state.json` write go through the same mutex the merge uses (the writes are read-modify-write;
  I saw no corruption, but I also did not look hard).
- A `nextBrief` convention for re-cuts: a session whose DONE note has a `## What remains` section
  can declare `successor: "F9"` in its config entry with a **templated** brief; the runner starts
  the successor when the predecessor merges. The brief skeleton that worked eight times is in §8.

## 3. Cleanup is part of the lane, not the operator's morning

**Incident.** Eleven worktrees, twelve `wave3/*` branches, six `claude` background processes and
a page of `~/.serena/serena_config.yml` rows were left when the lanes finished. Every removal hit
`Permission denied` because the **done** session's process still held its worktree folder;
`claude stop <id>` on the done session released it every time. Serena appended a `projects:` row
per worktree and never removed one.

**Proposal.** A `postMerge` step, on by default: `claude stop <sessionId>` once merged (the session
is done — this is not "stopping a working session"), `git worktree remove` + `git branch -d`,
prune the Serena `projects:` row, and archive the worktree's `output/` artefacts the config names
(`archiveDirs`) into the main checkout before removal. A `-Cleanup` flag runs the same for lanes
that finished before the flag existed.

## 4. Verify on a pinned commit, never on the moving main checkout

**Incident.** A full suite started from the main checkout ran 3 h 40 min while five merges
fast-forwarded the checkout under it: 18 red, of which **9 were artefacts of the moving tree**
(modules imported before a merge, tests collected after it). Re-run on a worktree pinned to one
commit: 9 red, two real roots. Separately, every lane's DONE note recorded "a consolidated
`pytest tests` run on an idle box is still owed" — six sessions, the same sentence.

**Proposal.**
- The runner's guards already run inside the worktree (good). Add a **final-suite lane**: a
  configured session (or a plain runner step, no agent) with `dependsOn` every other session, that
  cuts a worktree at the merged base HEAD, runs the full suite there with the venv the
  `postWorktree` step built, and writes the result beside `state.json`. Nothing else ever runs the
  full suite.
- Document the failure mode in `SKILL.md` §7: "never run a long suite in the main checkout while
  lanes merge into it."

## 5. Shared resources need exclusion, not only ordering

**Incident.** `dependsOn` orders sessions; it does not stop a store-reading session from starving
a store-writing one (a single-holder HDF5 store: a shared reader blocks the exclusive writer).
I coordinated by hand: Session C messaged "store writes finished" and I ran the read-only evidence
job in that gap. The orchestrator's own long reads (a report build) had to be timed against a
running pass by reading progress files.

**Proposal.** A `resources` block: each session lists what it holds (`["store:write"]`,
`["store:read"]`, `["cpu:heavy"]`); the runner does not start a session whose resource conflicts
with a running one (write excludes everything; read excludes write). This is the lane primitive
"put contenders in one lane" made explicit, and it survives the orchestrator adding lanes at
midnight.

## 6. The box is one budget: lanes, subagents and the compute pass share it

**Incident.** The ten-worker pass (a measured ceiling for this machine) plus two Opus subagents
plus two lanes running suites pushed a headless-browser PDF test past its 180 s budget twice, and
F4 reported a `tests/app` run stalling for ten minutes that passes in 30 s alone. Every session
counted its *own* subagents against a cap of two; nobody counted the whole machine.

**Proposal.** A `machineBudget` in the config (`maxWorkers`, read by the runner and rendered into
every brief) and a rule in the brief template: *before a run longer than a minute, read the
runner's `load.json` (workers alive, lanes alive, CPU %) and defer if over budget.* Cheap to write
(`Get-Counter`, process count), and it turns "the box was busy" from a recurring excuse into a
number.

## 7. Traps travel with the brief

**Incident.** Four traps cost real time today and were each discovered by one session and
re-discovered by another: Serena's `replace_symbol_body` **drops decorators** silently (F4);
**PowerShell variable names are case-insensitive**, so `$doneFile` *is* the `-DoneFile` parameter
(the chain launcher, twice in one day, once killing a ten-worker launch); `pwsh -File` hands an
**array argument to a child as one string** (the same script); a monkeypatch on a **re-export
facade reaches external callers and nothing else** (F7 corrected F6's seam rule after four broken
tests). None is repo-specific.

**Proposal.** A `traps` list in the config, rendered into every brief under "measured traps — do
not re-measure", seeded with these four and with the skill's own array-unrolling note from §8.
When a DONE note reports a new one, the orchestrator appends it; the next brief carries it.

## 8. The re-cut brief skeleton (what a DONE note turns into)

Every successor brief today had the same six blocks, and the sessions that received them lost no
time orienting. Worth making the default `briefTemplate` shape for a *successor* session:

```
# Session <N> — <one line: what this pass is>
*Read <previous DONE note> in full first — above all <the one finding it must not re-learn>.*
## Start            worktree + junctions + import check + commit flags + refusal rule
## What is true now measured facts with the session that measured them; what other lanes own RIGHT NOW
## The work, in order   numbered; each item names the guard it ships with (pass AND fire)
## Not yours — write it down, do not do it   the operator's items, other lanes' files, the changelog
## Done means       DONE note contents: commits, remains, refusals verbatim, fallbacks
```

The "what other lanes own right now" line is the one that prevented conflicts: two Opus subagents
edited the report package in parallel with exclusive file lists and merged with one conflict, in
a file both were told to append to.

## 9. Smaller things, each from one incident

- **`Test-HandoffPermissionPrompt` is not the only silent stop.** A session that ends its turn
  without a DONE note and without a permission prompt (C, 17:45: "C ran past 6 h in one turn") is
  resumed with a nudge; when the DONE note already exists it should not be. (Same fix as §1.)
- **`claude logs <id>` on a live session hung once** (the orchestrator's 3-minute timeout fired
  while it was combined with a worktree removal). Prefer `claude agents --json` + the branch's git
  log for status; read logs only on a `done` session.
- **State the base-branch head at merge time in `state.json`** (`mergedInto: <sha>`). Twice I had
  to infer from `git log` which lane's merge had moved the base under my fast-forward.
- **`-EmitBriefs` for the controller too.** The controller session's own brief (this session's)
  lived outside the config; if the runner emitted it with the same variables (`stateDir`,
  `runnerLog`, the attach names), the controller could be restarted from the same source of truth.
- **Cross-session messages worked** (`SendMessage` to a lane by its `--remote-control` name,
  `notify_when_idle`). Say so in §4 of `SKILL.md`: the brief should give every session the
  controller's name and the two events to report — DONE written, shared resource released.
- **The auto-mode classifier refused nothing today in seven lanes** and refused `Stop-Process`,
  a repair dry run and one read in the controller. Record per-session refusal counts in
  `state.json` so the morning reader sees the pattern without opening eight DONE notes.

## 10. Two things I would not change

- **Resume, never restart.** Every resumed session today continued from its commits; nothing was lost.
- **Guards as the merge gate, changelog at merge time by the controller.** Eight lanes appended
  nothing to the shared changelog and the runner never had a changelog conflict; the controller's
  `changelog_append.py --expect-head` never refused a stale write because there was never a second
  writer.

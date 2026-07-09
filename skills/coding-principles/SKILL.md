---
name: coding-principles
description: Apply core software-engineering discipline to any coding task in this and downstream repositories — DRY / single source of truth, test-driven development, single responsibility, documenting the why, backtracking via changelogs and ADRs, and MCP-first code navigation. Use at the start of any implementation, refactor, or bugfix, and whenever deciding how to structure code, tests, docs, or commits. Do not use for pure prose writing or non-code tasks.
---

# Coding Principles

A compact, enforceable baseline for how agents write code in this repository and
in any repository that adopts the `starters/coding-principles` pointer. These are
**flexible** principles — adapt them to context — except TDD and backtracking,
which are **rigid**: follow them exactly.

When a stronger, more specific skill is available (e.g.
`superpowers:test-driven-development`, `superpowers:systematic-debugging`), that
skill wins. This skill is the always-on floor, not a ceiling.

## Principle 1 — DRY / Single Source of Truth

Every fact, rule, or piece of logic has exactly one authoritative home. Other
places reference it; they do not restate it.

- Extract a shared unit on the **second real duplication**, not the first
  (premature abstraction is its own defect) and not the third.
- Config, constants, and copy live in one place and are imported.
- In this repo specifically: a skill's `SKILL.md` is the source of truth; starters
  and root instruction files are thin pointers, never copies of the workflow.

| Red flag | Reality |
|---|---|
| "I'll copy this block and tweak it" | Two copies drift. Extract or parameterize. |
| "It's only duplicated twice" | The third copy is coming. Extract now. |
| "I'll keep the README and the code in sync by hand" | You won't. Generate or reference. |

## Principle 2 — Test-Driven Development (rigid)

Write the failing test first, watch it fail, write the minimal code to pass,
then refactor. Defers to `superpowers:test-driven-development` when present.

- Red → Green → Refactor, one behavior at a time.
- A bug fix starts with a test that reproduces the bug.
- Never write implementation before there is a test that demands it.

| Red flag | Reality |
|---|---|
| "I'll add tests after" | After never comes, and the test can't fail-first. |
| "This is too simple to test" | Simple code breaks too; the test is cheap. |
| "The test passed on the first try" | Did you see it fail? If not, it may test nothing. |

## Principle 3 — Single Responsibility

Each module, file, function, and skill does one thing and has one reason to
change.

- If you can't describe a unit without "and", split it.
- File size is a smell: when a file grows past what you can hold in context,
  that usually means it took on a second responsibility.
- Split by responsibility, not by technical layer. Things that change together
  live together.

| Red flag | Reality |
|---|---|
| "This helper does X and also Y" | Two responsibilities. Two units. |
| "One more flag on this function" | Flags that switch behavior are a split signal. |

## Principle 4 — Documentation: document the *why*

Code shows what and how. Comments and docs exist for **why** — the constraint,
the tradeoff, the non-obvious reason.

- Keep `SKILL.md` / `README` in sync with behavior in the same change, never as
  a follow-up.
- Prefer a short "why" comment over a long "what" comment restating the code.
- Public interfaces get a one-line contract: what it does, how to call it, what
  it depends on.

| Red flag | Reality |
|---|---|
| `// increment i by 1` | Restates code. Delete or explain *why*. |
| "Docs update is a separate PR" | Docs drift from code. Same change or it's wrong. |

## Principle 5 — Backtracking via changelogs and ADRs (rigid)

Any future agent must be able to reconstruct *why* a change was made and revert
it safely. See [references/changelog-backtracking.md](references/changelog-backtracking.md).

- Maintain a `CHANGELOG.md` (Keep a Changelog style) — one entry per meaningful
  change, newest first.
- Record non-obvious decisions as ADRs under `docs/decisions/NNNN-title.md`
  (context → decision → consequences).
- Commits are small and frequent, each independently revertible, with a message
  that states intent, not just mechanics.

| Red flag | Reality |
|---|---|
| "One big commit at the end" | Un-revertible, un-reviewable. Commit per task. |
| "Everyone knows why we did this" | They won't in six months. Write the ADR. |

## Principle 6 — MCP-first navigation

Use semantic tools before brute-force file reads. In this repo the stack is
Serena (LSP symbols/refs/refactor), Graphify (code-structure graph), and
Omnigraph (structured cross-project memory). See
[skills/structured-memory/SKILL.md](../structured-memory/SKILL.md).

- Session start: load project structure and prior decisions from memory/graph
  before editing.
- Find a symbol/reference with Serena, not by reading whole files (typically
  80–95% fewer tokens).
- Ask the graph broad-structure questions; ask memory "what did we decide".
- Write durable decisions back to structured memory at session end.

| Red flag | Reality |
|---|---|
| "Let me read the whole file to find this function" | Use `find_symbol`. Cheaper and exact. |
| "I'll re-derive how this project works" | Query memory first — it's the ground truth. |

## Checklist

At the start of any implementation, refactor, or bugfix:

- [ ] Loaded project context from memory/graph (Principle 6).
- [ ] Wrote a failing test before implementation (Principle 2).
- [ ] Placed each new fact/logic in exactly one home (Principle 1).
- [ ] Each new unit has a single responsibility (Principle 3).
- [ ] Documented the *why* in the same change (Principle 4).
- [ ] Committed small; logged the change / ADR for backtracking (Principle 5).

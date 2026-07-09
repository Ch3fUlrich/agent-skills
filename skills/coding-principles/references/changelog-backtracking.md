# Backtracking via Changelogs and ADRs

The goal: any future agent (or human) can answer "why is the code like this?" and
"how do I safely undo it?" from the repository alone, without the original
author.

Two complementary records:

1. **`CHANGELOG.md`** — *what* changed, in human terms, over time.
2. **`docs/decisions/`** (ADRs) — *why* a non-obvious choice was made.

Plus the discipline that makes both usable: **small, frequently committed,
independently revertible changes**.

## CHANGELOG.md

Follow [Keep a Changelog](https://keepachangelog.com/) conventions. Newest entry
on top. Group by `Added / Changed / Fixed / Removed / Deprecated / Security`.

```markdown
# Changelog

## [Unreleased]

### Changed
- Default MCP memory layer switched from Mem0 to Omnigraph; Mem0 retained as an
  off-by-default Docker Compose fallback profile. See docs/decisions/0001-omnigraph-over-mem0.md.

### Added
- `coding-principles` and `structured-memory` skills with starters.
```

Rules:
- One bullet per meaningful change; reference the ADR or commit where relevant.
- Write it in the same change that makes the code change — not later.
- User-facing language: describe the effect, not the diff.

## Architecture Decision Records (ADRs)

For any decision that a reasonable engineer might later question — a dependency
choice, a tradeoff, a rejected alternative — write an ADR. Keep them short.

Path: `docs/decisions/NNNN-kebab-title.md` (zero-padded, monotonic).

```markdown
# 0001. Omnigraph over Mem0 for cross-project memory

- **Status:** Accepted (2026-07-09)
- **Context:** We need structured, cross-agent, cross-project memory. Mem0
  auto-extracts unstructured vector blobs; we want typed, queryable, reviewable
  memory so rules and decisions stay integrated.
- **Decision:** Adopt Omnigraph (typed nodes/edges + graph/vector/full-text
  retrieval) as the default. Replace Mem0's auto-extraction with an explicit
  structured-memory protocol.
- **Consequences:** Heavier infra (omnigraph-server + MinIO). Memory now depends
  on an agent-discipline protocol (treated as a feature). Mem0 kept as fallback.
- **Switch-back criteria:** If operating Omnigraph proves unsustainable, re-enable
  the `mem0-fallback` compose profile and layer the structured protocol on top.
```

Statuses: `Proposed → Accepted → Superseded by NNNN → Deprecated`. Never edit the
decision of an accepted ADR — supersede it with a new one and link both ways.

## Commit discipline (what makes reverts possible)

- One logical change per commit; each commit leaves the tree working.
- Message states **intent**: `feat: default memory to Omnigraph` not `update files`.
- Prefer many small commits over one large one — a bad change should be a single
  `git revert`, not archaeology.
- Reference the ADR/changelog entry in the body when the change is a decision.

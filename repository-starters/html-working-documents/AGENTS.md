# Agent Instructions

This repository uses browser-readable HTML working documents as the primary format for long planning, research, review, and project handoff artifacts.

## Use The Local Skill

When a task involves exploration, planning, implementation handoff, code review, research explanation, visual comparison, a report, a diagram, or a one-off editor, read and follow:

`./.codex/skills/html-working-documents/SKILL.md`

Read its `references/pattern-catalog.md` when choosing the artifact shape.

## Documentation Convention

- Prefer standalone `.html` artifacts over long markdown when the output benefits from layout, diagrams, tables, mockups, interaction, or sharing.
- Default new browser artifacts to `webpage/`.
- Keep HTML files self-contained: inline CSS, tiny inline JavaScript only when useful, no build step, and no remote dependencies unless explicitly justified.
- End substantial artifacts with an actionable recommendation, implementation slice, risk table, open questions, validation plan, or export button.
- Use markdown for short linear notes, README-level repository instructions, and documentation that should remain easy to diff by hand.

## New Repository Bootstrapping

If this is a new repository, create the first project plan as a browser-openable HTML file under `webpage/`. Make it concrete enough that a fresh agent session can implement from it: goals, constraints, architecture, milestones, risks, tests, and next actions.


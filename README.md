# Codex Skills

Reusable Codex skills and repository starter packs for AI-assisted projects.

This repository exists so useful agent workflows can be reused across projects instead of rediscovered in every new repository. The first skill, `html-working-documents`, teaches agents to create self-contained HTML working documents for substantial planning, exploration, review, research, reporting, prototyping, and implementation handoff work.

## Why HTML Working Documents

Long markdown plans are easy for agents to produce, but they quickly become hard to scan, compare, and reuse. Standalone HTML files can combine prose, tables, code snippets, diagrams, visual comparisons, status colors, and small interactions in one portable artifact that opens in any browser.

The goal is not to turn every note into HTML. The goal is to give future agents a clear decision rule: use HTML when layout, comparison, diagrams, mockups, interaction, or handoff value makes the work easier to understand.

## Repository Layout

```text
skills/
  html-working-documents/
    SKILL.md
    agents/openai.yaml
    references/pattern-catalog.md

repository-starters/
  html-working-documents/
    AGENTS.md
    README.md
    .codex/skills/html-working-documents/
```

## Use In An Existing Repository

Copy the contents of:

```text
repository-starters/html-working-documents/
```

into the root of your target repository.

That installs:

- `AGENTS.md`, which tells future agents when to use the workflow.
- `.codex/skills/html-working-documents/`, which contains the actual skill.

## Use As A Skill Library

If you only want the skill itself, copy:

```text
skills/html-working-documents/
```

to one of these locations:

- Repo-local: `.codex/skills/html-working-documents/`
- User-wide: `$CODEX_HOME/skills/html-working-documents/`

Repo-local installation is better when the workflow is part of a project convention. User-wide installation is better when you want the skill available everywhere.

## Current Skills

| Skill | Purpose |
| --- | --- |
| `html-working-documents` | Create self-contained HTML artifacts for planning, review, research, diagrams, reports, prototypes, and handoff. |

## Adding More Skills

Each skill should be self-contained and concise:

- Required: `SKILL.md`
- Recommended: `agents/openai.yaml`
- Optional: `references/`, `scripts/`, and `assets/`

Keep reusable detail in `references/` and keep `SKILL.md` focused on when to use the skill and how to execute the workflow.


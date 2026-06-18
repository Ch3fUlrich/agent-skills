# Agent Skills

Reusable AI-agent skills and repository starter packs for coding agents and agent orchestration setups.

This repository exists so useful agent workflows can be reused across projects instead of rediscovered in every new repository. The first skill, `html-working-documents`, teaches agents to create self-contained HTML working documents for substantial planning, exploration, review, research, reporting, prototyping, and implementation handoff work.

## Why HTML Working Documents

Long markdown plans are easy for agents to produce, but they quickly become hard to scan, compare, and reuse. Standalone HTML files can combine prose, tables, code snippets, diagrams, visual comparisons, status colors, and small interactions in one portable artifact that opens in any browser.

The goal is not to turn every note into HTML. The goal is to give future agents a clear decision rule: use HTML when layout, comparison, diagrams, mockups, interaction, or handoff value makes the work easier to understand.

## Repository Layout

```text
skills/                        # Skill library
  html-working-documents/
    SKILL.md
    agents/openai.yaml
    references/pattern-catalog.md
  mcp-servers-setup/
    SKILL.md

starters/                      # Starter packs — light pointers to the full skills
  html-working-documents/
    README.md
  mcp-servers/
    AGENTS.md
    CLAUDE.md
    README.md

mcp-servers/                   # Self-hosted MCP server stack
  config/
  docs/
  scripts/
    linux/
    windows/
  servers/
    mem0-patched/
    superpowers/

docs/
  agent-compatibility.md
```

## Use In An Existing Repository

Add a short pointer to your project's agent instruction file (`AGENTS.md`,
`CLAUDE.md`, `GEMINI.md`, or equivalent):

```markdown
## HTML Working Documents

For long planning, research, review, report, diagram, prototype, and handoff
work, follow the skill at `skills/html-working-documents/SKILL.md`.
```

See `docs/agent-compatibility.md` for the native instruction file format each
agent expects.

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
| `mcp-servers-setup` | Configure and use the self-hosted MCP server stack for token-efficient coding. |

## Adding More Skills

See `CONTRIBUTING.md` for conventions on adding skills and starter packs.

Each skill should be self-contained and concise:

- Required: `SKILL.md`
- Recommended: `agents/openai.yaml`
- Optional: `references/`, `scripts/`, and `assets/`

Keep reusable detail in `references/` and keep `SKILL.md` focused on when to use the skill and how to execute the workflow.

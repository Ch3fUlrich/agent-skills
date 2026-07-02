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

mcp-servers/                   # Self-hosted MCP server stack (Serena, Graphify,
  config/                      # Mem0, Superpowers, Playwright) — see
  scripts/                     # mcp-servers/README.md for setup and usage
  servers/
  docs/

antigravity-remote-ui/         # Setup scripts for the Omni Remote Chat UI
  start-remote-session.ps1
  start-remote-session.sh
  Dockerfile
  docker-compose.yml

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

## MCP Server Stack

`mcp-servers/` holds a self-hosted MCP server stack that reduces token usage on
code-heavy tasks through semantic navigation, a queryable project graph, and
persistent cross-session memory. It runs on your own hardware (Docker + uv +
Node.js) and needs no OpenAI API key.

| Server | Transport | Purpose |
| --- | --- | --- |
| [Serena](https://github.com/oraios/serena) | stdio (`uvx`) | LSP semantic code navigation — symbols, references, refactoring |
| [Graphify](https://github.com/safishamsi/graphify) | stdio (`uv`) | Queryable project graph for code, docs, and relationships |
| **Mem0** (official) | SSE (`docker`) | Persistent cross-session memory — REST API + pgvector |
| [Superpowers](https://github.com/erophames/superpowers-mcp) | stdio (`node`) | Disciplined workflow skills — TDD, debugging, planning, brainstorming |
| [Playwright](https://github.com/microsoft/playwright-mcp) | stdio (`npx`) | Full browser automation |

Setup, configuration, and per-agent wiring (Claude Code, Antigravity, etc.)
are documented in [mcp-servers/README.md](mcp-servers/README.md) and
[mcp-servers/docs/INSTALL-GUIDE.md](mcp-servers/docs/INSTALL-GUIDE.md). To
install the workflow instructions that teach an agent to use this stack in
another repository, see `starters/mcp-servers/`.

## Current Skills

| Skill | Purpose |
| --- | --- |
| `html-working-documents` | Create self-contained HTML artifacts for planning, review, research, diagrams, reports, prototypes, and handoff. |
| mcp-servers-setup | Configure and use the self-hosted MCP server stack for token-efficient coding. |
| antigravity-remote-ui | Automated scripts and Docker configuration to set up a remote chat session for Antigravity AI, allowing you to seamlessly continue your work from your phone. |

## Adding More Skills

See `CONTRIBUTING.md` for conventions on adding skills and starter packs.

Each skill should be self-contained and concise:

- Required: `SKILL.md`
- Recommended: `agents/openai.yaml`
- Optional: `references/`, `scripts/`, and `assets/`

Keep reusable detail in `references/` and keep `SKILL.md` focused on when to use the skill and how to execute the workflow.


# Agent Compatibility Notes

Each coding agent has its own format for project-level instructions. This page
collects the official documentation links for reference when you need to add
instructions for a specific agent.

## Agent Instruction Formats

| Agent/tool | Instruction file | Documentation |
| --- | --- | --- |
| OpenAI Codex / AGENTS.md-aware tools | `AGENTS.md` | Used by Codex, Cursor, Copilot, and others |
| Claude Code | `CLAUDE.md` or `.claude/CLAUDE.md` | https://code.claude.com/docs/en/memory |
| Cursor | `.cursor/rules/*.mdc` | https://docs.cursor.com/en/context/rules |
| VS Code / GitHub Copilot | `.github/copilot-instructions.md` | https://code.visualstudio.com/docs/copilot/customization/custom-instructions |
| Roo Code | `.roo/rules/*.md` | https://docs.roocode.com/ |
| Cline | `.clinerules/*.md` | https://docs.cline.bot/customization/cline-rules |
| Continue | `.continue/rules/*.md` | https://docs.continue.dev/customize/rules |
| Windsurf | `.windsurf/rules/*.md` or `.windsurfrules` | — |
| Gemini CLI | `GEMINI.md` | https://google-gemini.github.io/gemini-cli/docs/cli/gemini-md.html |

## Using With Skills

To reference a skill from any of these instruction files, add a short pointer:

```markdown
For long planning, research, review, and handoff work, follow the skill at
`skills/html-working-documents/SKILL.md`.
```

Keep agent-specific instruction files short. The skill itself carries the full
workflow.

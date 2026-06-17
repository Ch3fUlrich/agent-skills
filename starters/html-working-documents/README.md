# HTML Working Documents Agent Starter

Copy the contents of this folder into the root of any repository to make future AI-agent sessions use self-contained HTML working documents for substantial planning, exploration, review, research, reporting, and handoff work.

The starter is intentionally multi-agent. It includes native instruction entrypoints for Codex, Claude Code, Cursor, VS Code/GitHub Copilot, Roo Code, Cline, Continue, Windsurf, Gemini CLI, and other tools that read `AGENTS.md`.

## What To Copy

Copy these paths into the target repository root:

- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`
- `.github/copilot-instructions.md`
- `.cursor/rules/html-working-documents.mdc`
- `.roo/rules/html-working-documents.md`
- `.clinerules/html-working-documents.md`
- `.continue/rules/html-working-documents.md`
- `.windsurf/rules/html-working-documents.md`
- `.windsurfrules`
- `.codex/skills/html-working-documents/`

After copying, future agents should pick up their native instruction file automatically, load the local `html-working-documents` skill when relevant, and place long browser-readable artifacts in `webpage/` by default.

## Why This Exists

Long markdown plans are easy to generate but hard to compare, review, and reuse. A standalone HTML artifact can combine prose, tables, code snippets, diagrams, mockups, color, and small interactions in one portable file. The skill in this starter teaches agents when HTML is worth using and when normal markdown is still the better fit.

## First Use In A New Repository

1. Copy this folder's contents into the repo root.
2. Ask the agent to read its project instructions. For most tools this is automatic; if unsure, ask it to inspect `AGENTS.md`.
3. For a first planning pass, ask for a self-contained project plan in `webpage/`.
4. Keep the HTML artifact as a living handoff document for future implementation sessions.

# Agent Compatibility Notes

The `repository-starters/html-working-documents/` pack includes multiple instruction entrypoints because coding agents do not share a single configuration standard yet.

## Entrypoints

| Agent/tool | File included | Basis |
| --- | --- | --- |
| OpenAI Codex and other AGENTS.md-aware tools | `AGENTS.md` | OpenAI Codex uses `AGENTS.md` as repository guidance. VS Code also recognizes `AGENTS.md` as always-on workspace instructions. |
| Claude Code | `CLAUDE.md` | Claude Code project instructions are stored in `./CLAUDE.md` or `./.claude/CLAUDE.md`. |
| Cursor | `.cursor/rules/html-working-documents.mdc` | Cursor project rules live in `.cursor/rules` and use MDC frontmatter with `description`, `globs`, and `alwaysApply`. |
| VS Code / GitHub Copilot | `.github/copilot-instructions.md` | VS Code automatically detects this workspace file and applies it to chat requests. |
| Roo Code | `.roo/rules/html-working-documents.md` | Roo Code uses workspace rule files under `.roo/rules/`. |
| Cline | `.clinerules/html-working-documents.md` | Cline's primary workspace rule format is `.clinerules/`. It also recognizes several other rule formats. |
| Continue | `.continue/rules/html-working-documents.md` | Continue local rules live in `.continue/rules`. |
| Windsurf | `.windsurf/rules/html-working-documents.md` and `.windsurfrules` | Newer Windsurf setups use `.windsurf/rules`; the legacy root `.windsurfrules` file is included for compatibility. |
| Gemini CLI | `GEMINI.md` | Gemini CLI loads project context from `GEMINI.md` files. |

## Maintenance Rule

Keep adapters short and aligned. Put durable workflow detail in:

- `instructions/html-working-documents.md` for tool-agnostic guidance.
- `skills/html-working-documents/SKILL.md` for the full skill.
- `repository-starters/html-working-documents/.codex/skills/html-working-documents/SKILL.md` for the drop-in starter copy.

## Source References

- Claude Code memory: https://code.claude.com/docs/en/memory
- VS Code custom instructions: https://code.visualstudio.com/docs/copilot/customization/custom-instructions
- Cursor rules: https://docs.cursor.com/en/context/rules
- Cline rules: https://docs.cline.bot/customization/cline-rules
- Continue rules: https://docs.continue.dev/customize/rules
- Gemini CLI context files: https://google-gemini.github.io/gemini-cli/docs/cli/gemini-md.html
- Roo Code docs: https://docs.roocode.com/


# Contributing

This repository stores reusable AI-agent skills and starter packs. Contributions that add or improve skills are welcome.

## Adding a New Skill

Each skill lives under `skills/<skill-name>/` and follows this convention:

```
skills/<skill-name>/
├── SKILL.md              # Required — the full skill instructions
├── agents/               # Recommended — agent-specific configs
│   └── openai.yaml       # Codex agent definition
└── references/           # Optional — supporting docs, pattern catalogs
    └── ...
```

**`SKILL.md`** should be self-contained enough that an agent reading only that file can execute the skill. Put reusable detail in `references/` and keep the main file focused on when to use the skill and how to execute the workflow.

## Adding a Starter Pack

Some skills benefit from a starter pack that installs agent-specific entrypoints into a target repository. These live under `starters/<skill-name>/`:

```
starters/<skill-name>/
├── README.md             # What gets installed and how to use
├── AGENTS.md             # Instructions for AGENTS.md-aware tools
├── CLAUDE.md             # Instructions for Claude Code
├── GEMINI.md             # Instructions for Gemini CLI
├── .github/              # GitHub Copilot instructions
├── .codex/skills/        # Codex skill-style installation
├── .cursor/rules/        # Cursor rules
├── .clinerules/          # Cline rules
├── .continue/rules/      # Continue rules
├── .roo/rules/           # Roo Code rules
└── .windsurf/rules/      # Windsurf rules
```

Each adapter file should be short — a few sentences directing the agent to the full skill. Keep the adapter generic and reference the skill by name, not by tool-specific commands.

## When a Starter Pack Is Needed

Create a starter pack when:

- The skill requires per-project configuration or context.
- The user should install it by copying files into their repo root.
- Multiple agents need instructions in their native format (`.cursor/rules/*.mdc`, `.github/copilot-instructions.md`, etc.).

If the skill is self-contained and the agent will load it from a skill library, a starter pack is not needed.

## Compatibility Goal

Prefer broad, plug-and-play compatibility over a single-vendor setup. If a workflow should work in multiple agents, provide the native instruction file each agent expects and keep each adapter short.

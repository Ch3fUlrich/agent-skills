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

Some skills benefit from a starter pack — a short README that points users to
the full skill and explains the convention. These live under
`starters/<skill-name>/`:

```
starters/<skill-name>/
└── README.md             # What the skill does and how to reference it
```

The README should be short — a few sentences directing the user to the full
skill. Reference the skill by path, not by tool-specific commands.

If additional agent-specific instruction files are genuinely needed (different
content per agent, not just different filenames), add them alongside the README.
See `docs/agent-compatibility.md` for the native format each agent expects.

## When a Starter Pack Is Needed

Create a starter pack when:

- The skill requires per-project context or convention explanation.
- Users need a quick reference for how to wire the skill into their project.

If the skill is self-contained and the agent will load it from a skill library,
a starter pack is not needed.

## Compatibility Goal

Prefer broad, plug-and-play compatibility over a single-vendor setup. If a workflow should work in multiple agents, provide the native instruction file each agent expects and keep each adapter short.

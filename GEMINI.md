# Gemini CLI Instructions

**Read [AGENTS.md](AGENTS.md) first** — skills, memory model, env vars, hard rules.
This file is *only* the Gemini/Antigravity delta. Start at the router:
`skills/repository-index/SKILL.md`.

## Antigravity notes

- **Config:** `infra/mcp-servers/config/mcp_antigravity.json`. Antigravity reads its global
  `mcp_config.json` — location and transport in `infra/mcp-servers/README.md`.
- **That config is GLOBAL**, so unlike a project-scoped `.mcp.json` it cannot pin a per-repo
  graph. **Always set `OMNIGRAPH_GRAPH_ID` to the active repository folder name (e.g. `agent-skills`, `basic-analysis`) before launching or writing memory**, or you read and write the wrong graph — silently, with no error. **Never write or push project memory to the `memory` graph/branch.**
- `.agents/AGENTS.md` in a target repo may define swarm roles (`@architect` / `@engineer` /
  `@reviewer`). `skills/swarm-orchestration/SKILL.md` is the source of truth; keep that file
  a pointer.

## Scratch Scripts & Filesystem Hygiene

- **NEVER create scratch scripts or query files in random repository locations or the root folder** (e.g., `scratch_query.py`).
- Always write temporary scratch scripts inside connected/designated scratch folders:
  - Antigravity session scratch: `<appDataDir>/brain/<conversation-id>/scratch/`
  - Repository scratch folder: `scratch/` or `.gemini/scratch/`
- Delete throwaway scripts when finished or keep them inside the designated scratch folder.

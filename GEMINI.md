# Gemini CLI Instructions

**Read [AGENTS.md](AGENTS.md) first** — skills, memory model, env vars, hard rules.
This file is *only* the Gemini/Antigravity delta. Start at the router:
`skills/repository-index/SKILL.md`.

## Antigravity notes

- **Config:** `infra/mcp-servers/config/mcp_antigravity.json`. Antigravity reads its global
  `mcp_config.json` — location and transport in `infra/mcp-servers/README.md`.
- **That config is GLOBAL**, so unlike a project-scoped `.mcp.json` it cannot pin a per-repo
  graph. **Set `OMNIGRAPH_GRAPH_ID` to the repo you are working in before launching**, or you
  read and write the wrong graph — silently, with no error.
- `.agents/AGENTS.md` in a target repo may define swarm roles (`@architect` / `@engineer` /
  `@reviewer`). `skills/swarm-orchestration/SKILL.md` is the source of truth; keep that file
  a pointer.

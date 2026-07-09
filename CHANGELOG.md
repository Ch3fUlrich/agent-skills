# Changelog

All notable changes to this repository are recorded here, newest first.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Deployed the Omnigraph memory stack on coding.vm via the single-source
  `Server/server/coding/mcp-servers/docker-compose.yml` (server + MinIO + viewer),
  seeded, with real Ollama `nomic-embed-text` embeddings and working semantic
  search. Read-only branch-aware memory **viewer** and `search_decisions` query.
- `infra/mcp-servers/setup/`: client/server setup guide, `client-setup.sh`,
  and `omnigraph-sync.sh` (+ systemd timer) for automatic device-branch sync.
- `coding-principles` skill + starter: DRY, TDD, single responsibility,
  document-the-why, changelog/ADR backtracking, MCP-first navigation.
- `structured-memory` skill: typed cross-project memory protocol on Omnigraph
  (schema + recall/persist workflow).
- `infra/remote-access/herdr/`: Herdr agent-multiplexer setup for Linux, macOS,
  and Windows, with helper scripts and a remote-access comparison guide.
- Omnigraph + MinIO as the default memory stack in `infra/mcp-servers/`, plus
  `servers/omnigraph/README.md`.
- ADRs: `0001-omnigraph-over-mem0`, `0002-herdr-multiplexer`.
- Restructure spec + implementation plan under `docs/superpowers/`.

### Changed
- **Repository restructured** into three pillars: `skills/` (reusable skills),
  `starters/` (per-repo adapters), `infra/` (self-hosted runtime:
  `mcp-servers/` + `remote-access/`). Loose dirs `Gen/`, `prompt/`,
  `repositories/` consolidated into `prompts/`; `mcp-servers/` and
  `antigravity-remote-ui/` moved under `infra/`.
- Default MCP memory layer switched from Mem0 to Omnigraph. Mem0 retained as an
  off-by-default `mem0-fallback` Compose profile. See
  `docs/decisions/0001-omnigraph-over-mem0.md`.
- Root instruction files (`AGENTS.md`, `CLAUDE.md`, new `GEMINI.md`) reduced to
  thin pointers at the skills.
- Infra scripts/configs de-personalized: hardcoded paths replaced with
  `${AGENT_SKILLS_ROOT}` / `${CODE_ROOT}` / `${SERENA_HOME}` (and PowerShell
  `$env:` equivalents).

### Removed
- Committed generated `graphify-out/` output is no longer tracked.

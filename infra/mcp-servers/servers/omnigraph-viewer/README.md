# Omnigraph Memory Viewer

A minimal **read-only** web viewer for the Omnigraph `memory` graph. Omnigraph
ships no self-hostable UI (the `ui` cluster field is reserved upstream), so this
fills the gap: it lists projects and the typed memory nodes (Decisions, Rules,
Preferences, Conventions, Components) via the server's stored-query routes.

## Design

- Server-rendered HTML (Flask + gunicorn). No client JS, no external assets —
  Authelia/Caddy-friendly and CSP-safe.
- **Holds the Omnigraph bearer token server-side**; the browser never sees it.
- Read-only: it only calls `GET /graphs` and `POST /graphs/<id>/queries/<name>`
  (the `list_*` stored queries declared in `cluster/queries/memory.gq`).

> **Security:** the app has no auth of its own — put **Authelia SSO in front**
> (Caddy `import authelia`). Never expose it directly. The Omnigraph **API**
> host, by contrast, is protected by its own bearer token and must NOT sit
> behind Authelia (that would block programmatic/MCP clients).

## Env

| Var | Default | Purpose |
|---|---|---|
| `OMNIGRAPH_URL` | `http://omnigraph-server:8080` | Omnigraph server base URL |
| `OMNIGRAPH_TOKEN` | — | bearer token (kept server-side) |
| `OMNIGRAPH_GRAPH` | `memory` | graph id to view |
| `PORT` | `8090` | listen port |

## Run

It is defined as the `omnigraph-viewer` service in the deployment compose
(`Server/server/coding/mcp-servers/docker-compose.yml`) and, for local testing,
in `agent-skills/infra/mcp-servers/docker-compose.yml`. Behind Caddy it is
served at `omnigraph-ui.ohje.ooguy.com` (Authelia-gated).

```bash
docker compose up -d omnigraph-viewer   # then browse http://127.0.0.1:8090
```

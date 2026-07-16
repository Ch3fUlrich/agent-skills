# graphify-mcp (Docker)

Containerized build of the `graphify` stdio MCP server (see
`../../README.md#graphify-visualizations` and
`../../docs/INSTALL-GUIDE.md#how-graphify-fits-in` for what graphify does and
the local-Ollama extraction gotchas). This image exists so a repo can run
graphify's MCP server without a host-level `uv`/Python toolchain — only
Docker is required.

## Why `docker run -i`, not docker-compose

`graphify.serve` (see `graphify/serve.py` in the package) is stdio-only —
there is no built-in SSE/HTTP transport, unlike serena in this repo. That
means it can't be a long-running compose service the way `serena` is; it
has to be spawned fresh per Claude Code session,
exactly like the `uv run ...` command it replaces. Claude Code (and any
other MCP client) is fine with `docker run -i` as the spawned command — it's
just a subprocess with stdin/stdout piped, same as `uv`/`npx`/`uvx`.

## Build

```bash
docker build -t graphify-mcp:latest mcp-servers/servers/graphify-mcp
```

## Generate the graph (once per repo, before first use)

The image only serves an existing `graphify-out/graph.json`; it doesn't
build one. From the repo you want to graph:

```bash
# Deterministic AST-only graph, no LLM/API key needed, fast (~1s for this repo):
docker run --rm -v "$PWD:/repo" -w /repo --entrypoint python graphify-mcp:latest \
  -m graphify update .

# Fuller graph with LLM-derived semantic edges (needs a backend/API key —
# see docs/INSTALL-GUIDE.md and README.md's Ollama gotchas section):
docker run --rm -v "$PWD:/repo" -w /repo --entrypoint python graphify-mcp:latest \
  -m graphify extract . --backend <gemini|openai|deepseek|ollama|...>
```

Regenerate with `update` (or re-run `extract`) after significant code
changes; graphify's own git hooks (`graphify hook install`) can automate
this outside the container.

## Run (test a raw handshake)

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | \
  docker run -i --rm -v "$PWD:/repo" graphify-mcp:latest
```

A working server replies with a `serverInfo` block on stdout. Ctrl-D (EOF on
stdin) ends the container.

## Register with Claude Code

Add to `config/mcp-claude-code.json` (or `claude mcp add`) in place of the
`uv run --with graphifyy[mcp] ...` command:

```json
"graphify": {
  "command": "docker",
  "args": [
    "run", "-i", "--rm",
    "-v", "${AGENT_SKILLS_DIR}:/repo",
    "graphify-mcp:latest"
  ]
}
```

`${AGENT_SKILLS_DIR}` should point at whichever repo's `graphify-out/` you
want served — the graph path (`graphify-out/graph.json`) is resolved
relative to `/repo` inside the container.

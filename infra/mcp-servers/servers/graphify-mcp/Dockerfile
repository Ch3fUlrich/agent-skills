FROM python:3.12-slim

# graphify's own extractors need no compiler (tree-sitter ships prebuilt
# wheels), so this stays a single-stage slim image.
RUN pip install --no-cache-dir "graphifyy[mcp]"

WORKDIR /repo

# graphify.serve is a stdio MCP server (see graphify/serve.py) — no SSE/HTTP
# transport exists, so this container is meant to be run with `docker run -i`
# and the repo bind-mounted at /repo, not as a long-running compose service.
ENTRYPOINT ["python", "-m", "graphify.serve"]
CMD ["graphify-out/graph.json"]

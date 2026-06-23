"""MCP SSE bridge for self-hosted Mem0 REST API.

Exposes memory tools (add, search, list, delete) over Server-Sent Events
so CodeWhale and Claude Code can use mem0 without the stdio timeout issue.

Connects to the mem0 REST API container (mem0:8000) on the Docker network.
"""

import json
import os
import sys
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

# ─── Fix .env Encoding ───────────────────────────────────────────────────────
# Ensure .env is UTF-8 encoded to prevent Pydantic crashes on Windows CP1252
_env_path = ".env"
if os.path.exists(_env_path):
    try:
        with open(_env_path, "rb") as f:
            _content = f.read()
        _content.decode("utf-8")
    except UnicodeDecodeError:
        print("Fixing .env file encoding to UTF-8", file=sys.stderr)
        with open(_env_path, "wb") as f:
            f.write(_content.decode("cp1252", errors="replace").encode("utf-8"))

from mcp.server.fastmcp import FastMCP

# ─── Config ──────────────────────────────────────────────────────────────────
MEM0_API_URL = os.environ.get("MEM0_API_URL", "http://mem0:8000")
MEM0_USER_ID = os.environ.get("MEM0_USER_ID", "mauls")
PORT = int(os.environ.get("PORT", "8001"))

mcp = FastMCP(
    "mem0-mcp",
    host="0.0.0.0",
    port=PORT,
)

# ─── HTTP helpers ────────────────────────────────────────────────────────────


def _mem0_request(method: str, path: str, body: dict | None = None) -> dict:
    """Make a request to the mem0 REST API and return parsed JSON."""
    url = f"{MEM0_API_URL}{path}"
    data = json.dumps(body).encode() if body else None
    headers = {"Content-Type": "application/json"} if data else {}

    req = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode())
    except HTTPError as e:
        detail = e.read().decode() if e.fp else str(e)
        raise RuntimeError(f"mem0 API error {e.code}: {detail}") from e
    except URLError as e:
        raise RuntimeError(f"mem0 API unreachable at {MEM0_API_URL}: {e}") from e


# ─── Health check ────────────────────────────────────────────────────────────


@mcp.tool(name="health", description="Check if the mem0 MCP bridge and backend API are healthy.")
def health() -> str:
    """Health check for the bridge and the upstream mem0 API."""
    try:
        result = _mem0_request("GET", "/health")
        return json.dumps({"status": "ok", "mem0_api": result})
    except Exception as e:
        return json.dumps({"status": "degraded", "error": str(e)})


# ─── Memory tools ────────────────────────────────────────────────────────────


@mcp.tool(name="add_memory", description="Store text or conversation as a memory. Returns the created memory object.")
def add_memory(
    content: str,
    user_id: str = "",
    metadata: dict | None = None,
) -> str:
    """Add a memory. The mem0 API extracts facts and stores them."""
    uid = user_id or MEM0_USER_ID
    body: dict = {"messages": [{"role": "user", "content": content}], "user_id": uid}
    if metadata:
        body["metadata"] = metadata
    result = _mem0_request("POST", "/memories", body)
    return json.dumps(result, indent=2)


@mcp.tool(name="search_memories", description="Semantic search across memories. Returns ranked results with scores.")
def search_memories(
    query: str,
    user_id: str = "",
    limit: int = 10,
) -> str:
    """Search memories semantically."""
    uid = user_id or MEM0_USER_ID
    body: dict = {"query": query, "user_id": uid, "limit": limit}
    result = _mem0_request("POST", "/memories/search", body)
    return json.dumps(result, indent=2)


@mcp.tool(name="get_memories", description="List all memories for a user. Use before adding to avoid duplicates.")
def get_memories(
    user_id: str = "",
) -> str:
    """List all memories for a user."""
    uid = user_id or MEM0_USER_ID
    result = _mem0_request("GET", f"/memories?user_id={uid}")
    return json.dumps(result, indent=2)


@mcp.tool(name="delete_memory", description="Delete a memory by its ID. Returns confirmation.")
def delete_memory(
    memory_id: str,
    user_id: str = "",
) -> str:
    """Delete a single memory."""
    uid = user_id or MEM0_USER_ID
    result = _mem0_request("DELETE", f"/memories/{memory_id}?user_id={uid}")
    return json.dumps(result, indent=2)


# ─── Entrypoint ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    transport = os.environ.get("MCP_TRANSPORT", "sse")
    print(f"mem0 MCP bridge starting with transport: {transport}", file=sys.stderr)
    print(f"  MEM0_API_URL = {MEM0_API_URL}", file=sys.stderr)
    print(f"  MEM0_USER_ID = {MEM0_USER_ID}", file=sys.stderr)
    if transport == "sse":
        print(f"  PORT = {PORT}", file=sys.stderr)
    mcp.run(transport=transport)

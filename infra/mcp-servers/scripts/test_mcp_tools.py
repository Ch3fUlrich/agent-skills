#!/usr/bin/env python3
"""Script to verify MCP server tools by connecting to them via stdio transport

This script spawns each configured MCP server (Serena, Mem0, Superpowers) as a subprocess,
establishes an MCP client-server connection, retrieves its tools, and calls a basic validation tool.

Requirements:
    - uv (or python with the mcp package installed)
Usage:
    uv run --with mcp>=1.6.0 scripts/test_mcp_tools.py
"""

import asyncio
import os
import sys
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def test_mcp_server(name: str, command: str, args: list, env: dict = None, validation_tool: str = None, validation_args: dict = None):
    print(f"=== Testing MCP Server: {name} ===")
    print(f"Command: {command} {' '.join(args)}")
    
    # Merge existing environment to preserve PATH etc.
    full_env = os.environ.copy()
    if env:
        full_env.update(env)
        
    server_params = StdioServerParameters(
        command=command,
        args=args,
        env=full_env
    )
    
    try:
        # Use a timeout of 15 seconds for connection and initialization
        async with asyncio.timeout(15):
            async with stdio_client(server_params) as (read_stream, write_stream):
                async with ClientSession(read_stream, write_stream) as session:
                    print("Connecting and initializing...")
                    await session.initialize()
                    
                    # 1. List tools
                    print("Listing tools...")
                    tools_result = await session.list_tools()
                    tools = tools_result.tools
                    print(f"[PASS] Successfully connected. Found {len(tools)} tools:")
                    for t in tools[:5]:
                        print(f"  - {t.name}: {t.description[:60]}...")
                    if len(tools) > 5:
                        print(f"  ... and {len(tools) - 5} more.")
                    
                    # 2. Call validation tool
                    if validation_tool:
                        print(f"Calling validation tool '{validation_tool}' with args {validation_args or '{}'}...")
                        res = await session.call_tool(validation_tool, arguments=validation_args or {})
                        # Find the text content
                        text_content = ""
                        for content in res.content:
                            if hasattr(content, "text"):
                                text_content += content.text
                            elif isinstance(content, dict) and "text" in content:
                                text_content += content["text"]
                        
                        snippet = text_content[:150].replace('\n', ' ')
                        print(f"[PASS] Tool call success. Result snippet: {snippet}...")
                    
                    print(f"=== {name} Test PASSED ===\n")
                    return True
    except asyncio.TimeoutError:
        print(f"[FAIL] {name} connection timed out after 15 seconds.\n")
        return False
    except Exception as e:
        print(f"[FAIL] {name} test encountered error: {e}\n")
        return False


async def main():
    # Paths (relative to script root if possible, or using env if needed)
    # We resolve relative paths based on the repository structure
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    superpowers_js = os.path.join(repo_root, "servers", "superpowers", "build", "index.js")
    mem0_server_py = os.path.join(repo_root, "servers", "mem0-mcp", "server.py")
    
    # 1. Serena config
    serena_config = {
        "name": "Serena",
        "command": "uvx",
        "args": [
            "--from", "serena-agent", "serena", "start-mcp-server",
            "--project-from-cwd",
            "--open-web-dashboard", "false",
            "--enable-gui-log-window", "false"
        ],
        "env": {
            "SERENA_HOME": os.path.expanduser("~/.serena")
        },
        "validation_tool": "get_current_config",
        "validation_args": {}
    }
    
    # 2. Superpowers config
    superpowers_config = {
        "name": "Superpowers",
        "command": "node",
        "args": [superpowers_js],
        "validation_tool": "list_skills",
        "validation_args": {}
    }
    
    # 3. Mem0 config
    mem0_config = {
        "name": "Mem0",
        "command": "uv",
        "args": [
            "run", "--with", "mcp>=1.6.0",
            mem0_server_py
        ],
        "env": {
            "MCP_TRANSPORT": "stdio",
            "MEM0_API_URL": "http://localhost:8888",
            "MEM0_USER_ID": "your-username"
        },
        "validation_tool": "health",
        "validation_args": {}
    }
    
    # Run tests
    results = []
    
    # We test Serena (note that get_current_config might fail if not in an active project,
    # so we'll check listing tools for success first, and let tool call be optional/checked gracefully)
    # But wait, Serena is activated globally in our previous step so it might pass config check
    results.append(await test_mcp_server(**serena_config))
    results.append(await test_mcp_server(**superpowers_config))
    results.append(await test_mcp_server(**mem0_config))
    
    success_count = sum(1 for r in results if r)
    total_count = len(results)
    
    print(f"Verification Summary: {success_count}/{total_count} servers passed.")
    if success_count < total_count:
        print("Some tests failed!")
        sys.exit(1)
    else:
        print("All MCP server tools are verified and working!")
        sys.exit(0)


if __name__ == "__main__":
    asyncio.run(main())

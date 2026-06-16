# MCP Server Stack — CLAUDE.md

This repository is configured with a self-hosted MCP server stack. When Claude
Code connects to the MCP servers, the following tools are available:

## Serena Tools (Code Navigation)

Replace file reads with LSP-powered semantic lookups:

- `mcp_serena_find_symbol` — Find definitions
- `mcp_serena_find_references` — Find all usages
- `mcp_serena_get_file_structure` — File tree view
- `mcp_serena_get_code_context` — Code around a location

**Rule**: Before reading a file to find something, ask Serena. It returns
precise results in far fewer tokens.

## Mem0 Tools (Persistent Memory)

Store and retrieve knowledge across sessions:

- `mcp_mem0_remember "fact"` — Store for future sessions
- `mcp_mem0_recall "query"` — Retrieve relevant memories
- `mcp_mem0_search_memories "term"` — Full-text search

**Rule**: After learning anything reusable (architecture, preferences, patterns),
store it in Mem0 immediately.

## Superpowers Tools (Workflows)

Structured approaches for complex tasks:

- `mcp_superpowers_use_skill "tdd"` — Test-driven development
- `mcp_superpowers_use_skill "debug"` — Systematic debugging
- `mcp_superpowers_use_skill "plan"` — Structured planning
- `mcp_superpowers_use_skill "brainstorm"` — Idea generation

**Rule**: For multi-step tasks, activate the relevant workflow first instead
of improvising.

## Infrastructure

- Qdrant (vector DB): http://localhost:6333
- Ollama (embeddings): http://localhost:11434
- Model: bge-m3 (~2 GB, GPU-accelerated)

## Token Savings

This stack reduces token usage by 40-60% compared to raw file reading and
session-from-scratch approaches.

Note: Some Claude Code built-in tools may overlap with Serena. Prefer Serena
for semantic queries (find_symbol, find_references) and use built-in tools
for file writes and shell commands.

from __future__ import annotations

from typing import Any, Dict, List


def normalize_tool_names(tools: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    normalized = []
    for tool in tools:
        normalized.append({
            "name": tool.get("name"),
            "description": tool.get("description", ""),
            "schema": tool.get("schema", {}),
        })
    return normalized


def make_cache_metadata(enabled: bool, stable_blocks: List[str]) -> Dict[str, Any]:
    return {
        "enabled": enabled,
        "stable_blocks": stable_blocks,
    }


def make_checkpoint_metadata(agent_id: str, task_id: str, branch: str, worktree: str) -> Dict[str, Any]:
    return {
        "agent_id": agent_id,
        "task_id": task_id,
        "branch": branch,
        "worktree": worktree,
    }
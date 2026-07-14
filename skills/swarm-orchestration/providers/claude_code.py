from __future__ import annotations

from typing import Any, Dict

from providers.base import AgentRequest, AgentResponse, ProviderAdapter
from providers.common import normalize_tool_names


class ClaudeCodeAdapter:
    name = "claude_code"

    def capabilities(self) -> Dict[str, Any]:
        return {
            "native_checkpointing": True,
            "explicit_cache_control": True,
            "subagents": True,
            "skills": True,
            "mcp": True,
            "terminal": True,
        }

    def supports_native_checkpointing(self) -> bool:
        return True

    def supports_explicit_cache_control(self) -> bool:
        return True

    def build_request(self, request: AgentRequest) -> Dict[str, Any]:
        payload = {
            "model": request.model,
            "system": request.system_prompt,
            "prompt": request.user_prompt,
            "tools": normalize_tool_names(request.tools),
            "mcp_servers": request.mcp_servers,
            "skills": request.skill_ids,
            "metadata": request.metadata,
        }
        if request.cache_control:
            payload["cache_control"] = request.cache_control
        if request.checkpoint_hint:
            payload["checkpoint_hint"] = request.checkpoint_hint
        return payload

    def invoke(self, request: AgentRequest) -> AgentResponse:
        payload = self.build_request(request)
        return AgentResponse(
            agent_id=request.agent_id,
            role=request.role,
            status="stubbed",
            content="Claude Code adapter invocation placeholder.",
            raw=payload,
        )

    def resume(self, request: AgentRequest) -> AgentResponse:
        return self.invoke(request)
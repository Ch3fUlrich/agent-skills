from __future__ import annotations

from typing import Any, Dict

from providers.base import AgentRequest, AgentResponse
from providers.common import normalize_tool_names


class OpenHandsAdapter:
    name = "openhands"

    def capabilities(self) -> Dict[str, Any]:
        return {
            "native_checkpointing": False,
            "explicit_cache_control": False,
            "subagents": False,
            "skills": False,
            "mcp": True,
            "terminal": True,
            "browser": True,
        }

    def supports_native_checkpointing(self) -> bool:
        return False

    def supports_explicit_cache_control(self) -> bool:
        return False

    def build_request(self, request: AgentRequest) -> Dict[str, Any]:
        return {
            "model": request.model,
            "system_prompt": request.system_prompt,
            "task": request.user_prompt,
            "tools": normalize_tool_names(request.tools),
            "mcp_servers": request.mcp_servers,
            "metadata": request.metadata,
            "working_directory": request.working_directory,
        }

    def invoke(self, request: AgentRequest) -> AgentResponse:
        payload = self.build_request(request)
        return AgentResponse(
            agent_id=request.agent_id,
            role=request.role,
            status="stubbed",
            content="OpenHands adapter invocation placeholder.",
            raw=payload,
        )

    def resume(self, request: AgentRequest) -> AgentResponse:
        return self.invoke(request)
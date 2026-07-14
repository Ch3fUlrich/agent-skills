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
            "structured_output": False,
            "strict_schema": False,
            "tool_calling": True,
            "json_mode": False,
            "prompt_json_fallback": True,
            "plain_text": True,
        }

    def supports_native_checkpointing(self) -> bool:
        return False

    def supports_explicit_cache_control(self) -> bool:
        return False

    def build_request(self, request: AgentRequest) -> Dict[str, Any]:
        system_prompt = request.system_prompt
        
        if request.allow_prompt_fallback and request.response_strategy == "prompt_fallback":
            from providers.common import get_prompt_fallback_instruction
            fallback_instruction = get_prompt_fallback_instruction(request.response_schema)
            system_prompt = (system_prompt or "") + fallback_instruction

        return {
            "model": request.model,
            "system_prompt": system_prompt,
            "task": request.user_prompt,
            "tools": normalize_tool_names(request.tools) if request.response_strategy == "tool_calling" else [],
            "mcp_servers": request.mcp_servers,
            "metadata": request.metadata,
            "working_directory": request.working_directory,
            "response_strategy": request.response_strategy,
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
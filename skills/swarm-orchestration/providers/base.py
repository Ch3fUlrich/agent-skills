from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Protocol


@dataclass
class AgentRequest:
    agent_id: str
    role: str
    model: str
    system_prompt: str
    user_prompt: str
    tools: List[Dict[str, Any]] = field(default_factory=list)
    mcp_servers: List[str] = field(default_factory=list)
    skill_ids: List[str] = field(default_factory=list)
    working_directory: Optional[str] = None
    branch: Optional[str] = None
    worktree: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    cache_control: Dict[str, Any] = field(default_factory=dict)
    checkpoint_hint: Dict[str, Any] = field(default_factory=dict)


@dataclass
class AgentResponse:
    agent_id: str
    role: str
    status: str
    content: str
    tool_calls: List[Dict[str, Any]] = field(default_factory=list)
    files_touched: List[str] = field(default_factory=list)
    verification: Dict[str, Any] = field(default_factory=dict)
    token_usage: Dict[str, Any] = field(default_factory=dict)
    raw: Dict[str, Any] = field(default_factory=dict)


class ProviderAdapter(Protocol):
    name: str

    def capabilities(self) -> Dict[str, Any]:
        ...

    def build_request(self, request: AgentRequest) -> Dict[str, Any]:
        ...

    def invoke(self, request: AgentRequest) -> AgentResponse:
        ...

    def resume(self, request: AgentRequest) -> AgentResponse:
        ...

    def supports_native_checkpointing(self) -> bool:
        ...

    def supports_explicit_cache_control(self) -> bool:
        ...
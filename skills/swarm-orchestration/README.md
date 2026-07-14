# Swarm Orchestration Scaffold

This repository contains a provider-agnostic agent orchestration system that uses Markdown for canonical policy, YAML for declarative runtime config, and Python for the local execution scaffold. 

## Architectural Principles

1. **Markdown Remains Canonical**
   - `SKILL.md`, `ARCHITECTURE_CONTRACT.md`, `AGENT_ORCHESTRATION_FRAMEWORK.md`, and `AGENT_ORCHESTRATION_RATIONALE.md` define the rules and constraints of the system. Coding agents read these files first.
2. **YAML is Declarative Runtime Policy**
   - `agent_orchestration.config.yaml` controls runtime routing, risk thresholds, MCP assignments, and provider failovers. It separates threshold numbers from Python execution code.
3. **Python is Execution Support**
   - `orchestrator_scaffold.py` provides the runtime state mechanics. It coordinates checkpoint persistence, risk scoring, git worktree creation, and routing between providers. It doesn't overwrite Markdown rules.
4. **Provider-Specific Logic is Isolated**
   - The `providers/` package contains individual provider adapters (e.g. `claude_code.py`, `antigravity.py`). This prevents the core orchestrator from getting tangled up in provider-specific request formats or features.

## Implemented vs Stubbed

- **Implemented**: Risk Engine, Budget Engine, Git Manager (branches/worktrees), Checkpointing (state storage), Contract Hash Manager, MCP Router, Provider Executor, Role Router.
- **Stubbed**: The actual API clients inside the `providers/` adapters. They currently return a simulated success payload, making the scaffold safe for local structural testing without API keys.

## Running the Dry-Run Example

A minimal runnable example script is provided in `examples/run_orchestrator.py`. This simulates an end-to-end task (creating a contract, assigning an engineer, writing a checkpoint, and doing a review pass) purely using stubbed provider responses.

```bash
python examples/run_orchestrator.py
```

This acts as a smoke test to validate that the YAML config can be parsed, worktrees can be managed, and requests route correctly to the stubbed providers.

## How to Add a New Provider Adapter

1. Create a new file in `providers/` (e.g., `my_provider.py`).
2. Implement a class that matches the interface in `providers/base.py` (needs `capabilities()`, `supports_native_checkpointing()`, `supports_explicit_cache_control()`, `build_request()`, `invoke()`, `resume()`).
3. Import your adapter in `providers/registry.py` and add it to the `_providers` dictionary.
4. Update `agent_orchestration.config.yaml` to route roles (or fallback paths) to your new provider.

## Next Implementation Steps

1. **Live Provider Implementation**: Replace the stubs in `providers/` with actual API client calls for the respective agentic backends.
2. **State Cleanup & Locking Logic Implementation**: Add the missing Git hook or automated cleanup tasks to remove stale locks and merged worktrees.
3. **Verification/Test Feedback Parsing**: Pipe actual `pytest`/`ruff`/`mypy` output into the reviewer payload automatically.

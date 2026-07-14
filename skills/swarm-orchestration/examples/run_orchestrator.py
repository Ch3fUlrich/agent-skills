import json
import os
import sys
from pathlib import Path

# Ensure the root of the skill is in the Python path so we can import the orchestrator
skill_root = Path(__file__).parent.parent
sys.path.insert(0, str(skill_root))

from orchestrator_scaffold import Orchestrator, RiskSignals, ContractManager

def run_dry_run():
    config_path = skill_root / "agent_orchestration.config.yaml"
    repo_root = skill_root

    print("1. Loading YAML config...")
    orch = Orchestrator(str(config_path), str(repo_root))

    print("2. Building mock task...")
    signals = RiskSignals(
        touches_more_than_3_files=0.0,
        modifies_public_api=0.0,
        ambiguous_acceptance_criteria=0.0,
        weak_or_missing_test_coverage=0.0,
        cross_module_interface_change=0.0,
    )

    task = orch.build_task(
        task_id="task-mock-001",
        title="Add normalize_user_event() helper",
        scope_files=["src/events.py", "tests/test_events.py"],
        objective="Add a new normalize_user_event() helper to a small Python module and add tests.",
        acceptance=[
            "tests pass",
            "lint passes",
            "no forbidden files modified",
            "no public API break"
        ],
        signals=signals,
    )

    print(f"3. Risk Computed: Score={task.risk_score:.2f}, Mode={task.execution_mode}")

    print("4. Preparing worktree metadata...")
    agent_id = "mock-engineer-001"
    branch = f"agent/{agent_id}"
    worktree = str(orch.state.worktrees_dir / agent_id)
    print(f"   Branch: {branch}, Worktree: {worktree}")

    print("5. Writing initial checkpoint...")
    # Mocking the contract hash since we don't have a real ARCHITECTURE_CONTRACT.md in this example execution environment
    contract_hash = "mock_hash_123" 
    checkpoint = orch.create_engineer_checkpoint(agent_id, task, contract_hash, branch, worktree)
    orch.state.write_checkpoint(checkpoint)
    print(f"   Checkpoint path: {orch.state.checkpoint_path(agent_id)}")

    print("6. Invoking Architect (Stub)...")
    architect_result = orch.invoke_role_agent(
        role="architect",
        agent_id="mock-architect-001",
        system_prompt="You are the architect.",
        user_prompt="Create ARCHITECTURE_CONTRACT.md for task-mock-001",
        tools=[],
        task_tags=["planning"],
        skill_ids=["planning"],
        metadata={},
        working_directory=str(repo_root)
    )
    print(f"   Architect Provider: {architect_result.provider_name} ({architect_result.model})")
    print(f"   Architect Result: {architect_result.response.status}")

    print("7. Invoking Engineer (Stub)...")
    engineer_result = orch.invoke_role_agent(
        role="engineer",
        agent_id=agent_id,
        system_prompt="You are the engineer.",
        user_prompt="Implement the normalize_user_event() helper according to the contract.",
        tools=[],
        task_tags=["implementation"],
        skill_ids=["implementation"],
        metadata={},
        working_directory=worktree,
        branch=branch,
        worktree=worktree
    )
    print(f"   Engineer Provider: {engineer_result.provider_name} ({engineer_result.model})")
    print(f"   Engineer Result: {engineer_result.response.status}")

    print("8. Invoking Reviewer (Stub)...")
    reviewer_result = orch.invoke_role_agent(
        role="reviewer",
        agent_id="mock-reviewer-001",
        system_prompt="You are the reviewer.",
        user_prompt="Verify the engineer's implementation against the contract.",
        tools=[],
        task_tags=["verification"],
        skill_ids=["review"],
        metadata={},
        working_directory=worktree,
        branch=branch,
        worktree=worktree
    )
    print(f"   Reviewer Provider: {reviewer_result.provider_name} ({reviewer_result.model})")
    print(f"   Reviewer Result: {reviewer_result.response.status}")

    print("\n--- Final Status Summary ---")
    summary = {
        "task_id": task.task_id,
        "risk_score": task.risk_score,
        "execution_mode": task.execution_mode,
        "architect_status": architect_result.response.status,
        "architect_provider": architect_result.provider_name,
        "engineer_status": engineer_result.response.status,
        "engineer_provider": engineer_result.provider_name,
        "reviewer_status": reviewer_result.response.status,
        "reviewer_provider": reviewer_result.provider_name,
        "checkpoint_file": str(orch.state.checkpoint_path(agent_id)),
    }
    print(json.dumps(summary, indent=2))

if __name__ == "__main__":
    run_dry_run()

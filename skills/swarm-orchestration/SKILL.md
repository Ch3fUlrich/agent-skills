---
name: swarm-orchestration
description: Multi-agent coding orchestration for large codebases, medium applications, and small scripts. Defines roles, handoffs, cache-aware prompting, checkpointing, recovery, and verification.
---

# Swarm Orchestration

Use this skill for complex implementation, refactoring, migrations, debugging, and verification work that benefits from role separation.

## Roles

### @architect
- Role: planner, orchestrator, decomposer, risk scorer.
- Writes no application code unless explicitly required by the task.
- Owns:
  - `task.md`
  - `BUG_REGISTER.md`
  - `ARCHITECTURE_CONTRACT.md`
  - checkpoint coordination
  - model routing
  - Best-of-N decisions
- Allowed MCP focus:
  - Graphify
  - Omnigraph
  - Context7
  - Superpowers
  - Fetch
  - Sentry
  - Datadog only for multi-server/distributed systems
  - Playwright only when UI/browser verification is needed
  - Sequential Thinking only when the active model lacks strong built-in reasoning
- Must:
  1. Analyze the request.
  2. Map the affected system and dependencies.
  3. Write or update `ARCHITECTURE_CONTRACT.md`.
  4. Decompose work into scoped tasks.
  5. Assign tasks to leaf agents.
  6. Validate completion against contract and verifier output.
- Must not:
  - Delegate vague tasks.
  - Ask engineer to invent architecture.
  - Rely on chat history as the source of truth.

### @engineer
- Role: implementer.
- Writes code, tests, migrations, and mechanical refactors within assigned scope.
- Allowed MCP focus:
  - Serena
  - Context7
  - Superpowers
  - Sentry when debugging production-visible failures
  - Playwright only if explicitly required for UI work
- Must:
  1. Read `ARCHITECTURE_CONTRACT.md` before coding.
  2. Work only inside assigned scope.
  3. Follow TDD or at minimum add regression coverage for changed behavior.
  4. Run required validation via a **Local Proxy** (see `../no-mistakes/SKILL.md`) before reporting completion. Never push failing code.
  5. Use `BabysitState` (see `../babysit-prs/SKILL.md`) to track asynchronous CI test sweeps.
  6. Update checkpoint state before risky edits and before ending turn.
- Must not:
  - Change architecture without architect approval.
  - Modify unrelated files.
  - Report success without verification results.

### @reviewer
- Role: verifier, critic, QA gate.
- Audits implementation for correctness, architecture fit, regressions, edge cases, security, and completeness.
- Allowed MCP focus:
  - Serena
  - Superpowers
  - Playwright for UI verification
  - Sentry for error-driven validation
  - Datadog only for distributed systems
- Must:
  1. Operate as a **Swarm** of specialized sub-agents (see `../qa-swarm/SKILL.md`).
  2. Classify findings and calculate a deterministic verdict (Actionable, Nit, Ambiguous) via **Review Triage** (see `../review-triage/SKILL.md`).
  3. Obey the **Human Participation Gate**: Never auto-resolve or auto-reply to a thread authored by a human.
  4. Return concrete failure reasons and next actions using the Narration Protocol.
- Must not:
  - Approve based on agent claims alone.
  - Rewrite architecture unless explicitly tasked.
  - Loosen the Deterministic Safety Gates.

## Core Artifacts

The following artifacts are mandatory for non-trivial tasks:

- `task.md`: current task tree and status.
- `BUG_REGISTER.md`: known defects, deferred issues, risks.
- `ARCHITECTURE_CONTRACT.md`: scoped contract for the current task or workstream.
- `.agent-state/checkpoints/<agent_id>.json`: latest durable checkpoint.
- Optional:
  - `.agent-state/locks/`
  - `.agent-state/decisions/`
  - `.agent-state/risk/`

If these artifacts exist, agents must use them instead of relying on conversation memory. All cross-agent conversational memory and long-term state must be managed exclusively by the `omnigraph` MCP server to ensure a durable graph representation of the project's evolution.

## Orchestration Flow

1. Architect receives task.
2. Architect inspects repository and dependency context.
3. Architect creates or updates:
   - `task.md`
   - `BUG_REGISTER.md`
   - `ARCHITECTURE_CONTRACT.md`
4. Architect computes risk score.
5. Architect decides:
   - single engineer, or
   - Best-of-N engineers for high-risk work.
6. Engineer executes scoped work in isolated branch/worktree (validated via `../no-mistakes/SKILL.md`).
7. Engineer runs required verification and writes checkpoint.
8. **Deterministic Safety Gates** (`../pr-approval-agent/SKILL.md`): The orchestrator strictly checks diff size and deny-lists before reviewing. If failed -> Escalate immediately.
9. **Swarm Review** (`../qa-swarm/SKILL.md`): Parallel sub-agents audit the code.
10. **Triage & Verdict** (`../review-triage/SKILL.md`):
    - If `BLOCKED` or `REQUEST_CHANGES` -> return to Engineer (or escalate).
    - Engineer revises (max 3 loops).
11. If approved:
    - architect marks task complete.
    - cleanup runs after merge/acceptance.

## Risk Scoring

Use Best-of-N only when justified. Risk is calculated as a sum of the following weighted trigger signals:

Trigger signals & weights:
- touches more than 3 files (+0.15)
- modifies public API (+0.15)
- ambiguous acceptance criteria (+0.20)
- high-churn module (+0.10)
- architect confidence below threshold (+0.15)
- weak or missing test coverage (+0.10)
- concurrency or async change (+0.10)
- security-sensitive code (+0.20)
- prior review failure (+0.15)
- cross-module interface change (+0.10)
- estimate variance above 30pct (+0.10)

Default policy thresholds (based on sum of signals):
- **low risk (< 0.60)**: 1 engineer
- **medium risk (>= 0.60, < 0.85)**: 1 engineer + stronger reviewer gate
- **high risk (>= 0.85)**: Best-of-3
- **very high risk**: Best-of-5 only if verification can cheaply arbitrate

Never use Best-of-N as a default for all tasks.

### Best-of-N Execution
If executing a high-risk task without the custom Python scaffold, the Architect MUST manually execute the Best-of-N pattern:
1. Spawn N engineer sub-agents concurrently.
2. Provide them with identical prompts and architecture contracts.
3. Assign each a separate, isolated Git worktree or branch.
4. Wait for all N engineers to complete their implementation.
5. Run verification commands (tests, linters) on each isolated implementation.
6. Arbitrate the winning implementation based on verification results and contract adherence.

## Handoffs

Every architect-to-engineer handoff must include:
- task ID
- exact file or module scope
- objective
- acceptance criteria
- forbidden changes
- verification commands
- checkpoint location
- branch/worktree name
- relevant contract section references

Valid handoff example:
- Implement `normalize_events()` in `src/pipeline/events.py`
- Allowed files: `src/pipeline/events.py`, `tests/test_events.py`
- Must pass:
  - `pytest tests/test_events.py -q`
  - `ruff check src/pipeline/events.py tests/test_events.py`
  - `mypy src/pipeline/events.py`
- Must not:
  - change public API outside `normalize_events`
  - add dependencies
  - refactor unrelated modules

## Cache Control

Use cache-aware prompting only when supported by the model provider or client.

Cache only stable context:
- tool definitions
- role/system instructions
- repository invariants
- approved architecture contract
- stable workflow rules

Do not treat these as stable cache by default:
- terminal output
- transient errors
- exploratory notes
- raw logs
- partial diffs
- reviewer-specific rejection text unless intentionally reused

Rules:
1. Preserve wording and ordering of stable prompt blocks across turns.
2. Avoid adding or removing tools mid-task unless necessary.
3. If explicit cache control is supported, place breakpoints after:
   - tool definitions
   - role instructions
   - approved architecture contract
4. If caching is automatic, keep the stable prefix structurally unchanged.
5. Invalidate cached contract context when:
   - interfaces change
   - dependency constraints change
   - acceptance criteria change
   - allowed tool inventory changes in a way that affects execution

## Checkpointing

Checkpoint before:
- multi-file edits
- risky refactors
- long tool chains
- test or verification runs
- handoff completion
- ending a turn with unfinished work

Each checkpoint must contain:
- `agent_id`
- `task_id`
- `role`
- `branch`
- `worktree`
- `architecture_contract_hash`
- `files_touched`
- `last_completed_step`
- `next_step`
- `verification_status`
- `tokens_used`
- `risk_level`
- `unresolved_issues`
- `timestamp`

Checkpoint rules:
1. Checkpoint state is durable source of truth for in-progress work.
2. If the session restarts, load checkpoint before acting.
3. If worktree exists, continue there.
4. If worktree is missing but branch exists, recreate worktree and continue.
5. Never continue based only on conversational memory when checkpoint artifacts exist.

## Branches, Worktrees, and Locks

For non-trivial work:
- each engineer uses an isolated branch/worktree
- reviewer may use separate validation branch/worktree if needed
- shared-file edits require a lock file

Lock rules:
- acquire lock before editing contested files
- lock must have TTL
- stale locks may be reclaimed by architect
- release lock after commit, abort, or reassignment

Cleanup rules after approval:
- merge or apply accepted diff
- delete temporary branches if no longer needed
- remove worktrees
- remove locks
- archive or delete obsolete checkpoints

## Verification

Default Python verification:
- `pytest`
- `ruff check`
- `mypy`

For non-Python subprojects, the architect must specify exact alternatives in the contract.

Reviewer approval requires:
- contract alignment
- scope compliance
- verification success
- no unresolved blocking defects

## MCP Routing

Default MCP routing:

- Architect:
  - Graphify
  - Omnigraph
  - Context7
  - Superpowers
  - Sentry
  - Datadog only for distributed systems
- Engineer:
  - Serena
  - Context7
  - Superpowers
  - Sentry when debugging
- Reviewer:
  - Serena
  - Superpowers
  - Playwright when UI validation is required
  - Sentry
  - Datadog only for distributed systems

Guidance:
- Prefer Omnigraph over generic memory MCP for shared coding-state coordination.
- Use Playwright only for browser workflows.
- Use Sequential Thinking only when the active model lacks strong native reasoning.
- Do not load large flat skill catalogs into every agent by default.

## Skill Selection

Use a curated skill subset per role.
Do not expose a large undifferentiated skill library to all agents.

Allowed pattern:
- architect selects skill family
- engineer/reviewer receive only needed skills for current task
- load additional skills lazily

## Failure Policy

Replan instead of brute-forcing when:
- review loop fails 3 times
- risk increases during execution
- verification cost exceeds expected task value
- implementation diverges from architecture
- token use rises because the task was underspecified

Architect must then:
1. narrow scope
2. improve contract
3. split task further
4. switch model or workflow
5. retry only with revised constraints
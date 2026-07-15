---
name: repository-index
description: Central routing index for all MCP servers and agent skills. Start here.
---

# Agent Skills Repository Index

Welcome to the `agent-skills` repository. The core purpose of this repository is to provide **high-performance, efficient automation** through a deterministic, fail-closed multi-agent orchestration pipeline.

This file serves as the definitive routing map for any agent operating in this repository.

## 1. MCP Server Directory

| Server Name | Purpose | When to Use | Setup Notes |
| :--- | :--- | :--- | :--- |
| **`omnigraph`** | Persistent, structured memory graph | Preferred over generic Memory MCPs for sharing architectural state across the swarm. | Runs locally. Automatically syncs at start/end of sessions. |
| **`serena`** | Advanced code manipulation | When bulk refactoring, renaming, or precise AST manipulations are needed. | Requires language server context. |
| **`graphify`** | Codebase dependency graphing | When the Architect needs to understand cross-module blast radii. | None. |
| **`superpowers`** | Workflow extensions and internet access | When you need to search the web or execute non-standard environment scripts. | None. |
| **`sentry`** | Observability and crash reporting | Error-driven development or when debugging production-visible failures. | Requires Sentry SDK and valid DSN. |
| **`datadog`** | Distributed tracing and metrics | When debugging multi-server setups or cross-service latency/errors. | Only use for distributed systems. |
| **`playwright`** | Browser automation | Strictly for UI validation, screenshot testing, or E2E browser tasks. | Requires local browser binaries. |

## 2. Skills Directory

| Skill / Path | Source / Author | License | Purpose | Routing Trigger |
| :--- | :--- | :--- | :--- | :--- |
| `skills/swarm-orchestration` | Internal | - | The master orchestration pipeline defining Architect, Engineer, and Reviewer roles. | Any complex multi-file task, refactor, or feature request. |
| `skills/pr-approval-agent` | PostHog / StampHog | MIT | Deterministic safety gates (deny-list and size ceilings) before LLM review. | Automatically triggered by the orchestrator before `qa-swarm`. |
| `skills/qa-swarm` | Paul D'Ambra | MIT | Parallel sub-agent reviews (Security, Performance, XP) and convergence scoring. | Automatically triggered during the Reviewer phase. |
| `skills/review-triage` | Paul D'Ambra | MIT | Triage scoring, the Human Participation Gate, and dual-mode narration. | Automatically triggered after `qa-swarm` to format results. |
| `skills/no-mistakes` | Kun Chen | MIT | Local pre-push validation proxy loop to keep main branch clean. | Used by `@engineer` before declaring a task complete. |
| `skills/babysit-prs` | Phil Haack | MIT | Asynchronous state tracking for CI test runs and retry loops. | Used by `@engineer` to poll for CI test completion asynchronously. |

## 3. Routing Decision Tree

```text
[TASK RECEIVED]
       |
       +--> Is it a simple single-file tweak?
       |      ├── YES: Fix it directly.
       |      └── NO: Proceed to Orchestration.
       |
[ORCHESTRATION]
       |
       +--> Route to `skills/swarm-orchestration/SKILL.md` (@architect).
       |
       +--> Architect builds contract -> delegates to @engineer.
       |
[IMPLEMENTATION]
       |
       +--> Engineer writes code.
       |      └── Runs local proxy validation (`skills/no-mistakes/SKILL.md`).
       |
[REVIEW PHASE]
       |
       +--> Orchestrator runs Gates (`skills/pr-approval-agent/SKILL.md`).
       |      ├── FAIL (Size/Deny-List): Blocked! Escalate to Architect.
       |      └── PASS: Proceed.
       |
       +--> Swarm Review (`skills/qa-swarm/SKILL.md`).
              |
              +--> Triage Pipeline (`skills/review-triage/SKILL.md`).
                     ├── HUMAN PRESENT? -> Do NOT auto-reply.
                     ├── BLOCKED / REQUEST_CHANGES -> Return to Engineer.
                     └── APPROVE -> Merge.
```

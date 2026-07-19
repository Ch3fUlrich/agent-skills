---
name: repository-index
description: Central routing index for all MCP servers and agent skills. Start here — read this before deciding how to do anything else.
---

# Agent Skills Repository Index

**This is the map. Read it first.** Every other skill in this repository is reachable from
here, and a skill you do not know about is a skill you will not load — so an agent that skips
this file silently does the work the hard way: re-deriving conventions that are already
written down, reading whole files where a symbol lookup would do, and losing at session end
whatever it learned.

The repository exists to make agents **fast and consistent**. Two things deliver that, and
they are different:

- **Always-on discipline** (§2a) — load these for essentially any task. They are the baseline,
  not an escalation.
- **Triggered capability** (§2b, §2c) — load when the trigger fires, not before.

This file is the definitive routing map for any agent operating in — or borrowing from —
this repository.

## 1. MCP Server Directory

Which server answers which question. **Prefer these over raw file reads**: that is Principle 6
of `coding-principles`, and it is where most of the token savings live.

| Server Name | Purpose | When to Use | Setup Notes |
| :--- | :--- | :--- | :--- |
| **`omnigraph`** | Persistent, structured memory graph | Recall at session start, persist durable decisions at end. Preferred over generic Memory MCPs for sharing architectural state across the swarm. | **One graph per repo**, pinned by `OMNIGRAPH_GRAPH_ID`; no tool takes a graph argument. Needs `OMNIGRAPH_TOKEN`/`OMNIGRAPH_NET` exported or it fails **silently**. A timer reconciles local↔central every 5 min — agents never manage branches. Read `skills/structured-memory/references/operations.md` before any query/mutate/load. |
| **`serena`** | Semantic code navigation + editing (LSP) | Finding symbols, references, declarations; renaming/replacing symbols. **Default for code**, not a special case. | Activate the project first. Its *memory* tools are disabled — Omnigraph is the memory layer. |
| **`graphify`** | Codebase dependency graphing | Cross-module blast radius, "what connects X to Y" — broader than symbol level. | Needs `graphify-out/graph.json` to exist for the repo. |
| **`superpowers`** | Disciplined workflow skills (14) | `systematic-debugging` for any bug; `test-driven-development` before implementation; `brainstorming` before design; `verification-before-completion` before claiming done. **Not** a web-search tool. | None — available via the `Skill` tool, no MCP check needed. |
| **`context7`** | Up-to-date library/framework documentation | Any question about a library, framework, SDK, or CLI — *even one you think you know*. Training data goes stale; this does not. | None. Prefer over web search for library docs. |
| **`playwright`** | Browser automation | Strictly UI validation, screenshot testing, E2E browser tasks. | Requires local browser binaries. |
| **`sentry`** | Observability and crash reporting | Error-driven development; debugging production-visible failures. | Requires Sentry SDK and valid DSN. |
| **`datadog`** | Distributed tracing and metrics | Multi-server setups; cross-service latency/errors. | Only for distributed systems. |

Full wiring, ports and troubleshooting: `skills/mcp-servers-setup/SKILL.md`.

## 2a. Always-on skills — load these for almost any task

These are the ones agents most often miss, because nothing dramatic happens when they are
skipped: the work just comes out worse.

| Skill / Path | Purpose | Routing Trigger |
| :--- | :--- | :--- |
| `skills/coding-principles` | The engineering baseline: DRY, TDD, single responsibility, document-the-why, changelog/ADR backtracking, MCP-first navigation. | **Any** implementation, refactor, or bugfix. Not just big ones. |
| `skills/structured-memory` | Typed, cross-project memory on Omnigraph — recall at session start, persist durable decisions at end. | **Every session**, at both ends. Read `references/operations.md` before any query/mutate/load/sync. |
| `skills/mcp-servers-setup` | How to configure and actually use the stack above. | When a server misbehaves, is unregistered, or you are on a new machine. |

## 2b. Task-shaped skills

| Skill / Path | Purpose | Routing Trigger |
| :--- | :--- | :--- |
| `skills/html-working-documents` | Self-contained HTML artifacts for planning, research, review, diagrams, reports, prototypes, handoff. | The answer would exceed ~100 lines of markdown, or needs a diagram/table/interactive view. |
| `skills/homelab-access` | SSH aliases, the `claude-ops` key, per-host shell/user quirks, and what is deliberately unreachable. | **Before any command that touches a VM, the firewall, or the NAS** — including `DOCKER_HOST=ssh://`. Cheaper than rediscovering that `ping` is blocked or that OPNsense runs `csh`. |
| `skills/repository-index` | This file. | You are lost, new to the repo, or unsure which skill applies. |

## 2c. Orchestration & review skills

| Skill / Path | Source / Author | License | Purpose | Routing Trigger |
| :--- | :--- | :--- | :--- | :--- |
| `skills/swarm-orchestration` | Internal | - | The master orchestration pipeline defining Architect, Engineer, and Reviewer roles. | Any complex multi-file task, refactor, or feature request. |
| `skills/pr-approval-agent` | PostHog / StampHog | MIT | Deterministic safety gates (deny-list and size ceilings) before LLM review. | Automatically triggered by the orchestrator before `qa-swarm`. |
| `skills/qa-swarm` | Paul D'Ambra | MIT | Parallel sub-agent reviews (Security, Performance, XP) and convergence scoring. | Automatically triggered during the Reviewer phase. |
| `skills/review-triage` | Paul D'Ambra | MIT | Triage scoring, the Human Participation Gate, and dual-mode narration. | Automatically triggered after `qa-swarm` to format results. |
| `skills/no-mistakes` | Kun Chen | MIT | Local pre-push validation proxy loop to keep main branch clean. | Used by `@engineer` before declaring a task complete. |
| `skills/babysit-prs` | Phil Haack | MIT | Asynchronous state tracking for CI test runs and retry loops. | Used by `@engineer` to poll for CI test completion asynchronously. |
| `skills/herdr-orchestration` | Internal | - | Driving the Herdr socket API: spawn/observe/synchronize agents in **persistent** panes. | Work must outlive the session, a human supervises it, a **non-Claude** agent is needed, or you wait on a long-running process. **Not** a replacement for `Agent`/`Workflow` — see its §1. |

## 3. Routing Decision Tree

The always-on layer comes first and is **not** part of the size question — "small" changes
still get the memory, the discipline, and the semantic tools. Only *orchestration* scales
with size.

```text
[SESSION START]  — regardless of the task
       |
       +--> Recall memory        (`skills/structured-memory`, omnigraph)
       +--> Activate serena      (code nav is MCP-first, not Read/Grep)
       +--> Apply the baseline   (`skills/coding-principles`)
       |
[TASK RECEIVED]
       |
       +--> Bug / test failure / surprise?  -> `superpowers:systematic-debugging` FIRST
       +--> Library / framework question?   -> `context7` (even if you think you know)
       +--> Long-form plan, research, report, diagram?
       |                                    -> `skills/html-working-documents`
       |
       +--> Is it a simple single-file tweak?
       |      ├── YES: Fix it directly — still TDD, still document the why.
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
       |
[SESSION END]  — regardless of the task, and the easiest step to skip
       |
       +--> Verify before claiming done (`superpowers:verification-before-completion`)
       +--> PERSIST what is durable to omnigraph (`skills/structured-memory`):
            the Decision and its WHY, a Rule you were corrected into, a Convention you
            found. Not the diff — git already has that.
```

Recall without persist is a memory that only ever shrinks. If this session taught you
something the next agent would otherwise rediscover the hard way, write it down before you
finish.

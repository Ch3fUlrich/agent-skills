# Remote Access & Multi-Agent Operation

Two complementary tools for running agents you can walk away from and check on
remotely. They solve different problems — pick by what you need.

| Need | Use | Why |
|---|---|---|
| Run/persist **multiple agents**, reattach over SSH (incl. phone), agents coordinate | **[Herdr](herdr/)** | Purpose-built agent multiplexer; sessions survive detach/restart; socket API for agent-to-agent workflows. Supersedes raw tmux here. |
| **Stream the Antigravity IDE** chat UI to a phone browser | **[antigravity-remote-ui](antigravity-remote-ui/)** | Captures the Antigravity chat DOM over CDP and serves a mobile web UI + tunnel. Herdr can't do this — it's terminal, not IDE-DOM. |
| Bare terminal persistence, no agent-awareness | tmux/screen | Fine, but Herdr gives per-agent status and the socket API for free. |

## Herdr vs tmux (why the switch)

tmux persists terminals but treats every pane as opaque text. Herdr understands
that a pane is an **agent** — surfacing blocked/working/done state, and exposing a
socket API so agents can spawn panes and wait on each other. For a
multiple-coding-agents workflow that is the difference between "a wall of
terminals" and "an orchestration surface". Keyboard bindings are tmux-style
(`ctrl+b` prefix), so muscle memory carries over.

## Herdr vs antigravity-remote-ui (why keep both)

They don't overlap:

- **Herdr** = run agents in the terminal, reattach anywhere. Best for CLI agents
  (Claude Code, Codex, etc.) and long unattended runs.
- **antigravity-remote-ui** = mirror the *Antigravity desktop IDE's* chat to a
  phone. Best when your agent lives in that GUI IDE, not a terminal.

Start with Herdr for terminal/multi-agent work; reach for antigravity-remote-ui
only for the Antigravity-IDE-on-phone case.

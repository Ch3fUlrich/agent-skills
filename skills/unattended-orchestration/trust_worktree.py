r"""Pre-approve a git worktree so an unattended Claude Code session is not blocked.

WHY THIS EXISTS
---------------
A freshly created worktree is a directory Claude Code has never seen, so the
first session in it asks before it will do anything: *do you trust the files in
this folder?* and, when ``.mcp.json`` declares servers, *do you approve them?*
An interactive session answers once. A **background** session cannot: it goes
to the ``blocked`` state and stays there until somebody attaches. Measured on
the first real launch of ``run_handoff_sessions.ps1`` (2026-09-03): both lanes'
sessions went ``blocked`` within seconds, in two brand-new worktrees.

So the runner calls this from ``postWorktree`` before starting a session. It
records the worktree in ``~/.claude.json`` with the trust flags the main
checkout already carries, optionally enables named ``.mcp.json`` servers, and
copies the gitignored ``.claude/settings.local.json`` (MCP enablement, tokens)
into the worktree - which is exactly what an interactive session would have
after answering those prompts.

It is **idempotent** and **additive**: an entry that already exists is left
alone unless ``--force``, nothing else in the config is touched, and the file is
written atomically beside a one-per-day backup. It grants no permission a
session would not have had after the operator clicked "trust" once.

This file is part of the ``unattended-orchestration`` skill and carries no
repository-specific knowledge; reference it from ``postWorktree`` as
``'{{skillDir}}/trust_worktree.py'``.

Usage::

    python trust_worktree.py <worktree> [--repo <main checkout>] [--mcpjson NAME ...]
    python trust_worktree.py <worktree> --check      # report, change nothing
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
from datetime import date
from pathlib import Path

#: The flags a project entry carries once its trust dialog has been answered.
TRUST_FLAGS = {
    "hasTrustDialogAccepted": True,
    "hasCompletedProjectOnboarding": True,
}

#: Copied into the worktree when the main checkout has it. Gitignored in most
#: repositories, so a worktree never has it by construction.
LOCAL_SETTINGS = Path(".claude") / "settings.local.json"

#: Per-session bookkeeping that must not be inherited by a new entry.
VOLATILE_KEYS = ("history", "lastCost", "lastAPIDuration", "lastSessionId",
                 "lastSessionMetrics", "lastModelUsage", "lastDuration",
                 "lastToolDuration", "lastStartTime")


def config_path() -> Path:
    """``~/.claude.json`` - the user-scope config the trust flags live in."""
    return Path(os.environ.get("CLAUDE_CONFIG_PATH") or (Path.home() / ".claude.json"))


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def save(path: Path, data: dict) -> None:
    """Atomic write, with one backup per day kept beside it."""
    backup = path.with_suffix(f".bak-{date.today():%Y%m%d}")
    if not backup.exists():
        shutil.copy2(path, backup)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".claude-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(data, fh, indent=2)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def _find_entry(projects: dict, repo: Path) -> dict:
    """The main checkout's entry, whichever separator style it was stored under."""
    wanted = str(repo).replace("\\", "/").rstrip("/").lower()
    best: dict = {}
    for key, entry in projects.items():
        if str(key).replace("\\", "/").rstrip("/").lower() == wanted:
            # Prefer the entry that already carries the trust flag.
            if not best or (entry or {}).get("hasTrustDialogAccepted"):
                best = dict(entry or {})
    return best


def template(data: dict, repo: Path) -> dict:
    """The main checkout's entry as the shape a new one should have."""
    entry = _find_entry(data.get("projects") or {}, repo)
    for key in VOLATILE_KEYS:
        entry.pop(key, None)
    return entry


def trust(worktree: Path, repo: Path, *, mcpjson: list[str], force: bool = False,
          check: bool = False) -> tuple[bool, str]:
    """``(changed, message)`` - record ``worktree`` as trusted."""
    path = config_path()
    if not path.is_file():
        return False, f"no config at {path}"
    data = load(path)
    projects = data.setdefault("projects", {})
    key = str(worktree)
    entry = projects.get(key)
    already = bool(entry) and all(entry.get(k) == v for k, v in TRUST_FLAGS.items())
    enabled = list((entry or {}).get("enabledMcpjsonServers") or [])
    missing_mcp = [m for m in mcpjson if m not in enabled]
    if already and not missing_mcp and not force:
        return False, f"already trusted: {key}"
    if check:
        return False, f"WOULD trust: {key}" + (f" (+mcpjson {missing_mcp})" if missing_mcp else "")
    merged = template(data, repo)
    merged.update(entry or {})
    merged.update(TRUST_FLAGS)
    if mcpjson:
        merged["enabledMcpjsonServers"] = sorted(set(enabled) | set(mcpjson))
    projects[key] = merged
    save(path, data)
    return True, f"trusted: {key}" + (f" (mcpjson {sorted(set(enabled) | set(mcpjson))})" if mcpjson else "")


def copy_local_settings(worktree: Path, repo: Path, *, check: bool = False) -> str:
    """Copy the gitignored local settings into the worktree, if any."""
    src, dst = repo / LOCAL_SETTINGS, worktree / LOCAL_SETTINGS
    if not src.is_file():
        return f"no {LOCAL_SETTINGS} in the main checkout"
    if dst.is_file():
        return f"worktree already has {LOCAL_SETTINGS}"
    if check:
        return f"WOULD copy {src} -> {dst}"
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    return f"copied {LOCAL_SETTINGS} into the worktree"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    ap.add_argument("worktree", type=Path)
    ap.add_argument("--repo", type=Path, default=None,
                    help="the main checkout whose trust entry is the template "
                         "(default: the worktree's own git common dir parent)")
    ap.add_argument("--mcpjson", action="append", default=[],
                    help="a .mcp.json server name to enable for the worktree (repeatable)")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--check", action="store_true", help="report, change nothing")
    args = ap.parse_args(argv)

    worktree = args.worktree.resolve()
    if not worktree.is_dir():
        print(f"not a directory: {worktree}", file=sys.stderr)
        return 2
    repo = args.repo.resolve() if args.repo else _main_checkout(worktree)
    if repo is None:
        print("could not determine the main checkout; pass --repo", file=sys.stderr)
        return 2

    changed, msg = trust(worktree, repo, mcpjson=args.mcpjson, force=args.force, check=args.check)
    print(msg)
    print(copy_local_settings(worktree, repo, check=args.check))
    return 0


def _main_checkout(worktree: Path) -> Path | None:
    """The main checkout behind a linked worktree, or the worktree itself."""
    dot_git = worktree / ".git"
    if dot_git.is_dir():
        return worktree
    if not dot_git.is_file():
        return None
    pointer = dot_git.read_text(encoding="utf-8").strip()
    if not pointer.startswith("gitdir:"):
        return None
    gitdir = Path(pointer.split(":", 1)[1].strip())
    if not gitdir.is_absolute():
        gitdir = worktree / gitdir
    try:
        commondir = (gitdir / "commondir").read_text(encoding="utf-8").strip()
    except OSError:
        return None
    common = (gitdir / commondir).resolve()
    return common.parent if common.name == ".git" else None


if __name__ == "__main__":
    raise SystemExit(main())

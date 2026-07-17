#!/usr/bin/env python3
"""Safety regression tests for omnigraph_jsonl.py.

These guard the invariant whose absence cost central its graphs on 2026-07-17:

    AN EMPTY BODY IS NOT A CLEAN GRAPH.

A failed fetch — dead server, bad token, wrong graph, curl error — returns zero
records. When `verify` called that "clean (no duplicates)" and exited 0, a wiped
stack reported perfect health for every graph, and the operator (an agent) believed
it. Everything here exists to keep no-data failing loudly.

If you are tempted to make `verify` pass on empty input again: don't. Pass
`--allow-empty` at the call site where emptiness is genuinely expected.

Run:  python3 test_omnigraph_jsonl.py     (no dependencies; non-zero exit on failure)
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
JQ = os.path.join(HERE, "omnigraph_jsonl.py")

CLEAN = ('{"type":"Rule","data":{"slug":"r1","statement":"s"}}\n'
         '{"edge":"ConstrainsProject","from":"r1","to":"p"}\n')
DUPE = '{"edge":"X","from":"a","to":"b"}\n{"edge":"X","from":"a","to":"b"}\n'

CASES = []


def case(name):
    def deco(fn):
        CASES.append((name, fn))
        return fn
    return deco


def run(stdin, *args):
    p = subprocess.run([sys.executable, JQ, *args], input=stdin, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


@case("empty input must NOT verify clean (the 2026-07-17 data-loss trap)")
def t_empty():
    rc, _, err = run("", "verify")
    assert rc != 0, f"empty input exited {rc} — a failed fetch would read as success"
    assert "NO DATA" in err, f"expected a NO DATA refusal, got: {err!r}"


@case("whitespace-only input must NOT verify clean")
def t_blank():
    rc, _, err = run("\n\n", "verify")
    assert rc != 0, f"blank input exited {rc} — must not pass"


@case("a genuinely empty graph passes only when explicitly allowed")
def t_allow_empty():
    rc, _, err = run("", "verify", "--allow-empty")
    assert rc == 0, f"--allow-empty should pass, got {rc}: {err!r}"


@case("a real graph still verifies clean")
def t_clean():
    rc, _, err = run(CLEAN, "verify")
    assert rc == 0, f"clean data must pass, got {rc}: {err!r}"
    assert "clean (no duplicates)" in err, err


@case("duplicates are still detected")
def t_dupes():
    rc, _, err = run(DUPE, "verify")
    assert rc == 1, f"duplicates must exit 1, got {rc}"
    assert "DUPLICATES PRESENT" in err, err


@case("dedup still collapses duplicates (arg parsing intact)")
def t_dedup():
    rc, out, _ = run(DUPE, "dedup")
    lines = [ln for ln in out.splitlines() if ln.strip()]
    assert rc == 0 and len(lines) == 1, f"dedup broken: rc={rc} out={out!r}"


def main():
    failed = 0
    for name, fn in CASES:
        try:
            fn()
            print(f"  PASS  {name}")
        except AssertionError as exc:
            failed += 1
            print(f"  FAIL  {name}\n        {exc}")
    print(f"\n{len(CASES) - failed}/{len(CASES)} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

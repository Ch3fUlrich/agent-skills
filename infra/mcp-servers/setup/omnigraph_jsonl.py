#!/usr/bin/env python3
"""JSONL helpers for Omnigraph sync — guarantee NO node/edge duplicates.

Omnigraph nodes dedupe by @key (slug) on merge, but EDGES are not slug-keyed, so
a naive cross-store export -> load can duplicate edges. This utility dedupes and
verifies a graph export so the sync helpers can enforce "no duplicates after
merge" (see docs/REMOTE-SYNC-TEST-PLAN.md).

Record shapes (NDJSON):
  node: {"type":"<NodeType>","data":{"slug":"...", ...}}
  edge: {"edge":"<EdgeType>","from":"<slug>","to":"<slug>"}

Usage:
  cat graph.jsonl | python3 omnigraph_jsonl.py dedup  > clean.jsonl
  cat graph.jsonl | python3 omnigraph_jsonl.py verify        # exit 1 if duplicates
"""
import json
import sys


def node_key(rec):
    return ("node", rec.get("type"), (rec.get("data") or {}).get("slug"))


def edge_key(rec):
    return ("edge", rec.get("edge"), rec.get("from"), rec.get("to"))


def rec_key(rec):
    if "type" in rec:
        return node_key(rec)
    if "edge" in rec:
        return edge_key(rec)
    return ("other", json.dumps(rec, sort_keys=True))


def load(lines):
    out = []
    for ln in lines:
        ln = ln.strip()
        if ln:
            out.append((ln, json.loads(ln)))
    return out


def dedup(lines):
    # Nodes: keep LAST occurrence (most recent wins). Edges: keep one.
    seen = {}
    for ln, rec in load(lines):
        seen[rec_key(rec)] = ln
    return list(seen.values())


def verify(lines):
    counts = {}
    for _ln, rec in load(lines):
        k = rec_key(rec)
        counts[k] = counts.get(k, 0) + 1
    dup_nodes = [k for k, v in counts.items() if v > 1 and k[0] == "node"]
    dup_edges = [k for k, v in counts.items() if v > 1 and k[0] == "edge"]
    n_nodes = sum(v for k, v in counts.items() if k[0] == "node")
    n_edges = sum(v for k, v in counts.items() if k[0] == "edge")
    d_nodes = sum(1 for k in counts if k[0] == "node")
    d_edges = sum(1 for k in counts if k[0] == "edge")
    return n_nodes, d_nodes, n_edges, d_edges, dup_nodes, dup_edges


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "verify"
    lines = sys.stdin.readlines()
    if cmd == "dedup":
        for ln in dedup(lines):
            print(ln)
        return
    n_nodes, d_nodes, n_edges, d_edges, dup_nodes, dup_edges = verify(lines)
    sys.stderr.write(
        f"[verify] nodes={n_nodes} (distinct {d_nodes}) | edges={n_edges} (distinct {d_edges})\n"
    )
    if dup_nodes:
        sys.stderr.write(f"[verify] DUPLICATE NODES ({len(dup_nodes)}): {dup_nodes[:20]}\n")
    if dup_edges:
        sys.stderr.write(f"[verify] DUPLICATE EDGES ({len(dup_edges)}): {dup_edges[:20]}\n")
    if dup_nodes or dup_edges:
        sys.stderr.write("[verify] RESULT: DUPLICATES PRESENT\n")
        sys.exit(1)
    sys.stderr.write("[verify] RESULT: clean (no duplicates)\n")


if __name__ == "__main__":
    main()

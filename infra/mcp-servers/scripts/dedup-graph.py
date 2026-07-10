#!/usr/bin/env python3
"""Deduplicate the Omnigraph `memory` graph and re-integrate it cleanly.

Omnigraph merges nodes by @key (slug): two branches/devices that use the SAME
slug are merged automatically. But when the same thing ends up under DIFFERENT
slugs — most commonly a case variant like `Invest` vs `invest`, or slug drift —
Omnigraph keeps both. This script collapses those duplicates:

  * groups nodes by (type, casefold(slug))  [add --by-name for (type, label) too]
  * picks a canonical slug per group (lowercase preferred, else richest, else min)
  * redirects every edge from a duplicate to the canonical, de-dups edges
  * merges node fields (canonical wins; missing filled from duplicates)
  * preserves Decision embeddings as-is (dedup does not change decision content)

It is **idempotent and cheap when clean**: if no duplicates are found it exits 0
without touching the running graph — safe to run after every sync/merge. Only
when duplicates exist does it rebuild (reset the store + `load --mode overwrite`
the cleaned graph — the one write path that is reliable on omnigraph-server
v0.8.1). A pre-change NDJSON backup is always written.

Run manually, or wire it into setup/omnigraph-sync.sh after a branch merge.

Examples:
  python scripts/dedup-graph.py --dry-run          # report duplicates only
  python scripts/dedup-graph.py                    # dedup + rebuild if needed
  python scripts/dedup-graph.py --map Invest=invest # force a specific merge
"""
import argparse
import json
import os
import subprocess
import sys
import time
from collections import defaultdict

LABEL = {"Project": "name", "Decision": "title", "Rule": "statement",
         "Preference": "statement", "Convention": "name", "Component": "name", "Task": "title"}


def sh(cmd, **kw):
    return subprocess.run(cmd, **kw)


def cli(args, network, image, token, stdin=None, capture=True):
    """Run the omnigraph CLI in a throwaway container against the server."""
    base = ["docker", "run", "--rm", "-i", "--network", network,
            "-e", f"OMNIGRAPH_BEARER_TOKEN={token}", "-e", "HOME=/tmp", "-w", "/tmp",
            "--entrypoint", "sh", image, "-c",
            'mkdir -p /tmp/.omnigraph; printf "servers:\\n  local:\\n    url: %s\\n" "$OG" >/tmp/.omnigraph/config.yaml; ' + args]
    env = dict(os.environ)
    return subprocess.run(base, input=stdin, capture_output=capture, text=True,
                          env={**env})


def export_graph(server, network, image, token):
    r = subprocess.run(
        ["docker", "run", "--rm", "-i", "--network", network,
         "-e", f"OMNIGRAPH_BEARER_TOKEN={token}", "-e", f"OG={server}", "-e", "HOME=/tmp", "-w", "/tmp",
         "--entrypoint", "sh", image, "-c",
         'mkdir -p /tmp/.omnigraph; printf "servers:\\n  local:\\n    url: %s\\n" "$OG">/tmp/.omnigraph/config.yaml; '
         f'omnigraph export --server local --graph memory 2>/dev/null'],
        capture_output=True, text=True)
    recs = []
    for line in r.stdout.splitlines():
        line = line.strip()
        if line and not line.startswith("warning") and (line[0] == "{"):
            try:
                recs.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return recs


def find_dupes(nodes, by_name):
    groups = defaultdict(list)
    for n in nodes:
        groups[(n["type"], n["data"]["slug"].casefold())].append(n)
        if by_name:
            lab = n["data"].get(LABEL.get(n["type"], ""), "")
            if lab:
                groups[(n["type"], "name:" + lab.casefold())].append(n)
    # unique groups with >1 distinct slug
    out = []
    seen = set()
    for members in groups.values():
        slugs = sorted({m["data"]["slug"] for m in members})
        if len(slugs) > 1 and tuple(slugs) not in seen:
            seen.add(tuple(slugs))
            out.append(members)
    return out


def canonical(members, forced):
    slugs = {m["data"]["slug"] for m in members}
    for s in slugs:
        if forced.get(s):
            return forced[s]
    lower = sorted(s for s in slugs if s == s.lower())
    if lower:
        return lower[0]
    richest = max(members, key=lambda m: len(m["data"]))
    return richest["data"]["slug"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default="http://omnigraph-server:8080")
    ap.add_argument("--network", default="mcp-servers_default")
    ap.add_argument("--image", default="modernrelay/omnigraph-server:v0.8.1")
    ap.add_argument("--token-file", default="/home/s/code/Server/server/coding/mcp-servers/.env")
    ap.add_argument("--compose-file", default="/home/s/code/Server/server/coding/mcp-servers/docker-compose.yml")
    ap.add_argument("--minio-volume", default="mcp-servers_omnigraph_minio")
    ap.add_argument("--backup-dir", default=os.path.join(os.path.dirname(__file__), "..", ".graph-backup"))
    ap.add_argument("--by-name", action="store_true", help="also treat same-type same-label nodes as duplicates")
    ap.add_argument("--map", action="append", default=[], help="force a merge, e.g. --map Invest=invest")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    token = os.environ.get("OMNIGRAPH_TOKEN")
    if not token and os.path.exists(a.token_file):
        for line in open(a.token_file):
            if line.startswith("OMNIGRAPH_TOKEN="):
                token = line.split("=", 1)[1].strip()
    if not token:
        sys.exit("no OMNIGRAPH_TOKEN (env or --token-file)")
    forced = dict(kv.split("=", 1) for kv in a.map)

    recs = export_graph(a.server, a.network, a.image, token)
    nodes = [r for r in recs if "type" in r]
    edges = [r for r in recs if "edge" in r]
    dupes = find_dupes(nodes, a.by_name)
    # Duplicate EDGES: edges are not slug-keyed, so a cross-store export->load (e.g. a
    # device-branch merge, or reconciling two clients) APPENDS them -> duplicates. The
    # GQ API cannot delete an individual edge (edges have no queryable `id`, and
    # `where from=.. and to=..` does not parse), so the only fix is this
    # export->dedup->rebuild path. Trigger the rebuild on edge dups too, not just nodes.
    eseen = set()
    edge_dupes = 0
    for e in edges:
        k = (e["edge"], e["from"], e["to"])
        edge_dupes += 1 if k in eseen else 0
        eseen.add(k)

    if not dupes and not edge_dupes:
        print("[dedup] no duplicates — graph is clean, nothing to do.")
        return

    slug_map = {}
    if dupes:
        print("[dedup] duplicate node groups:")
        for members in dupes:
            canon = canonical(members, forced)
            for m in members:
                s = m["data"]["slug"]
                if s != canon:
                    slug_map[s] = canon
            print(f"  {members[0]['type']}: {sorted({m['data']['slug'] for m in members})} -> {canon}")
    if edge_dupes:
        print(f"[dedup] {edge_dupes} duplicate edge(s) to collapse "
              "(rebuild de-dupes by (type,from,to)).")
    if a.dry_run:
        print("[dedup] --dry-run: would remap", slug_map, f"+ drop {edge_dupes} dup edges")
        return

    os.makedirs(a.backup_dir, exist_ok=True)
    bk = os.path.join(a.backup_dir, f"pre-dedup-{time.strftime('%Y%m%d-%H%M%S')}.jsonl")
    with open(bk, "w", encoding="utf-8") as f:
        for r in recs:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"[dedup] backup -> {bk}")

    # merge node fields into the canonical, drop the duplicates
    merged = {}
    for n in nodes:
        s = n["data"]["slug"]
        canon = slug_map.get(s, s)
        d = {k: v for k, v in n["data"].items() if k != "id"}
        d["slug"] = canon
        if canon in merged:
            for k, v in d.items():
                merged[canon]["data"].setdefault(k, v)
        else:
            merged[canon] = {"type": n["type"], "data": d}
    # redirect + dedupe edges, drop self-loops
    seen, out_edges = set(), []
    for e in edges:
        fr, to = slug_map.get(e["from"], e["from"]), slug_map.get(e["to"], e["to"])
        if fr == to:
            continue
        k = (e["edge"], fr, to)
        if k in seen:
            continue
        seen.add(k)
        out_edges.append({"edge": e["edge"], "from": fr, "to": to})

    clean = os.path.join(a.backup_dir, "dedup-clean.jsonl")
    with open(clean, "w", encoding="utf-8") as f:
        for v in merged.values():
            f.write(json.dumps(v, ensure_ascii=False) + "\n")
        for e in out_edges:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
    print(f"[dedup] cleaned graph: {len(merged)} nodes, {len(out_edges)} edges -> {clean}")

    # rebuild: reset the store (overwrite is unreliable on a populated v0.8.1 graph) then overwrite-load
    print("[dedup] resetting store + overwrite-loading cleaned graph...")
    dc = ["docker", "compose", "-f", a.compose_file]
    sh(dc + ["rm", "-sf", "omnigraph-server", "omnigraph-viewer", "omnigraph-minio",
             "omnigraph-init", "omnigraph-minio-init"], capture_output=True)
    sh(["docker", "volume", "rm", a.minio_volume], capture_output=True)
    sh(dc + ["up", "-d", "omnigraph-minio", "omnigraph-minio-init", "omnigraph-init",
             "omnigraph-server", "omnigraph-viewer"], capture_output=True)
    # wait for health
    for _ in range(30):
        h = sh(dc + ["ps", "omnigraph-server", "--format", "{{.Status}}"], capture_output=True, text=True)
        if "healthy" in h.stdout:
            break
        time.sleep(2)
    data = open(clean, "rb").read()
    r = subprocess.run(
        ["docker", "run", "--rm", "-i", "--network", a.network,
         "-e", f"OMNIGRAPH_BEARER_TOKEN={token}", "-e", f"OG={a.server}", "-e", "HOME=/tmp", "-w", "/tmp",
         "--entrypoint", "sh", a.image, "-c",
         'mkdir -p /tmp/.omnigraph; printf "servers:\\n  local:\\n    url: %s\\n" "$OG">/tmp/.omnigraph/config.yaml; '
         'cat > /tmp/c.jsonl; omnigraph load --server local --graph memory --data /tmp/c.jsonl --mode overwrite --yes --json'],
        input=data, capture_output=True)
    print(r.stdout.decode()[-400:])
    if r.returncode != 0:
        sys.exit(f"[dedup] overwrite failed; restore from {bk} via mc mirror. stderr:\n{r.stderr.decode()[-400:]}")
    print("[dedup] done. Verify with a query / search_decisions.")


if __name__ == "__main__":
    main()

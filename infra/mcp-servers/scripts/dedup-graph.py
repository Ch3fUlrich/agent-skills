#!/usr/bin/env python3
"""Deduplicate every Omnigraph graph (or --graphs/GRAPHS subset) and re-integrate cleanly.

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


def list_graphs(server, network, image, token):
    """Discover every graph the server exposes (GET /graphs) from a throwaway container."""
    r = subprocess.run(
        ["docker", "run", "--rm", "--network", network, "-e", f"OG={server}",
         "--entrypoint", "sh", image, "-c",
         'curl -s "$OG/graphs" -H "Authorization: Bearer ' + token + '"'],
        capture_output=True, text=True)
    import re
    return re.findall(r'"graph_id":"([^"]+)"', r.stdout)


def export_graph(server, network, image, token, graph="memory"):
    r = subprocess.run(
        ["docker", "run", "--rm", "-i", "--network", network,
         "-e", f"OMNIGRAPH_BEARER_TOKEN={token}", "-e", f"OG={server}", "-e", "HOME=/tmp", "-w", "/tmp",
         "--entrypoint", "sh", image, "-c",
         'mkdir -p /tmp/.omnigraph; printf "servers:\\n  local:\\n    url: %s\\n" "$OG">/tmp/.omnigraph/config.yaml; '
         f'omnigraph export --server local --graph {graph} 2>/dev/null'],
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


def clean_records(nodes, edges, dupes, forced):
    """Collapse duplicate nodes into their canonical slug + de-dupe/redirect edges.
    Returns (merged_nodes_by_slug, out_edges, edge_dupes_dropped)."""
    slug_map = {}
    for members in dupes:
        canon = canonical(members, forced)
        for m in members:
            s = m["data"]["slug"]
            if s != canon:
                slug_map[s] = canon
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
    seen, out_edges, edge_dupes = set(), [], 0
    for e in edges:
        fr, to = slug_map.get(e["from"], e["from"]), slug_map.get(e["to"], e["to"])
        if fr == to:
            continue
        k = (e["edge"], fr, to)
        if k in seen:
            edge_dupes += 1
            continue
        seen.add(k)
        out_edges.append({"edge": e["edge"], "from": fr, "to": to})
    return merged, out_edges, edge_dupes


def node_count(a, token, graph="memory"):
    """Total node rows in the graph (via snapshot). -1 on failure."""
    r = subprocess.run(
        ["docker", "run", "--rm", "-i", "--network", a.network,
         "-e", f"OMNIGRAPH_BEARER_TOKEN={token}", "-e", f"OG={a.server}", "-e", "HOME=/tmp", "-w", "/tmp",
         "--entrypoint", "sh", a.image, "-c",
         'mkdir -p /tmp/.omnigraph; printf "servers:\\n  local:\\n    url: %s\\n" "$OG">/tmp/.omnigraph/config.yaml; '
         f'omnigraph snapshot --server local --graph {graph} 2>/dev/null'],
        capture_output=True, text=True)
    try:
        d = json.loads(r.stdout[r.stdout.index("{"):])
        return sum(t["rowCount"] for t in d.get("tables", []) if t["tableKey"].startswith("node"))
    except Exception:  # noqa: BLE001
        return -1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default="http://omnigraph-server:8080")
    ap.add_argument("--network", default="mcp-server_mcp-net")
    ap.add_argument("--image", default="modernrelay/omnigraph-server:v0.8.1")
    ap.add_argument("--token-file", default="/home/s/code/Server/server/coding/mcp-servers/.env")
    ap.add_argument("--compose-file", default="/home/s/code/Server/server/coding/mcp-servers/docker-compose.yml")
    ap.add_argument("--minio-volume", default="mcp-servers_omnigraph_minio")
    ap.add_argument("--minio-path", default=os.environ.get("MINIO_PATH", ""),
                    help="bind-mount data dir to clear on reset (e.g. /home/s/apps/omnigraph/minio); "
                         "overrides --minio-volume when the store is a bind mount, not a named volume")
    ap.add_argument("--backup-dir", default=os.path.join(os.path.dirname(__file__), "..", ".graph-backup"))
    ap.add_argument("--by-name", action="store_true", help="also treat same-type same-label nodes as duplicates")
    ap.add_argument("--map", action="append", default=[], help="force a merge, e.g. --map Invest=invest")
    ap.add_argument("--graphs", default=os.environ.get("GRAPHS", ""),
                    help="comma-separated graphs to dedup (default: all graphs the server exposes)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    a.graphs = [g.strip() for g in a.graphs.split(",") if g.strip()]

    token = os.environ.get("OMNIGRAPH_TOKEN")
    if not token and os.path.exists(a.token_file):
        for line in open(a.token_file):
            if line.startswith("OMNIGRAPH_TOKEN="):
                token = line.split("=", 1)[1].strip()
    if not token:
        sys.exit("no OMNIGRAPH_TOKEN (env or --token-file)")
    forced = dict(kv.split("=", 1) for kv in a.map)

    graphs = a.graphs or list_graphs(a.server, a.network, a.image, token)
    if not graphs:
        sys.exit("[dedup] could not discover any graphs (GET /graphs) — pass --graphs or set GRAPHS=")
    print(f"[dedup] graphs: {graphs}")

    # 1. Export + clean EVERY graph up front. The rebuild resets the whole MinIO
    #    volume (overwrite is unreliable on a populated v0.8.1 graph), which wipes
    #    all graphs — so every graph must be reloaded afterward, even clean ones.
    ts = time.strftime("%Y%m%d-%H%M%S")
    os.makedirs(a.backup_dir, exist_ok=True)
    plan = {}
    for g in graphs:
        recs = export_graph(a.server, a.network, a.image, token, g)
        nodes = [r for r in recs if "type" in r]
        edges = [r for r in recs if "edge" in r]
        dupes = find_dupes(nodes, a.by_name)
        merged, out_edges, edge_dupes = clean_records(nodes, edges, dupes, forced)
        dirty = bool(dupes or edge_dupes)
        plan[g] = dict(recs=recs, merged=merged, out_edges=out_edges,
                       dupes=dupes, edge_dupes=edge_dupes, dirty=dirty)
        print(f"[dedup]   {g}: {len(nodes)} nodes, {len(edges)} edges — "
              + (f"{len(dupes)} node-dup group(s), {edge_dupes} dup edge(s)" if dirty else "clean"))

    if not any(p["dirty"] for p in plan.values()):
        print("[dedup] no duplicates in any graph — nothing to do.")
        return
    if a.dry_run:
        for g, p in plan.items():
            if p["dirty"]:
                print(f"[dedup] --dry-run {g}: collapse {len(p['dupes'])} node group(s) + drop {p['edge_dupes']} edge(s)")
        return

    # 2. Back up every graph + write its cleaned jsonl (so the reset is recoverable).
    cleans = {}
    for g, p in plan.items():
        bk = os.path.join(a.backup_dir, f"pre-dedup-{g}-{ts}.jsonl")
        with open(bk, "w", encoding="utf-8") as f:
            for r in p["recs"]:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        cf = os.path.join(a.backup_dir, f"dedup-clean-{g}-{ts}.jsonl")
        with open(cf, "w", encoding="utf-8") as f:
            for v in p["merged"].values():
                f.write(json.dumps(v, ensure_ascii=False) + "\n")
            for e in p["out_edges"]:
                f.write(json.dumps(e, ensure_ascii=False) + "\n")
        cleans[g] = cf
    print(f"[dedup] backups + cleaned files under {a.backup_dir} (ts {ts})")

    # 3. Reset the store ONCE (wipes ALL graphs; every graph is reloaded in step 4).
    print("[dedup] resetting store (wipes ALL graphs; each is reloaded below)...")
    dc = ["docker", "compose", "-f", a.compose_file]
    svcs = ["omnigraph-server", "omnigraph-viewer", "omnigraph-minio",
            "omnigraph-init", "omnigraph-minio-init"]
    sh(dc + ["stop"] + svcs, capture_output=True)
    sh(dc + ["rm", "-f"] + svcs, capture_output=True)
    if a.minio_path:
        # Bind-mount store (e.g. central's NVMe $APPS_ROOT/omnigraph/minio): clear the
        # directory in a root container (files are root-owned) — a named-volume rm is a
        # no-op here and would leave the data, tripping the empty-guard below.
        sh(["docker", "run", "--rm", "-v", f"{a.minio_path}:/data", "alpine",
            "sh", "-c", "rm -rf /data/* /data/.minio.sys 2>/dev/null; true"], capture_output=True)
        left = sh(["docker", "run", "--rm", "-v", f"{a.minio_path}:/data", "alpine",
                   "sh", "-c", "ls -A /data | head"], capture_output=True, text=True).stdout.strip()
        if left:
            sys.exit(f"[dedup] ABORT: could not clear bind-mount {a.minio_path} (still: {left}); graphs untouched. backups under {a.backup_dir}")
    else:
        for c in sh(["docker", "ps", "-aq", "--filter", f"volume={a.minio_volume}"],
                    capture_output=True, text=True).stdout.split():
            sh(["docker", "rm", "-f", c], capture_output=True)
        sh(["docker", "volume", "rm", a.minio_volume], capture_output=True)
        vols = sh(["docker", "volume", "ls", "--format", "{{.Name}}"], capture_output=True, text=True).stdout.split()
        if a.minio_volume in vols:
            sys.exit(f"[dedup] ABORT: could not remove volume {a.minio_volume}; graphs untouched. backups under {a.backup_dir}")

    sh(dc + ["up", "-d"] + list(reversed(svcs)), capture_output=True)
    for _ in range(45):
        h = sh(dc + ["ps", "omnigraph-server", "--format", "{{.Status}}"], capture_output=True, text=True)
        if "healthy" in h.stdout:
            break
        time.sleep(2)

    # 4. Reload every graph's cleaned data into the fresh (empty) store.
    for g, p in plan.items():
        # GUARD: never overwrite a non-empty graph (that is what silently accumulated
        # nodes on v0.8.1 when a wipe failed). Abort unless the fresh graph is empty.
        empty = node_count(a, token, g)
        if empty > 0:
            sys.exit(f"[dedup] ABORT: fresh graph {g} not empty ({empty} nodes) — not loading, "
                     f"to avoid duplication. backups under {a.backup_dir}")
        data = open(cleans[g], "rb").read()
        r = subprocess.run(
            ["docker", "run", "--rm", "-i", "--network", a.network,
             "-e", f"OMNIGRAPH_BEARER_TOKEN={token}", "-e", f"OG={a.server}", "-e", "HOME=/tmp", "-w", "/tmp",
             "--entrypoint", "sh", a.image, "-c",
             'mkdir -p /tmp/.omnigraph; printf "servers:\\n  local:\\n    url: %s\\n" "$OG">/tmp/.omnigraph/config.yaml; '
             f'cat > /tmp/c.jsonl; omnigraph load --server local --graph {g} --data /tmp/c.jsonl --mode overwrite --yes --json'],
            input=data, capture_output=True)
        if r.returncode != 0:
            sys.exit(f"[dedup] {g} overwrite failed; restore from {a.backup_dir}. stderr:\n{r.stderr.decode()[-400:]}")
        got, want = node_count(a, token, g), len(p["merged"])
        print(f"[dedup]   {g}: {got} nodes" + ("" if got == want else f"  !! expected {want} — inspect drift"))
    print("[dedup] done — all graphs deduped + reloaded.")


if __name__ == "__main__":
    main()

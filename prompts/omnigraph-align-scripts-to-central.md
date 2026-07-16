# Prompt — align the Omnigraph helper scripts to CENTRAL (coding.vm)

Send this to an agent **with shell + docker access on `coding.vm`** (the host running
the authoritative Omnigraph instance behind `omnigraph.ohje.ooguy.com`).

Copy everything below the line.

---

You are on **`coding.vm`**. The Omnigraph helper scripts in the `agent-skills` repo
(`infra/mcp-servers/scripts/apply-cluster.sh`, `dedup-graph.py`, `split-project-graph.py`,
`add-project-graph.sh`) were tuned against a **local** stack, so their defaults don't match
this host's **central** deployment. Central boots from
`Server/server/coding/mcp-servers/docker-compose.yml` (compose project `mcp-servers`,
Dockhand-managed), **not** `agent-skills`'s `docker-compose.server.yml`.

## First, verify against the LIVE stack (don't trust these values blindly)

```bash
docker inspect omnigraph-server --format '{{range $n,$_ := .NetworkSettings.Networks}}{{$n}} {{end}}'   # real docker network
docker inspect omnigraph-minio  --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'  # MinIO store: bind vs volume
```
Expected (2026-07-16): network **`mcp-servers_default`**, MinIO **bind mount**
`/home/s/apps/omnigraph/minio` (`$APPS_ROOT/omnigraph/minio`), viewer bound `0.0.0.0:8090`.

## The mismatches and the exact overrides

| Script | Local default | Central override |
|---|---|---|
| `apply-cluster.sh` | `OMNI_NET=mcp-server_mcp-net` | `OMNI_NET=mcp-servers_default ./scripts/apply-cluster.sh` (its `OMNI_S3=http://omnigraph-minio:9000` already matches central) |
| `dedup-graph.py` | `--network mcp-server_mcp-net`, `--minio-volume mcp-servers_omnigraph_minio` | `--network mcp-servers_default --minio-path /home/s/apps/omnigraph/minio` (a `docker volume rm` is a no-op on a bind mount) |
| `split-project-graph.py` | `--net mcp-server_mcp-net` | `--net mcp-servers_default` |

`apply-cluster.sh` sources `.env.shared` + `.env.server` — make those resolve to
**central's** `OMNIGRAPH_TOKEN` / MinIO creds (they live in
`Server/server/coding/mcp-servers/.env`), or `export OMNIGRAPH_TOKEN=…` first.
`dedup-graph.py` already defaults `--token-file`/`--compose-file` to central's `.env`/compose.

**Don't confuse** `OMNIGRAPH_GRAPH_ID` (the MCP **bridge**'s graph) with `OMNIGRAPH_GRAPH`
(the **viewer** app's variable).

## Do one of

- **(a)** Run the scripts with the overrides above for a one-off, **or**
- **(b)** Change the script defaults to auto-detect central — derive the network from
  `docker inspect omnigraph-server`, and the MinIO mount type/path from
  `docker inspect omnigraph-minio` — falling back to the local values when off-host.
  Keep local runs working.

If you change any default, **update the scripts *and*** the "Central vs local: script
defaults & mismatches" section in `infra/mcp-servers/README.md` to match, then commit.
If you only run with overrides, say so and change nothing.

## Report back
- The live network + MinIO mount you observed from `docker inspect`.
- Which option (a/b) you took and the exact commands/flags used.
- Any script/README edits, or confirmation you changed only the run invocation.

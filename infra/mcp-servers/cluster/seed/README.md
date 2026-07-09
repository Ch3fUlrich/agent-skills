# Initial memory seed

Bootstrap `Project`/`Decision`/`Rule`/`Preference`/`Convention`/`Component`
nodes for the `memory` graph, derived from each repo's ADRs, README, and docs.
Idempotent by `slug` — load with `merge`:

```bash
OMNIGRAPH_BEARER_TOKEN=$OMNIGRAPH_TOKEN omnigraph load \
  --server <url> --graph memory --data agent-skills.jsonl --mode merge --yes
```

Format: NDJSON, `{"type":"NodeType","data":{...}}` and
`{"edge":"EdgeType","from":"<slug>","to":"<slug>"}`. See
../../../../skills/structured-memory/references/schema.md.

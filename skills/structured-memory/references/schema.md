# Structured Memory Schema (Omnigraph)

The memory graph is **typed**. Instead of storing unstructured conversation blobs
(Mem0's model), agents write specific node types with explicit edges, so memory
is queryable, reviewable, and stays "rules-integrated". One shared graph holds
all projects; each project is a `Project` node and everything project-specific
edges back to it. Global, cross-project facts edge to the root `Preference`
scope instead.

## Node types

| Type | Holds | Key fields |
|---|---|---|
| `Project` | One repository / workstream | `slug`, `name`, `path`, `summary` |
| `Decision` | A choice that was made and why | `slug`, `title`, `rationale`, `status`, `date` |
| `Rule` | A hard constraint agents must follow | `slug`, `statement`, `severity` |
| `Preference` | A soft, overridable inclination (often global) | `slug`, `statement`, `scope` |
| `Convention` | A repeatable pattern/way-of-doing | `slug`, `name`, `example` |
| `Component` | A notable part of a system | `slug`, `name`, `kind`, `location` |
| `Task` | Ongoing/planned work worth remembering | `slug`, `title`, `state` |

`status` for `Decision`: `proposed | accepted | superseded | deprecated`.
`severity` for `Rule`: `must | should`.
`scope` for `Preference`: `global | <project-slug>`.

## Edge types

| Edge | From → To | Meaning |
|---|---|---|
| `decided-in` | `Decision` → `Project` | decision belongs to a project |
| `constrains` | `Rule` → `Project`/`Component` | rule applies to target |
| `applies-to` | `Convention`/`Preference` → `Project`/`Component` | pattern/pref applies |
| `part-of` | `Component` → `Project` | component belongs to project |
| `supersedes` | `Decision` → `Decision` | replaces an earlier decision |
| `relates-to` | any → any | loose association |

## Schema declaration (Omnigraph `.pg`-style)

```pg
node Project     { slug: id!, name: string, path: string, summary: text }
node Decision    { slug: id!, title: string, rationale: text, status: string, date: string }
node Rule        { slug: id!, statement: text, severity: string }
node Preference  { slug: id!, statement: text, scope: string }
node Convention  { slug: id!, name: string, example: text }
node Component   { slug: id!, name: string, kind: string, location: string }
node Task        { slug: id!, title: string, state: string }

edge decided-in  (Decision  -> Project)
edge constrains  (Rule      -> Project | Component)
edge applies-to  (Convention | Preference -> Project | Component)
edge part-of     (Component  -> Project)
edge supersedes  (Decision   -> Decision)
edge relates-to  (any -> any)
```

## JSONL ingest example

The MCP `ingest` tool accepts newline-delimited records. Nodes carry `type` +
`data`; edges carry `edge` + `from`/`to` by `slug`.

```jsonl
{"type":"Project","data":{"slug":"agent-skills","name":"Agent Skills","path":"~/code/agent-skills","summary":"Reusable agent skills + self-hosted MCP stack"}}
{"type":"Decision","data":{"slug":"omnigraph-over-mem0","title":"Omnigraph replaces Mem0 as default memory","rationale":"Typed, queryable, reviewable memory keeps rules integrated; Mem0 kept as fallback","status":"accepted","date":"2026-07-09"}}
{"edge":"decided-in","from":"omnigraph-over-mem0","to":"agent-skills"}
{"type":"Rule","data":{"slug":"skill-single-source","statement":"A skill's SKILL.md is the source of truth; starters/instructions are thin pointers","severity":"must"}}
{"edge":"constrains","from":"skill-single-source","to":"agent-skills"}
{"type":"Preference","data":{"slug":"mcp-first-nav","statement":"Prefer Serena/Graphify/Omnigraph over brute-force file reads","scope":"global"}}
```

## Slug conventions

- `Project.slug` = repository folder name (e.g. `agent-skills`, `homelab-server`).
- Other slugs are kebab-case and unique within their project scope.
- Prefer stable, human-readable slugs so edges stay legible and re-ingest is
  idempotent (re-writing the same slug updates rather than duplicates).

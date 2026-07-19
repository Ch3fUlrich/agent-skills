#!/usr/bin/env bash
# MCP Server Stack — Graphify Scope Check (Linux)
# ============================================================================
# Graphify is REPO-BOUND: the server resolves graphify-out/graph.json relative
# to its bind mount, so one server serves exactly one repo. Three gates must
# all be open, and NONE of them errors when shut:
#
#   1. project-scoped server in <repo>/.mcp.json mounting THAT repo
#        missed -> another repo's graph answers for yours, silently
#   2. approval in <repo>/.claude/settings.local.json enabledMcpjsonServers
#        missed -> tool simply absent; no prompt, no error
#   3. a built graph at <repo>/graphify-out/graph.json
#        missed -> server starts and serves nothing
#
# Plus two traps this script also catches:
#   - graphify-docker/omnigraph in USER scope (~/.claude.json): one global
#     entry serves one repo's data to every repo (the 2026-07-19 bug)
#   - root-owned graphify-out: the container runs as root, so a rebuild
#     without --user leaves files you cannot overwrite
#
# Usage:
#   bash linux/check-graphify-scope.sh [--code-root DIR] [--fix]
#
#   --fix  apply the safe repairs: approve the server in local settings and
#          chown root-owned graphify-out back to you. Never edits tracked
#          files and never builds a graph (that is a real extraction run).
#
# Exit 0 = every participating repo is fully wired.
# ============================================================================
set -uo pipefail

CODE_ROOT="${CODE_ROOT:-$HOME/code}"
FIX=0
while [ $# -gt 0 ]; do
    case "$1" in
        --code-root) CODE_ROOT="$2"; shift 2 ;;
        --fix) FIX=1; shift ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; D=$'\033[90m'; C=$'\033[36m'; N=$'\033[0m'
PROBLEMS=0

echo "${C}======================================================================${N}"
echo "${C}  Graphify — scope check   (code root: $CODE_ROOT)${N}"
echo "${C}======================================================================${N}"

# ---------------------------------------------------------------- user scope
# Repo-bound servers must never live here: a single global entry answers for
# every repo, which is exactly the failure this check exists to prevent.
echo ""
echo "USER SCOPE  ~/.claude.json"
LEAKED=$(python3 - <<'PY'
import json, pathlib
p = pathlib.Path.home() / '.claude.json'
try:
    ms = json.loads(p.read_text()).get('mcpServers') or {}
except Exception:
    ms = {}
print(' '.join(n for n in ('graphify-docker', 'graphify', 'omnigraph') if n in ms))
PY
)
if [ -n "$LEAKED" ]; then
    echo "  ${R}X repo-bound server(s) in user scope: $LEAKED${N}"
    echo "    ${D}Serves ONE repo's data to EVERY repo. Remove with:${N}"
    for s in $LEAKED; do
        echo "    ${D}claude mcp remove -s user $s${N}"
    done
    PROBLEMS=$((PROBLEMS + 1))
else
    echo "  ${G}v clean — no repo-bound servers in user scope${N}"
fi

# ------------------------------------------------------------------ per repo
for repo in "$CODE_ROOT"/*/; do
    repo="${repo%/}"
    name="$(basename "$repo")"
    [ -d "$repo/.git" ] || continue
    # "Participating" = declares a graphify server or has a graph. A repo with
    # neither simply does not use graphify; silence is correct there.
    [ -f "$repo/.mcp.json" ] || [ -d "$repo/graphify-out" ] || continue
    grep -q graphify "$repo/.mcp.json" 2>/dev/null || [ -d "$repo/graphify-out" ] || continue

    echo ""
    echo "${C}$name${N}  ${D}$repo${N}"

    # -- gate 1: project-scoped server mounting THIS repo ------------------
    MOUNT=$(python3 - "$repo" <<'PY'
import json, sys, pathlib, re
repo = pathlib.Path(sys.argv[1])
try:
    srv = (json.loads((repo/'.mcp.json').read_text()).get('mcpServers') or {}).get('graphify-docker')
except Exception:
    srv = None
if not srv:
    print('MISSING'); raise SystemExit
args = srv.get('args') or []
mount = next((a for a in args if ':/repo' in a), '')
host = mount.split(':/repo')[0]
host = re.sub(r'\$\{([A-Za-z_]\w*)(?::-([^}]*))?\}', lambda m: m.group(2) or '', host)
print('OK' if pathlib.Path(host).resolve() == repo.resolve() else f'WRONG {host}')
PY
)
    case "$MOUNT" in
        OK) echo "  ${G}v gate 1  project-scoped server mounts this repo${N}" ;;
        MISSING)
            echo "  ${R}X gate 1  no graphify-docker in $name/.mcp.json${N}"
            echo "    ${D}Another repo's graph may answer for this one. See${N}"
            echo "    ${D}skills/mcp-servers-setup/SKILL.md -> Graphify -> Per-repo setup${N}"
            PROBLEMS=$((PROBLEMS + 1)) ;;
        *)  echo "  ${R}X gate 1  mounts the WRONG path: ${MOUNT#WRONG }${N}"
            echo "    ${D}It will serve that repo's graph, not this one.${N}"
            PROBLEMS=$((PROBLEMS + 1)) ;;
    esac

    # -- gate 2: approved in untracked local settings ----------------------
    SETTINGS="$repo/.claude/settings.local.json"
    APPROVED=$(python3 - "$SETTINGS" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
try:
    d = json.loads(p.read_text())
except Exception:
    print('NOFILE'); raise SystemExit
if d.get('enableAllProjectMcpServers') is True:
    print('ALL')
elif 'graphify-docker' in (d.get('enabledMcpjsonServers') or []):
    print('YES')
else:
    print('NO')
PY
)
    if [ "$APPROVED" = YES ] || [ "$APPROVED" = ALL ]; then
        echo "  ${G}v gate 2  approved in local settings${N}"
    else
        if [ "$FIX" -eq 1 ]; then
            mkdir -p "$repo/.claude"
            python3 - "$SETTINGS" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
d = {}
if p.exists():
    try: d = json.loads(p.read_text())
    except Exception: d = {}
lst = d.setdefault('enabledMcpjsonServers', [])
if 'graphify-docker' not in lst:
    lst.append('graphify-docker')
p.write_text(json.dumps(d, indent=2) + '\n')
PY
            echo "  ${Y}~ gate 2  FIXED — approved graphify-docker in local settings${N}"
        else
            echo "  ${R}X gate 2  not approved -> the tool will be silently ABSENT${N}"
            echo "    ${D}Add to $name/.claude/settings.local.json (untracked):${N}"
            echo "    ${D}  { \"enabledMcpjsonServers\": [\"graphify-docker\"] }   (or --fix)${N}"
            PROBLEMS=$((PROBLEMS + 1))
        fi
    fi

    # -- gate 3: a graph exists -------------------------------------------
    if [ -f "$repo/graphify-out/graph.json" ]; then
        AGE=$(( ( $(date +%s) - $(stat -c %Y "$repo/graphify-out/graph.json") ) / 86400 ))
        if [ "$AGE" -gt 14 ]; then
            echo "  ${Y}~ gate 3  graph exists but is ${AGE}d old — consider rebuilding${N}"
        else
            echo "  ${G}v gate 3  graph present (${AGE}d old)${N}"
        fi
    else
        echo "  ${R}X gate 3  no graphify-out/graph.json — server would serve nothing${N}"
        echo "    ${D}cd $repo && docker run --rm --user \"\$(id -u):\$(id -g)\" \\${N}"
        echo "    ${D}  -v \"\$PWD:/repo\" -w /repo --entrypoint python graphify-mcp:latest \\${N}"
        echo "    ${D}  -m graphify update .${N}"
        PROBLEMS=$((PROBLEMS + 1))
    fi

    # -- trap: root-owned artefacts from a --user-less rebuild -------------
    if [ -d "$repo/graphify-out" ]; then
        ROOTED=$(find "$repo/graphify-out" ! -user "$(id -un)" 2>/dev/null | wc -l)
        if [ "$ROOTED" -gt 0 ]; then
            if [ "$FIX" -eq 1 ]; then
                docker run --rm -v "$repo:/repo" --entrypoint chown graphify-mcp:latest \
                    -R "$(id -u):$(id -g)" /repo/graphify-out >/dev/null 2>&1 \
                    && echo "  ${Y}~ owner  FIXED — chowned $ROOTED file(s) back to you${N}" \
                    || { echo "  ${R}X owner  $ROOTED file(s) not yours; chown failed${N}"; PROBLEMS=$((PROBLEMS + 1)); }
            else
                echo "  ${R}X owner  $ROOTED file(s) not owned by you (rebuilt without --user)${N}"
                echo "    ${D}The next rebuild will fail with permission denied. Run with --fix${N}"
                PROBLEMS=$((PROBLEMS + 1))
            fi
        fi
    fi
done

echo ""
echo "${C}----------------------------------------------------------------------${N}"
if [ "$PROBLEMS" -eq 0 ]; then
    echo "${G}  All gates open — every participating repo serves its own graph.${N}"
else
    echo "${R}  $PROBLEMS problem(s) found — see the fixes above (or re-run with --fix).${N}"
fi
echo "${C}======================================================================${N}"
[ "$PROBLEMS" -eq 0 ]

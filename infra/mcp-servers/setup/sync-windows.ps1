<#
  sync-windows.ps1 — Windows / Docker Desktop adaptation of omnigraph-sync.sh.

  On Docker Desktop, `--network host` cannot reach the local server on 127.0.0.1,
  so the CLI container runs on the compose network (mcp-server_mcp-net) and
  addresses the LOCAL server as http://omnigraph-server:8080 and the CENTRAL
  server at its public URL. Data is piped over stdin (no bind-mount path issues).

  MULTI-GRAPH: per-project isolation means every project graph must sync, not
  just `memory`. The graphs to sync are discovered like omnigraph-sync.sh:
    - $env:GRAPHS ("a,b" or "a b")            -> exactly that list
    - elseif $env:GRAPH set and != 'memory'   -> that single graph (legacy)
    - else GET {CENTRAL_URL}/graphs            -> every graph_id it returns
  Each graph is reconciled independently; one graph's failure does NOT abort the
  others (the script tracks the last non-zero code and exits with it).

  Guarantees (per graph), matching omnigraph-sync.sh:
    - BACKUP local main first (local is the newest/authoritative copy)
    - push local -> central device/<host> branch -> native merge into central main
    - VERIFY central has no node/edge duplicates before trusting it
    - pull central -> local via OVERWRITE of a deduped export (no dup edges);
      restore from backup if the pull fails
    - VERIFY local; delete the device branch unless -KeepDeviceBranch

  Config: setup/.env or env vars —
    CENTRAL_URL, CENTRAL_TOKEN, LOCAL_TOKEN (required)
    GRAPHS  (comma/space list; default: all graphs central exposes)
    GRAPH   (legacy single non-'memory' graph)      DEVICE (default: hostname)
    DRY_RUN, KEEP_DEVICE_BRANCH (also the -DryRun / -KeepDeviceBranch switches)
  Run in PowerShell 7 (pwsh). See docs/REMOTE-SYNC-TEST-PLAN.md.
#>
[CmdletBinding()]
param(
  [switch]$DryRun,            # snapshot + verify BOTH sides, no writes
  [switch]$KeepDeviceBranch   # keep device/<host> on central after merge
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- load setup/.env ---
$envFile = Join-Path $here '.env'
if (Test-Path $envFile) {
  foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*([A-Za-z_]\w*)\s*=\s*(.*)$') {
      Set-Item -Path ("Env:" + $Matches[1]) -Value $Matches[2].Trim()
    }
  }
}
function Need($n) { $v = [Environment]::GetEnvironmentVariable($n); if (-not $v) { throw "set $n (in setup/.env)" }; $v }
$CENTRAL_URL   = Need 'CENTRAL_URL'
$CENTRAL_TOKEN = Need 'CENTRAL_TOKEN'
$LOCAL_TOKEN   = Need 'LOCAL_TOKEN'
# LOCAL server as seen from INSIDE the CLI container (compose service name):
# Two views of the SAME local server, and they are not interchangeable:
#   $LOCAL_URL     — as seen from inside the CLI container (compose service name)
#   $LOCAL_API_URL — as seen from this host (the published port), for direct HTTP calls
# Using the container name from the host (or 127.0.0.1 from inside a container) fails.
$LOCAL_URL     = if ($env:LOCAL_URL_CONTAINER) { $env:LOCAL_URL_CONTAINER } else { 'http://omnigraph-server:8080' }
$LOCAL_API_URL = if ($env:LOCAL_URL) { $env:LOCAL_URL } else { 'http://127.0.0.1:8080' }
$DEVICE     = if ($env:DEVICE) { $env:DEVICE } else { $env:COMPUTERNAME }
$IMAGE      = if ($env:OMNIGRAPH_IMAGE) { $env:OMNIGRAPH_IMAGE } else { 'modernrelay/omnigraph-server:v0.8.1' }
$NET        = if ($env:DOCKER_NET) { $env:DOCKER_NET } else { 'mcp-server_mcp-net' }
$BACKUP_DIR = if ($env:BACKUP_DIR) { $env:BACKUP_DIR } else { Join-Path $here 'backups' }
$PY         = if ($env:PYTHON) { $env:PYTHON } else { 'python' }
$BRANCH     = "device/$DEVICE"
$JQ         = Join-Path $here 'omnigraph_jsonl.py'
# switches OR env vars (any non-empty env value counts, like bash's `[ -n ... ]`)
$DryRunEff     = [bool]$DryRun          -or [bool]$env:DRY_RUN
$KeepBranchEff = [bool]$KeepDeviceBranch -or [bool]$env:KEEP_DEVICE_BRANCH
New-Item -ItemType Directory -Force -Path $BACKUP_DIR | Out-Null
$work = (New-Item -ItemType Directory -Path (Join-Path $env:TEMP ("ogsync-" + [guid]::NewGuid().ToString('N')))).FullName

function Log($m) { Write-Host "[omnigraph-sync] $m" -ForegroundColor Cyan }
function WriteText($path, $text) { [System.IO.File]::WriteAllText($path, $text) }

# omnigraph CLI (URL-addressed); returns stdout as text.
# A non-zero exit from a NATIVE command is not a PowerShell terminating error, so a
# caller's try/catch never fires unless we check $LASTEXITCODE and throw. Swallowing
# stderr to $null on top of that is how a FAILED pull still logged "pulled central main
# -> local main" and returned rc=0 while local was untouched (2026-07-17). Fail loudly.
# The omnigraph CLI writes its progress banner ("omnigraph load → … (served)") to
# STDERR on success. This script runs with $ErrorActionPreference='Stop', under which
# `2>&1` promotes that harmless banner to a TERMINATING error — so stderr must not be
# merged while EAP is Stop. Capture it with EAP temporarily relaxed, then judge success
# by $LASTEXITCODE only. (The old code used `2>$null` and never checked the exit code at
# all, which is why a failed pull still logged "pulled central main -> local main" and
# returned rc=0 while local was untouched.)
function Invoke-Native([scriptblock]$Block, [string]$What) {
  $eap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { $out = (& $Block 2>&1 | ForEach-Object { "$_" }) -join "`n" }
  finally { $ErrorActionPreference = $eap }
  if ($LASTEXITCODE -ne 0) { throw "$What failed (exit $LASTEXITCODE): $out" }
  $out
}
function Og([string]$token, [string[]]$cliArgs) {
  Invoke-Native { docker run --rm -i --network $NET -e "OMNIGRAPH_BEARER_TOKEN=$token" --entrypoint omnigraph $IMAGE @cliArgs } "omnigraph $($cliArgs -join ' ')"
}
# load a JSONL file into graph/branch via stdin (no bind mount)
function OgLoad([string]$token, [string]$url, [string]$branch, [string]$mode, [string]$file, [string]$graph) {
  $b = if ($branch) { "--branch $branch " } else { "" }
  $cmd = "cat > /tmp/d.jsonl; omnigraph load --server $url --graph $graph $b--data /tmp/d.jsonl --mode $mode --yes --json"
  Invoke-Native { Get-Content -Raw -LiteralPath $file | docker run --rm -i --network $NET -e "OMNIGRAPH_BEARER_TOKEN=$token" --entrypoint sh $IMAGE -c $cmd } "load --mode $mode --graph $graph"
}
function Export([string]$token, [string]$url, [string]$outFile, [string]$graph) {
  WriteText $outFile (Og $token @('export','--server',$url,'--graph',$graph))
}
function Verify([string]$file) { Get-Content -Raw -LiteralPath $file | & $PY $JQ verify; return $LASTEXITCODE }

# Which graphs to sync (mirrors omnigraph-sync.sh discovery). Returns a string[].
function Get-GraphList {
  if ($env:GRAPHS) {
    return @($env:GRAPHS -split '[,\s]+' | Where-Object { $_ })
  }
  if ($env:GRAPH -and $env:GRAPH -ne 'memory') {
    return @($env:GRAPH)
  }
  try {
    $resp = Invoke-WebRequest -UseBasicParsing -TimeoutSec 8 `
      -Uri "$($CENTRAL_URL.TrimEnd('/'))/graphs" `
      -Headers @{ Authorization = "Bearer $CENTRAL_TOKEN" }
    return @([regex]::Matches($resp.Content, '"graph_id":"([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
  } catch {
    return @()
  }
}

# Reconcile ONE graph: backup local, push to a central device branch, native-merge
# to central main, verify no dupes, then overwrite local with clean central. Every
# guarantee (local backup first, no-dup gate before overwrite, restore-on-failure)
# is preserved per graph. Returns a non-zero code on failure without throwing, so
# the caller can continue with the remaining graphs.
function Sync-Graph([string]$Graph) {
  # 1. BACKUP local main FIRST (before any mutation)
  $ts = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
  $backup = Join-Path $BACKUP_DIR "local-$Graph-$ts.jsonl"
  Export $LOCAL_TOKEN $LOCAL_URL $backup $Graph
  $localFile = Join-Path $work "local-$Graph.jsonl"; Copy-Item $backup $localFile -Force
  Log "[$Graph] backed up local main -> $backup"
  Log "[$Graph] local pre-sync verify:"; Verify $localFile | Out-Null

  if ($DryRunEff) {
    $c = Join-Path $work "central-$Graph.jsonl"; Export $CENTRAL_TOKEN $CENTRAL_URL $c $Graph
    Log "[$Graph] central verify:"; Verify $c | Out-Null
    Log "[$Graph] DRY_RUN — no writes. Backup: $backup"
    return 0
  }

  # 2-3. push local -> central device branch -> native merge into main.
  #
  # Push only the DELTA, never the whole local export. The device branch is forked from
  # central's main, so it already holds central's edges; edges have no @key, so a
  # `load --mode merge` of every local edge APPENDS a second copy of each shared one and
  # the branch-merge then carries the duplicates into main. That is exactly how central
  # reached 2x edges on every project graph (2026-07-17). Nodes are @key(slug) and merge
  # safely, so `pushset` keeps all nodes and only the edges central lacks.
  $centralPre = Join-Path $work "central-pre-$Graph.jsonl"
  Export $CENTRAL_TOKEN $CENTRAL_URL $centralPre $Graph
  $push = Join-Path $work "push-$Graph.jsonl"
  WriteText $push ((Get-Content -Raw -LiteralPath $localFile | & $PY $JQ pushset $centralPre) -join "`n")
  $pushLines = @(Get-Content -LiteralPath $push | Where-Object { $_.Trim() })
  $nEdge = @($pushLines | Where-Object { $_ -match '"edge"' }).Count
  $nNode = @($pushLines | Where-Object { $_ -match '"type"' }).Count

  # Push the delta STRAIGHT to central main — no device branch.
  #
  # The old branch dance (create -> load -> merge -> delete) exists for "review before
  # merge", which buys nothing on an unattended 5-minute timer, and on omnigraph v0.8.1 it
  # walks into three separate defects (all reproduced 2026-07-17):
  #   * `branch create`  -> Lance internal: "Clone operation should not enter build_manifest"
  #   * `branch merge`   -> "Concurrent modification: table version N already exists for
  #                          node:<Type>" when the branch touched a table main is level with
  #   * pushing the whole export -> duplicate edges (no @key on edges)
  # A delta merge-load onto main has none of those: nodes upsert by @key(slug), and only
  # edges central lacks are sent, so it cannot duplicate. Safety comes from the delta, the
  # pre-write backup, and the verify gates — not from the branch.
  if ($pushLines.Count -eq 0) {
    Log "[$Graph] nothing to push (local adds nothing to central)"   # the common case on a timer
  } else {
    Log "[$Graph] pushing delta -> central main: $nNode changed/new node(s), $nEdge new edge(s)"
    OgLoad $CENTRAL_TOKEN $CENTRAL_URL '' 'merge' $push $Graph | Out-Null
    Log "[$Graph] pushed to central main"
  }

  # 4. export central + verify NO duplicates before we trust it.
  # The merge can land after this read (the manifest advances asynchronously), so a
  # "clean" here is not proof — re-verify at the end and treat that as authoritative.
  $central = Join-Path $work "central-$Graph.jsonl"; Export $CENTRAL_TOKEN $CENTRAL_URL $central $Graph
  Log "[$Graph] central verify:"
  if ((Verify $central) -ne 0) { Log "[$Graph] !! central has DUPLICATES after merge — NOT overwriting local. Backup: $backup"; return 2 }

  # 5. pull central -> local (local := clean central).
  #
  # Delegated to pull_graph.py, which purges local and merge-loads into the EMPTY graph.
  # `load --mode overwrite` into a POPULATED graph trips a Lance bug on v0.8.1
  # (`stage_create_btree_index … all columns in a record batch must have the same length`)
  # — and worse, it sometimes lands anyway while exiting 1, so you cannot even trust its
  # failure. Loading into an empty graph is the one reliable path (it is how central was
  # repaired). pull_graph.py refuses to purge unless the source is non-empty and
  # duplicate-free, checks the purge actually emptied the graph before loading, restores
  # from backup if the load fails, and verifies the result matches the source.
  # Two target URLs on purpose: --target-url is hit from THIS host (export/mutate), while
  # --target-load-url is hit from inside the CLI container (the load). They are different
  # hosts — 127.0.0.1 inside the container is the container.
  & $PY (Join-Path $here 'pull_graph.py') $Graph `
      --source-url $CENTRAL_URL --source-token $CENTRAL_TOKEN `
      --target-url $LOCAL_API_URL --target-load-url $LOCAL_URL --target-token $LOCAL_TOKEN `
      --net $NET --backup $backup
  if ($LASTEXITCODE -ne 0) { Log "[$Graph] !! pull failed (exit $LASTEXITCODE) — backup: $backup"; return 3 }

  # 6. verify local + optional branch cleanup
  $after = Join-Path $work "local-$Graph.after.jsonl"; Export $LOCAL_TOKEN $LOCAL_URL $after $Graph
  Log "[$Graph] local post-sync verify:"; Verify $after | Out-Null
  # No device branch is created any more (see the push above), so there is nothing to clean
  # up. Sweep any left over by an older run, so they can't block `schema apply`.
  if (-not $KeepBranchEff) {
    try { Og $CENTRAL_TOKEN @('branch','delete',$BRANCH,'--server',$CENTRAL_URL,'--graph',$Graph,'--yes') | Out-Null
          Log "[$Graph] removed stale device branch $BRANCH" } catch { }
  }
  Log "[$Graph] sync complete. Local backup: $backup"
  return 0
}

try {
  # 0. reachable? (from the host)
  try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 8 "$($CENTRAL_URL.TrimEnd('/'))/healthz" | Out-Null }
  catch { Log "central unreachable — offline, skipping"; return }

  # which graphs to sync
  $graphList = Get-GraphList
  if (@($graphList).Count -eq 0) { Log "no graphs to sync (GET /graphs empty?)"; exit 1 }
  Log ("syncing graphs: " + ($graphList -join ' '))

  # reconcile each graph; a single graph's failure must not abort the others
  $rc = 0
  foreach ($g in $graphList) {
    try {
      $code = Sync-Graph $g
      if ($code -is [array]) { $code = @($code)[-1] }
    } catch {
      Log "[$g] sync error: $($_.Exception.Message)"; $code = 1
    }
    if ($code -ne 0) { $rc = $code; Log "[$g] sync returned $code — continuing with remaining graphs" }
  }

  if ($DryRunEff) { Log "DRY_RUN complete — no writes made." }
  Log ("sync finished for: " + ($graphList -join ' ') + " (rc=$rc)")
  exit $rc
}
finally { Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue }

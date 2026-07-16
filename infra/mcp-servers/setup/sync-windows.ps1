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
$LOCAL_URL  = if ($env:LOCAL_URL_CONTAINER) { $env:LOCAL_URL_CONTAINER } else { 'http://omnigraph-server:8080' }
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

# omnigraph CLI (URL-addressed); returns stdout as text
function Og([string]$token, [string[]]$cliArgs) {
  (& docker run --rm -i --network $NET -e "OMNIGRAPH_BEARER_TOKEN=$token" --entrypoint omnigraph $IMAGE @cliArgs 2>$null) -join "`n"
}
# load a JSONL file into graph/branch via stdin (no bind mount)
function OgLoad([string]$token, [string]$url, [string]$branch, [string]$mode, [string]$file, [string]$graph) {
  $b = if ($branch) { "--branch $branch " } else { "" }
  $cmd = "cat > /tmp/d.jsonl; omnigraph load --server $url --graph $graph $b--data /tmp/d.jsonl --mode $mode --yes --json"
  Get-Content -Raw -LiteralPath $file | & docker run --rm -i --network $NET -e "OMNIGRAPH_BEARER_TOKEN=$token" --entrypoint sh $IMAGE -c $cmd
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

  # 2-3. push local -> central device branch -> native merge into main
  Og $CENTRAL_TOKEN @('branch','create',$BRANCH,'--server',$CENTRAL_URL,'--graph',$Graph) | Out-Null
  OgLoad $CENTRAL_TOKEN $CENTRAL_URL $BRANCH 'merge' $localFile $Graph | Out-Null
  Og $CENTRAL_TOKEN @('branch','merge',$BRANCH,'--into','main','--server',$CENTRAL_URL,'--graph',$Graph,'--yes') | Out-Null
  Log "[$Graph] merged $BRANCH -> main on central"

  # 4. export central + verify NO duplicates before we trust it
  $central = Join-Path $work "central-$Graph.jsonl"; Export $CENTRAL_TOKEN $CENTRAL_URL $central $Graph
  Log "[$Graph] central verify:"
  if ((Verify $central) -ne 0) { Log "[$Graph] !! central has DUPLICATES after merge — NOT overwriting local. Backup: $backup"; return 2 }

  # 5. pull central -> local via OVERWRITE (deduped input; local := clean central)
  $clean = Join-Path $work "central-$Graph.clean.jsonl"
  WriteText $clean ((Get-Content -Raw -LiteralPath $central | & $PY $JQ dedup) -join "`n")
  try { OgLoad $LOCAL_TOKEN $LOCAL_URL '' 'overwrite' $clean $Graph | Out-Null }
  catch { Log "[$Graph] !! local overwrite failed — restoring from backup"; OgLoad $LOCAL_TOKEN $LOCAL_URL '' 'overwrite' $localFile $Graph | Out-Null; return 3 }
  Log "[$Graph] pulled central main -> local main (overwrite, deduped)"

  # 6. verify local + optional branch cleanup
  $after = Join-Path $work "local-$Graph.after.jsonl"; Export $LOCAL_TOKEN $LOCAL_URL $after $Graph
  Log "[$Graph] local post-sync verify:"; Verify $after | Out-Null
  if (-not $KeepBranchEff) { Og $CENTRAL_TOKEN @('branch','delete',$BRANCH,'--server',$CENTRAL_URL,'--graph',$Graph,'--yes') | Out-Null; Log "[$Graph] deleted device branch $BRANCH" }
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

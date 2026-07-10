<#
  sync-windows.ps1 — Windows / Docker Desktop adaptation of omnigraph-sync.sh.

  On Docker Desktop, `--network host` cannot reach the local server on 127.0.0.1,
  so the CLI container runs on the compose network (mcp-server_mcp-net) and
  addresses the LOCAL server as http://omnigraph-server:8080 and the CENTRAL
  server at its public URL. Data is piped over stdin (no bind-mount path issues).

  Guarantees, matching omnigraph-sync.sh:
    - BACKUP local main first (local is the newest/authoritative copy)
    - push local -> central device/<host> branch -> native merge into central main
    - VERIFY central has no node/edge duplicates before trusting it
    - pull central -> local via OVERWRITE of a deduped export (no dup edges);
      restore from backup if the pull fails
    - VERIFY local; delete the device branch unless -KeepDeviceBranch

  Config: setup/.env (CENTRAL_URL, CENTRAL_TOKEN, LOCAL_TOKEN, GRAPH, DEVICE) or env vars.
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
$GRAPH      = if ($env:GRAPH)  { $env:GRAPH }  else { 'memory' }
$DEVICE     = if ($env:DEVICE) { $env:DEVICE } else { $env:COMPUTERNAME }
$IMAGE      = if ($env:OMNIGRAPH_IMAGE) { $env:OMNIGRAPH_IMAGE } else { 'modernrelay/omnigraph-server:v0.8.1' }
$NET        = if ($env:DOCKER_NET) { $env:DOCKER_NET } else { 'mcp-server_mcp-net' }
$BACKUP_DIR = if ($env:BACKUP_DIR) { $env:BACKUP_DIR } else { Join-Path $here 'backups' }
$PY         = if ($env:PYTHON) { $env:PYTHON } else { 'python' }
$BRANCH     = "device/$DEVICE"
$JQ         = Join-Path $here 'omnigraph_jsonl.py'
New-Item -ItemType Directory -Force -Path $BACKUP_DIR | Out-Null
$work = (New-Item -ItemType Directory -Path (Join-Path $env:TEMP ("ogsync-" + [guid]::NewGuid().ToString('N')))).FullName

function Log($m) { Write-Host "[omnigraph-sync] $m" -ForegroundColor Cyan }
function WriteText($path, $text) { [System.IO.File]::WriteAllText($path, $text) }

# omnigraph CLI (URL-addressed); returns stdout as text
function Og([string]$token, [string[]]$cliArgs) {
  (& docker run --rm -i --network $NET -e "OMNIGRAPH_BEARER_TOKEN=$token" --entrypoint omnigraph $IMAGE @cliArgs 2>$null) -join "`n"
}
# load a JSONL file into graph/branch via stdin (no bind mount)
function OgLoad([string]$token, [string]$url, [string]$branch, [string]$mode, [string]$file) {
  $b = if ($branch) { "--branch $branch " } else { "" }
  $cmd = "cat > /tmp/d.jsonl; omnigraph load --server $url --graph $GRAPH $b--data /tmp/d.jsonl --mode $mode --yes --json"
  Get-Content -Raw -LiteralPath $file | & docker run --rm -i --network $NET -e "OMNIGRAPH_BEARER_TOKEN=$token" --entrypoint sh $IMAGE -c $cmd
}
function Export([string]$token, [string]$url, [string]$outFile) {
  WriteText $outFile (Og $token @('export','--server',$url,'--graph',$GRAPH))
}
function Verify([string]$file) { Get-Content -Raw -LiteralPath $file | & $PY $JQ verify; return $LASTEXITCODE }

try {
  # 0. reachable? (from the host)
  try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 8 "$($CENTRAL_URL.TrimEnd('/'))/healthz" | Out-Null }
  catch { Log "central unreachable — offline, skipping"; return }

  # 1. BACKUP local main
  $ts = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
  $backup = Join-Path $BACKUP_DIR "local-main-$ts.jsonl"
  Export $LOCAL_TOKEN $LOCAL_URL $backup
  $localFile = Join-Path $work 'local.jsonl'; Copy-Item $backup $localFile
  Log "backed up local main -> $backup"
  Log "local pre-sync verify:"; Verify $localFile | Out-Null

  if ($DryRun) {
    $c = Join-Path $work 'central.jsonl'; Export $CENTRAL_TOKEN $CENTRAL_URL $c
    Log "central verify:"; Verify $c | Out-Null
    Log "DRY_RUN complete — no writes. Backup: $backup"; return
  }

  # 2-3. push local -> central device branch -> native merge into main
  Og $CENTRAL_TOKEN @('branch','create',$BRANCH,'--server',$CENTRAL_URL,'--graph',$GRAPH) | Out-Null
  OgLoad $CENTRAL_TOKEN $CENTRAL_URL $BRANCH 'merge' $localFile | Out-Null
  Og $CENTRAL_TOKEN @('branch','merge',$BRANCH,'--into','main','--server',$CENTRAL_URL,'--graph',$GRAPH,'--yes') | Out-Null
  Log "merged $BRANCH -> main on central"

  # 4. export central + verify NO duplicates
  $central = Join-Path $work 'central.jsonl'; Export $CENTRAL_TOKEN $CENTRAL_URL $central
  Log "central verify:"; if ((Verify $central) -ne 0) { Log "!! central has DUPLICATES after merge — NOT overwriting local. Backup: $backup"; exit 2 }

  # 5. pull central -> local via OVERWRITE (deduped)
  $clean = Join-Path $work 'central.clean.jsonl'
  WriteText $clean ((Get-Content -Raw -LiteralPath $central | & $PY $JQ dedup) -join "`n")
  try { OgLoad $LOCAL_TOKEN $LOCAL_URL '' 'overwrite' $clean | Out-Null }
  catch { Log "!! local overwrite failed — restoring from backup"; OgLoad $LOCAL_TOKEN $LOCAL_URL '' 'overwrite' $localFile | Out-Null; exit 3 }
  Log "pulled central main -> local main (overwrite, deduped)"

  # 6. verify local + optional branch cleanup
  $after = Join-Path $work 'local.after.jsonl'; Export $LOCAL_TOKEN $LOCAL_URL $after
  Log "local post-sync verify:"; Verify $after | Out-Null
  if (-not $KeepDeviceBranch) { Og $CENTRAL_TOKEN @('branch','delete',$BRANCH,'--server',$CENTRAL_URL,'--graph',$GRAPH,'--yes') | Out-Null; Log "deleted device branch $BRANCH" }
  Log "sync complete. Local backup: $backup"
}
finally { Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue }

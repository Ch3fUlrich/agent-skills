<#
Smoke tests for run_handoff_sessions.ps1 — the DRIVER, not the pure core.

These exist because both bugs found on the first real run lived here and were
invisible to HandoffCore.Tests.ps1: a lane array unrolled by the output stream,
and a local $followUp colliding with the [string]$FollowUp parameter. Both only
appear when the script is actually invoked, so these tests invoke it.

    pwsh -NoProfile -File skills/unattended-orchestration/tests/Runner.Smoke.Tests.ps1

Nothing here starts a `claude` session: -DryRun stops before any launch, and
-Validate stops before preflight.
#>
$ErrorActionPreference = "Stop"
$script:Failures = 0
$script:Ran = 0

function It([string]$name, [scriptblock]$body) {
    $script:Ran++
    try { & $body; Write-Host "  ok   $name" -ForegroundColor Green }
    catch { $script:Failures++; Write-Host "  FAIL $name`n       $($_.Exception.Message)" -ForegroundColor Red }
}
function Assert-Match([string]$text, [string]$pattern, [string]$because = "") {
    if ($text -notmatch $pattern) { throw "expected output matching '$pattern' $because`n--- got ---`n$text" }
}
function Assert-NotMatch([string]$text, [string]$pattern, [string]$because = "") {
    if ($text -match $pattern) { throw "did NOT expect '$pattern' $because`n--- got ---`n$text" }
}

$runner = Join-Path (Split-Path $PSScriptRoot -Parent) "run_handoff_sessions.ps1"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("handoff-smoke-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

function New-Config([array]$lanes, [string]$name) {
    $cfg = @{
        repo         = $repo
        baseBranch   = (git -C $repo rev-parse --abbrev-ref HEAD).Trim()
        branchPrefix = "smoke"
        stateDir     = (Join-Path $tmp "state-$name")
        sessions     = @{
            X = @{ name = "alpha"; model = "opus";   brief = "alpha work" }
            Y = @{ name = "beta";  model = "sonnet"; brief = "beta work" }
        }
        lanes        = $lanes
    }
    $p = Join-Path $tmp "$name.json"
    $cfg | ConvertTo-Json -Depth 8 | Set-Content $p -Encoding utf8
    return $p
}

try {
    Write-Host "`n-Validate"
    It "reports a two-session lane as ONE lane, not two" {
        $p = New-Config @(, @("X", "Y")) "onelane"
        $out = (& pwsh -NoProfile -File $runner -Config $p -Validate 2>&1 | Out-String)
        Assert-Match $out "lanes:\s+X,Y" "a sequential lane must stay sequential"
        Assert-NotMatch $out "X\s+\|\s+Y" "must not split into parallel lanes"
    }
    It "reports two lanes as two" {
        $p = New-Config @(@("X"), @("Y")) "twolanes"
        $out = (& pwsh -NoProfile -File $runner -Config $p -Validate 2>&1 | Out-String)
        Assert-Match $out "lanes:\s+X\s+\|\s+Y"
    }
    It "fails a config whose lane names an unknown session" {
        $p = New-Config @(, @("X", "NOPE")) "badlane"
        $out = (& pwsh -NoProfile -File $runner -Config $p -Validate 2>&1 | Out-String)
        Assert-Match $out "NOPE"
    }

    Write-Host "`n-DryRun"
    It "runs a single lane INLINE, without spawning lane child processes" {
        # The unrolling bug showed up exactly here: one lane became two children.
        $p = New-Config @(, @("X", "Y")) "inline"
        $out = (& pwsh -NoProfile -File $runner -Config $p -DryRun 2>&1 | Out-String)
        Assert-Match $out "dry run: would create" "the lane body must actually run"
        Assert-NotMatch $out "starting as lane\d" "a single lane must not fan out to children"
        Assert-Match $out "lane \[X,Y\] finished"
    }
    It "visits every session of a sequential lane, in order" {
        $p = New-Config @(, @("X", "Y")) "order"
        $out = (& pwsh -NoProfile -File $runner -Config $p -DryRun 2>&1 | Out-String)
        $ix = $out.IndexOf("session X"); $iy = $out.IndexOf("session Y")
        if ($ix -lt 0 -or $iy -lt 0) { throw "expected both sessions to be visited`n$out" }
        if ($ix -gt $iy) { throw "X must be visited before Y" }
    }
    It "dispatches multiple lanes as children that do NOT crash on argument binding" {
        # The $followUp / [string]$FollowUp collision surfaced only in a child.
        $p = New-Config @(@("X"), @("Y")) "children"
        $out = (& pwsh -NoProfile -File $runner -Config $p -DryRun 2>&1 | Out-String)
        Assert-Match $out "starting as lane1"
        $laneLogs = Get-ChildItem (Join-Path $tmp "state-children") -Filter "lane*.out.log" -ErrorAction SilentlyContinue
        if (-not $laneLogs) { throw "no lane child logs were written" }
        $childText = ($laneLogs | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
        Assert-NotMatch $childText "crashed at session" "child lanes must not crash"
        Assert-Match $childText "dry run: would create" "child lanes must reach the lane body"
    }
    Write-Host "`n-EmitBriefs"
    It "renders every session as markdown without launching anything" {
        $p = New-Config @(, @("X", "Y")) "emit"
        $out = (& pwsh -NoProfile -File $runner -Config $p -EmitBriefs 2>&1 | Out-String)
        Assert-Match $out "### Session X"
        Assert-Match $out "### Session Y"
        Assert-Match $out "claude attach handoff-X" "each section must say how to join the session"
        Assert-NotMatch $out "dry run: would create" "-EmitBriefs must not enter the run loop"
        Assert-NotMatch $out "preflight" "-EmitBriefs must not require a live claude login"
    }
    It "writes to -OutFile when asked, and the file round-trips" {
        $p = New-Config @(, @("X")) "emitfile"
        $f = Join-Path $tmp "briefs.md"
        (& pwsh -NoProfile -File $runner -Config $p -EmitBriefs -OutFile $f 2>&1) | Out-Null
        if (-not (Test-Path $f)) { throw "no file written to $f" }
        Assert-Match (Get-Content $f -Raw) "### Session X"
    }

    It "a session with dependsOn reports the wait in -DryRun and -Validate instead of blocking" {
        # The wait itself needs a live state file; a dry run must SAY it would
        # wait and carry on, or every rehearsal of a dependent lane hangs.
        $cfg = @{
            repo         = $repo
            baseBranch   = (git -C $repo rev-parse --abbrev-ref HEAD).Trim()
            branchPrefix = "smoke"
            stateDir     = (Join-Path $tmp "state-deps")
            sessions     = @{
                X = @{ name = "alpha"; model = "opus";   brief = "alpha work" }
                Y = @{ name = "beta";  model = "sonnet"; brief = "beta work"; dependsOn = @("X") }
            }
            lanes        = @(@("X"), @("Y"))
        }
        $p = Join-Path $tmp "deps.json"
        $cfg | ConvertTo-Json -Depth 8 | Set-Content $p -Encoding utf8
        $out = (& pwsh -NoProfile -File $runner -Config $p -Validate 2>&1 | Out-String)
        Assert-Match $out "dependsOn:\s+Y waits for X" "-Validate must surface the dependency"
        $out = (& pwsh -NoProfile -File $runner -Config $p -DryRun -Sessions "Y" 2>&1 | Out-String)
        Assert-Match $out "would wait for X" "a dry run must report the wait"
        Assert-Match $out "dry run: would create" "and still reach the lane body"
    }

    It "-Sessions overrides the config into a single inline lane" {
        $p = New-Config @(@("X"), @("Y")) "override"
        $out = (& pwsh -NoProfile -File $runner -Config $p -DryRun -Sessions "X,Y" 2>&1 | Out-String)
        Assert-NotMatch $out "starting as lane\d" "-Sessions must collapse to one lane"
        Assert-Match $out "lane \[X,Y\] finished"
    }
}
finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }

Write-Host "`n$($script:Ran) assertions, $($script:Failures) failed."
exit $script:Failures

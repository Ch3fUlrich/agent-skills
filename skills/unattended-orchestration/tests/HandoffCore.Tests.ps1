<#
Plain-PowerShell tests for HandoffCore.psm1 — no Pester dependency, so any
machine with pwsh can run the guards that protect this runner.

    pwsh -NoProfile -File skills/unattended-orchestration/tests/HandoffCore.Tests.ps1

Exit code 0 = green. Non-zero = the number of failed assertions.
#>
$ErrorActionPreference = "Stop"
$script:Failures = 0
$script:Ran = 0

function It([string]$name, [scriptblock]$body) {
    $script:Ran++
    try { & $body; Write-Host "  ok   $name" -ForegroundColor Green }
    catch { $script:Failures++; Write-Host "  FAIL $name`n       $($_.Exception.Message)" -ForegroundColor Red }
}
function Assert-Equal($expected, $actual, [string]$because = "") {
    if ($expected -ne $actual) { throw "expected '$expected', got '$actual' $because" }
}
function Assert-True($cond, [string]$because = "") {
    if (-not $cond) { throw "expected true $because" }
}
function Assert-Throws([scriptblock]$body, [string]$match) {
    try { & $body } catch {
        if ($_.Exception.Message -match $match) { return }
        throw "threw, but message '$($_.Exception.Message)' does not match '$match'"
    }
    throw "expected a throw matching '$match', but nothing was thrown"
}

$module = Join-Path (Split-Path $PSScriptRoot -Parent) "HandoffCore.psm1"
Import-Module $module -Force

Write-Host "`nClassify-HandoffFailure"
# Why these matter: each kind drives a different recovery. Misclassifying a usage
# limit as 'other' burns the night retrying every two minutes against a wall.
It "reads the epoch out of a usage-limit message and waits for the reset" {
    $future = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 3600
    $r = Classify-HandoffFailure "Claude usage limit reached|$future"
    Assert-Equal "limit" $r.kind
    Assert-True ($r.wait -gt 3000 -and $r.wait -le 6 * 3600) "wait should track the reset epoch, got $($r.wait)"
}
It "caps the limit wait at six hours even for an absurd epoch" {
    $far = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 999999
    $r = Classify-HandoffFailure "usage limit reached|$far"
    Assert-Equal (6 * 3600) $r.wait
}
It "falls back to a flat 30 min for a limit with no epoch" {
    $r = Classify-HandoffFailure "429 too many requests"
    Assert-Equal "limit" $r.kind
    Assert-Equal 1800 $r.wait
}
It "classifies auth failures as terminal (wait 0) so the runner stops instead of looping" {
    $r = Classify-HandoffFailure "Failed to authenticate: OAuth session expired"
    Assert-Equal "auth" $r.kind
    Assert-Equal 0 $r.wait
}
It "auth beats limit when a message contains both" {
    # Ordering guard: auth is checked first on purpose; a login failure is not waitable.
    $r = Classify-HandoffFailure "invalid api key - rate limit"
    Assert-Equal "auth" $r.kind
}
It "classifies overload/network as transient with a 5 min wait" {
    foreach ($t in @("529 overloaded", "500 Internal Server Error", "ECONNRESET", "fetch failed")) {
        $r = Classify-HandoffFailure $t
        Assert-Equal "transient" $r.kind "for '$t'"
        Assert-Equal 300 $r.wait "for '$t'"
    }
}
It "classifies anything unrecognised as 'other'" {
    Assert-Equal "other" (Classify-HandoffFailure "the model wrote a file").kind
}

Write-Host "`nTest-HandoffPermissionPrompt"
It "detects the prompts a background session cannot answer" {
    foreach ($t in @("Do you want to proceed?", "Do you trust the files", "[y/n]", "Permission required")) {
        Assert-True (Test-HandoffPermissionPrompt $t) "for '$t'"
    }
}
It "does not fire on ordinary prose" {
    Assert-True (-not (Test-HandoffPermissionPrompt "I proceeded to edit the file")) "false positive"
}

Write-Host "`nExpand-HandoffTemplate"
It "substitutes {{placeholders}} from a hashtable" {
    Assert-Equal "run in C:\wt on b1" (Expand-HandoffTemplate "run in {{worktree}} on {{branch}}" @{ worktree = "C:\wt"; branch = "b1" })
}
It "leaves unknown placeholders untouched rather than emptying them" {
    # An emptied placeholder produces a brief that silently omits the task.
    Assert-Equal "hi {{nope}}" (Expand-HandoffTemplate "hi {{nope}}" @{ other = "x" })
}
It "is not confused by a value that itself contains braces" {
    Assert-Equal "a {{b}} c" (Expand-HandoffTemplate "a {{x}} c" @{ x = "{{b}}" })
}

Write-Host "`nRead-HandoffConfig / validation"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("handoff-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $good = @{
        repo         = $tmp
        baseBranch   = "main"
        branchPrefix = "wave"
        sessions     = @{ A = @{ name = "alpha"; model = "opus"; brief = "do A" } }
        lanes        = @(, @("A"))
    }
    $goodPath = Join-Path $tmp "good.json"
    $good | ConvertTo-Json -Depth 8 | Set-Content $goodPath -Encoding utf8

    It "loads a minimal valid config and applies defaults" {
        $c = Read-HandoffConfig $goodPath
        Assert-Equal "main" $c.baseBranch
        Assert-Equal "auto" $c.permissionMode "permissionMode should default to auto"
        Assert-True ($c.stateDir) "stateDir should have a default"
        Assert-True ($c.allowedTools.Count -gt 0) "allowedTools should have a default"
    }
    It "resolves lanes from the session table when lanes are omitted" {
        $noLanes = $good.Clone(); $noLanes.Remove("lanes")
        $p = Join-Path $tmp "nolanes.json"; $noLanes | ConvertTo-Json -Depth 8 | Set-Content $p -Encoding utf8
        $c = Read-HandoffConfig $p
        Assert-Equal 1 $c.lanes.Count "one lane per session when unspecified"
    }
    It "keeps a multi-session lane as ONE lane, not one lane per session" {
        # PowerShell's pipeline unrolls nested arrays. Losing this collapses
        # 'run E then A in sequence' into 'run E and A at once', which is the
        # exact contention the lane existed to prevent.
        $two = $good.Clone()
        $two.sessions = @{ A = @{ name = "alpha"; model = "opus"; brief = "a" }
                           B = @{ name = "beta";  model = "opus"; brief = "b" } }
        $two.lanes = @(, @("A", "B"))
        $p = Join-Path $tmp "onelane.json"; $two | ConvertTo-Json -Depth 8 | Set-Content $p -Encoding utf8
        $c = Read-HandoffConfig $p
        Assert-Equal 1 $c.lanes.Count "expected a single lane"
        Assert-Equal "A,B" ($c.lanes[0] -join ",") "expected both sessions in lane 1, in order"
    }
    It "keeps two lanes of two distinct" {
        $four = $good.Clone()
        $four.sessions = @{ A = @{ name = "a"; model = "opus"; brief = "a" }; B = @{ name = "b"; model = "opus"; brief = "b" }
                            C = @{ name = "c"; model = "opus"; brief = "c" }; D = @{ name = "d"; model = "opus"; brief = "d" } }
        $four.lanes = @(@("A", "B"), @("C", "D"))
        $p = Join-Path $tmp "twolanes.json"; $four | ConvertTo-Json -Depth 8 | Set-Content $p -Encoding utf8
        $c = Read-HandoffConfig $p
        Assert-Equal 2 $c.lanes.Count
        Assert-Equal "A,B" ($c.lanes[0] -join ",")
        Assert-Equal "C,D" ($c.lanes[1] -join ",")
    }
    It "accepts the comma-string lane form too" {
        $cs = $good.Clone()
        $cs.sessions = @{ A = @{ name = "a"; model = "opus"; brief = "a" }; B = @{ name = "b"; model = "opus"; brief = "b" } }
        $cs.lanes = @("A,B")
        $p = Join-Path $tmp "commalane.json"; $cs | ConvertTo-Json -Depth 8 | Set-Content $p -Encoding utf8
        $c = Read-HandoffConfig $p
        Assert-Equal 1 $c.lanes.Count
        Assert-Equal "A,B" ($c.lanes[0] -join ",")
    }

    Write-Host "`nConvertTo-HandoffHash array nesting"
    It "preserves nested arrays instead of unrolling them through the pipeline" {
        $o = '{"lanes":[["A","B"],["C"]]}' | ConvertFrom-Json
        $h = ConvertTo-HandoffHash $o
        Assert-Equal 2 $h["lanes"].Count "outer array should keep 2 elements"
        Assert-Equal "A,B" ($h["lanes"][0] -join ",")
    }
    It "rejects a config whose lane names a session that does not exist" {
        $bad = $good.Clone(); $bad.lanes = @(, @("A", "ZZ"))
        $p = Join-Path $tmp "badlane.json"; $bad | ConvertTo-Json -Depth 8 | Set-Content $p -Encoding utf8
        Assert-Throws { Read-HandoffConfig $p } "ZZ"
    }
    It "rejects a config with no sessions" {
        $bad = $good.Clone(); $bad.sessions = @{}
        $p = Join-Path $tmp "nosessions.json"; $bad | ConvertTo-Json -Depth 8 | Set-Content $p -Encoding utf8
        Assert-Throws { Read-HandoffConfig $p } "sessions"
    }
    It "rejects a session missing its model" {
        $bad = $good.Clone(); $bad.sessions = @{ A = @{ name = "alpha"; brief = "x" } }
        $p = Join-Path $tmp "nomodel.json"; $bad | ConvertTo-Json -Depth 8 | Set-Content $p -Encoding utf8
        Assert-Throws { Read-HandoffConfig $p } "model"
    }
    It "rejects a missing config file with a path in the message" {
        Assert-Throws { Read-HandoffConfig (Join-Path $tmp "absent.json") } "absent.json"
    }
    It "reads a brief from briefFile when brief is not inline" {
        $bf = Join-Path $tmp "brief-a.md"; "brief body" | Set-Content $bf -Encoding utf8
        $c2 = $good.Clone(); $c2.sessions = @{ A = @{ name = "alpha"; model = "opus"; briefFile = "brief-a.md" } }
        $p = Join-Path $tmp "brieffile.json"; $c2 | ConvertTo-Json -Depth 8 | Set-Content $p -Encoding utf8
        $c = Read-HandoffConfig $p
        Assert-Equal "brief body" (Resolve-HandoffBrief $c $c.sessions["A"]).Trim()
    }

    Write-Host "`nState round-trip"
    It "writes and reads back state, surviving PS 5.1's lack of -AsHashtable" {
        $sf = Join-Path $tmp "state.json"
        Write-HandoffState $sf @{ A = @{ status = "merged"; session_id = "abc123" } }
        $s = Read-HandoffState $sf
        Assert-Equal "merged" $s["A"]["status"]
        Assert-Equal "abc123" $s["A"]["session_id"]
    }
    It "returns an empty table for a missing or corrupt state file" {
        Assert-Equal 0 (Read-HandoffState (Join-Path $tmp "none.json")).Count
        $bad = Join-Path $tmp "corrupt.json"; "{not json" | Set-Content $bad -Encoding utf8
        Assert-Equal 0 (Read-HandoffState $bad).Count
    }

    Write-Host "`nGuard command construction"
    It "builds the guard command from config, expanding {{guards}} to the path list" {
        $c = Read-HandoffConfig $goodPath
        $c.guards = @{ command = "pytest"; args = @("-q", "{{guards}}"); paths = @("t/a.py", "t/b.py") }
        $cmd = Build-HandoffGuardCommand $c @{}
        Assert-Equal "pytest" $cmd.command
        Assert-Equal "-q,t/a.py,t/b.py" ($cmd.args -join ",")
    }
    It "reports no guards when the config declares none, rather than inventing pytest" {
        $c = Read-HandoffConfig $goodPath
        Assert-True ($null -eq (Build-HandoffGuardCommand $c @{})) "guards must be opt-in"
    }
}
finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }

Write-Host "`n$($script:Ran) assertions, $($script:Failures) failed."
exit $script:Failures

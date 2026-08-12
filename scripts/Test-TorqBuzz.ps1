<#
.SYNOPSIS
  T01-T35 harness. C1 executes only cases that need no C2-C6 live authority.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^T\d{2}$|^ALL_C1$')]
    [string]$Case,

    [string]$Root = "E:\TORQ-BUZZ",
    [string]$RunId = [guid]::NewGuid().ToString()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PIN = "3e48f1b2365d326ee1c9582448d86a99b44ecd5d"
$prod = Join-Path $Root "source\buzz"
$evRoot = Join-Path $Root "evidence\T-cases\$Case\$RunId"
New-Item -ItemType Directory -Force -Path $evRoot | Out-Null

function Write-Result($case, $status, $detail) {
    $obj = [ordered]@{
        schema_version = 1
        case = $case
        status = $status
        detail = $detail
        run_id = $RunId
        utc = (Get-Date).ToUniversalTime().ToString("o")
    }
    $obj | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evRoot "result.json") -Encoding utf8
    Write-Host "$case $status - $detail"
    if ($status -eq "PASS") { exit 0 }
    if ($status -eq "BLOCKED") { exit 2 }
    exit 1
}

function Test-T01 {
    Push-Location $prod
    $head = git rev-parse HEAD
    Pop-Location
    if ($head -ne $PIN) { Write-Result "T01" "FAIL" "HEAD $head != $PIN" }
    Write-Result "T01" "PASS" "production HEAD pinned $PIN"
}

function Test-T02 {
    Push-Location $prod
    $porcelain = @(git status --porcelain)
    $fence = git diff -- crates/buzz-db/src/replica_fence.rs
    Pop-Location
    # Allow only the reviewed TORQ overlay patch paths
    $allowed = @(
        "crates/buzz-acp/src/acp.rs",
        "crates/buzz-relay/src/config.rs",
        "crates/buzz-relay/src/main.rs",
        "crates/buzz-relay/src/metrics.rs"
    )
    $unexpected = @()
    foreach ($line in $porcelain) {
        $path = ($line -replace '^\s*[AM?]{1,2}\s+', '').Trim()
        $path = $path -replace '\\', '/'
        if ($allowed -notcontains $path) { $unexpected += $path }
    }
    if ($fence -and $fence.Trim().Length -gt 0) {
        Write-Result "T02" "FAIL" "replica_fence.rs dirty in production worktree"
    }
    if ($unexpected.Count -gt 0) {
        Write-Result "T02" "FAIL" ("unexpected dirty: " + ($unexpected -join ', '))
    }
    Write-Result "T02" "PASS" "clean except reviewed TORQ overlay deltas; no replica_fence patch"
}

function Test-T03 {
    & (Join-Path $Root "scripts\Test-TorqDependencies.ps1") -Root $Root -RunId $RunId | Out-Null
    Write-Result "T03" "PASS" "dependency preflight recorded (no installs)"
}

function Test-T29 {
    $scanRoots = @(
        (Join-Path $Root "crates"),
        (Join-Path $Root "scripts"),
        (Join-Path $Root "schemas"),
        (Join-Path $Root "config"),
        (Join-Path $Root "compose"),
        (Join-Path $Root "docs")
    )
    $patterns = @('nsec1[a-z0-9]{20,}', 'sk-[A-Za-z0-9]{20,}')
    $hits = 0
    foreach ($r in $scanRoots) {
        if (-not (Test-Path $r)) { continue }
        Get-ChildItem $r -Recurse -File -EA SilentlyContinue | Where-Object {
            $_.FullName -notmatch '\\target\\' -and $_.Extension -match '\.(rs|ps1|json|md|yml|env|template)$'
        } | ForEach-Object {
            $t = Get-Content $_.FullName -Raw -EA SilentlyContinue
            if (-not $t) { return }
            foreach ($p in $patterns) {
                if ($t -match $p) { $hits++ }
            }
        }
    }
    if ($hits -gt 0) { Write-Result "T29" "FAIL" "hard secret pattern hits=$hits" }
    Write-Result "T29" "PASS" "no hard secret patterns in C1 artifacts"
}

function Test-Blocked($case, $gate) {
    Write-Result $case "BLOCKED" "requires operator gate $gate (not authorized under C1)"
}

function Invoke-Case($c) {
    switch ($c) {
        "T01" { Test-T01 }
        "T02" { Test-T02 }
        "T03" { Test-T03 }
        "T04" { Test-Blocked $c "C1+build_auth_or_long_build (frontend)" }
        "T05" { Test-Blocked $c "C1+desktop_package_auth" }
        "T06" { Test-Blocked $c "C1+relay_release_build" }
        "T07" { Test-Blocked $c "C5_portable_runtime" }
        "T08" { Test-Blocked $c "C5" }
        "T09" { Test-Blocked $c "C5" }
        "T10" { Test-Blocked $c "C5" }
        "T11" { Test-Blocked $c "C5" }
        "T12" { Test-Blocked $c "C5" }
        "T13" { Test-Blocked $c "C5" }
        "T14" { Test-Blocked $c "C5" }
        "T15" { Test-Blocked $c "C5" }
        "T16" { Test-Blocked $c "C5" }
        "T17" { Test-Blocked $c "C2+C3+C4" }
        "T18" { Test-Blocked $c "C5" }
        "T19" { Test-Blocked $c "C5" }
        "T20" { Test-Blocked $c "C2+C3+C4" }
        "T21" { Test-Blocked $c "C2+C3+C4" }
        "T22" { Test-Blocked $c "C2+C3+C4" }
        "T23" { Test-Blocked $c "C5" }
        "T24" { Test-Blocked $c "C5" }
        "T25" { Test-Blocked $c "C5" }
        "T26" { Test-Blocked $c "C5" }
        "T27" { Test-Blocked $c "C5" }
        "T28" { Test-Blocked $c "C2" }
        "T29" { Test-T29 }
        "T30" { Test-Blocked $c "C6" }
        "T31" { Test-Blocked $c "C5" }
        "T32" { Test-Blocked $c "C5" }
        "T33" { Test-Blocked $c "C5" }
        "T34" { Test-Blocked $c "C5" }
        "T35" { Test-Blocked $c "C5" }
        default { Write-Result $c "FAIL" "unknown case" }
    }
}

if ($Case -eq "ALL_C1") {
    $c1 = @("T01","T02","T03","T29")
    $summary = @()
    foreach ($c in $c1) {
        $sub = [guid]::NewGuid().ToString()
        $p = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile","-File",(Join-Path $Root "scripts\Test-TorqBuzz.ps1"),
            "-Case",$c,"-Root",$Root,"-RunId",$sub
        ) -Wait -PassThru -NoNewWindow
        $summary += [ordered]@{ case = $c; exit = $p.ExitCode }
    }
    $summary | ConvertTo-Json | Set-Content (Join-Path $evRoot "all_c1_summary.json") -Encoding utf8
    $bad = @($summary | Where-Object { $_.exit -ne 0 })
    if ($bad.Count -gt 0) { Write-Host "ALL_C1 had failures"; exit 1 }
    Write-Host "ALL_C1 PASS"
    exit 0
}

Invoke-Case $Case

<#
.SYNOPSIS
  Receipt-stability test (bounded, pre-C2).
  Validates the live receipt against the live permanent relay, backs it up,
  atomically rewrites the EXACT same bytes, verifies immediately, waits 120s,
  verifies again. Fails on any drift. Never starts/stops processes.
#>
[CmdletBinding()]
param(
    [string]$Root = "E:\TORQ-BUZZ",
    [string]$RunId = "receipt-stability-final",
    [int]$WaitSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$evidence = Join-Path $Root "evidence\c5\receipt-stability\$RunId"
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$receiptPath = Join-Path $Root "state\relay-process.json"

function Get-Prop($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    $p = $obj.PSObject.Properties[$name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Test-ReceiptVsLive([string]$path, [string]$label) {
    if (-not (Test-Path $path)) { throw "[$label] receipt missing: $path" }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $sha = (Get-FileHash $path -Algorithm SHA256).Hash
    $r = Get-Content $path -Raw | ConvertFrom-Json
    $rPid = [int](Get-Prop $r 'pid')
    $runId = Get-Prop $r 'launcher_run_id'
    $exe = Get-Prop $r 'executable_path'
    $exeSha = Get-Prop $r 'executable_sha256'
    $proc = Get-Process -Id $rPid -ErrorAction SilentlyContinue
    if ($null -eq $proc) { throw "[$label] receipt pid $rPid not alive" }
    if ([string]$proc.Path -ine [string]$exe) { throw "[$label] path mismatch: $($proc.Path) vs $exe" }
    $liveSha = (Get-FileHash ([string]$proc.Path) -Algorithm SHA256).Hash
    if ($liveSha -ine [string]$exeSha) { throw "[$label] exe sha mismatch" }
    if ((Get-Prop $r 'role') -ne "permanent-relay") { throw "[$label] role mismatch" }
    return [ordered]@{
        label = $label; file_sha256 = $sha; pid = $rPid; run_id = $runId
        executable_path = $exe; executable_sha256 = $exeSha
        live_match = $true; utc = (Get-Date).ToUniversalTime().ToString("o")
    }
}

# 1. validate current receipt vs live
$before = Test-ReceiptVsLive $receiptPath "before"

# 2. back up into evidence
Copy-Item $receiptPath (Join-Path $evidence "receipt.before.json") -Force

# 3. atomic rewrite of the exact same bytes (temp file in same dir, then replace)
$sameBytes = [System.IO.File]::ReadAllBytes($receiptPath)
$tmp = Join-Path $Root ("state\relay-process.json.tmp-" + $RunId)
[System.IO.File]::WriteAllBytes($tmp, $sameBytes)
Move-Item -Path $tmp -Destination $receiptPath -Force

# 4. immediate verify
$immediate = Test-ReceiptVsLive $receiptPath "immediate"
if ($immediate.file_sha256 -ne $before.file_sha256) { throw "immediate hash differs from before" }

# 5-6. wait and re-verify
Start-Sleep -Seconds $WaitSeconds
$after = Test-ReceiptVsLive $receiptPath "after"

$drift = @()
if ($after.file_sha256 -ne $before.file_sha256) { $drift += "file hash changed" }
if ($after.pid -ne $before.pid) { $drift += "pid reverted" }
if ($after.run_id -ne $before.run_id) { $drift += "run id changed" }

$result = [ordered]@{
    run_id = $RunId; wait_seconds = $WaitSeconds
    before = $before; immediate = $immediate; after = $after
    drift = $drift; pass = ($drift.Count -eq 0)
    utc = (Get-Date).ToUniversalTime().ToString("o")
}
$result | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidence "stability-result.json") -Encoding utf8

if ($drift.Count -gt 0) {
    Write-Host "FAIL: receipt stability - $($drift -join ', ')"
    exit 1
}
Write-Host "PASS: receipt stable ($RunId). hash=$($before.file_sha256) pid=$($before.pid) run=$($before.run_id)"
exit 0

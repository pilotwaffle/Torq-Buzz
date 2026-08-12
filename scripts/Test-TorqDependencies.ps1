<#
.SYNOPSIS
  Dependency preflight (read-only). No installs.
#>
[CmdletBinding()]
param(
    [string]$Root = "E:\TORQ-BUZZ",
    [string]$RunId = [guid]::NewGuid().ToString()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ev = Join-Path $Root "evidence\c1\deps\$RunId"
New-Item -ItemType Directory -Force -Path $ev | Out-Null

function Probe($name, $script) {
    try {
        $v = & $script
        return [ordered]@{ name = $name; ok = $true; value = "$v" }
    } catch {
        return [ordered]@{ name = $name; ok = $false; value = "$_" }
    }
}

$results = @(
    (Probe "rustc" { rustc --version }),
    (Probe "cargo" { cargo --version }),
    (Probe "git" { git --version }),
    (Probe "docker" { docker --version })
)

$report = [ordered]@{
    schema_version = 1
    run_id = $RunId
    results = $results
    installs_performed = $false
    utc = (Get-Date).ToUniversalTime().ToString("o")
}
$report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $ev "deps.json") -Encoding utf8
$failed = @($results | Where-Object { -not $_.ok })
if ($failed.Count -gt 0) {
    Write-Host "Some tools missing (non-fatal for C1 prep): $($failed.name -join ', ')"
    exit 0  # C1 prep still succeeds; missing docker is expected/fine
}
exit 0

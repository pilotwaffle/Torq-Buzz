<#
.SYNOPSIS
  Initialize TORQ Buzz permanent root layout (C1: filesystem prep only; no Docker).
#>
[CmdletBinding()]
param(
    [string]$Root = "E:\TORQ-BUZZ",
    [string]$RunId = [guid]::NewGuid().ToString()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$dirs = @(
    "bin","config","compose","scripts","schemas","evidence","state","logs","releases","docs","patches","harnesses","data\relay\git","data\relay\git-pack-cache"
)
foreach ($d in $dirs) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Root $d) | Out-Null
}

# Copy templates to non-secret example runtime paths if missing
$pairs = @{
    "config\relay.env.template" = "config\relay.env.example"
    "config\postgres.env.template" = "config\postgres.env.example"
    "config\minio.env.template" = "config\minio.env.example"
    "config\compose.images.env.template" = "config\compose.images.env.example"
}
foreach ($k in $pairs.Keys) {
    $src = Join-Path $Root $k
    $dst = Join-Path $Root $pairs[$k]
    if ((Test-Path $src) -and -not (Test-Path $dst)) {
        Copy-Item $src $dst
    }
}

$ev = Join-Path $Root "evidence\c1\initialize\$RunId"
New-Item -ItemType Directory -Force -Path $ev | Out-Null
@{
    schema_version = 1
    run_id = $RunId
    root = $Root
    docker_mutated = $false
    note = "C1 initialize: layout only"
    utc = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json | Set-Content (Join-Path $ev "initialize-receipt.json") -Encoding utf8

Write-Host "Initialized layout under $Root (no Docker)."
exit 0

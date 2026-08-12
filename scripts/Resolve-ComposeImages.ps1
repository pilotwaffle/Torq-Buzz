<#
.SYNOPSIS
  Resolve compose image tags to digests (C1: dry-run records plan only; no docker pull).
#>
[CmdletBinding()]
param(
    [string]$Root = "E:\TORQ-BUZZ",
    [string]$RunId = [guid]::NewGuid().ToString(),
    [switch]$DryRun = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ev = Join-Path $Root "evidence\c1\compose-images\$RunId"
New-Item -ItemType Directory -Force -Path $ev | Out-Null

$template = Join-Path $Root "config\compose.images.env.template"
$out = [ordered]@{
    schema_version = 1
    run_id = $RunId
    dry_run = [bool]$DryRun
    template = $template
    resolved = $false
    note = "C1: no docker inspect/pull authorized. Operator must authorize C5 before digest pin write to compose.images.env"
    images_from_template = Get-Content $template -ErrorAction SilentlyContinue
    utc = (Get-Date).ToUniversalTime().ToString("o")
}
$out | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $ev "resolve-plan.json") -Encoding utf8
Write-Host "Compose image resolve dry-run only. No Docker mutation."
exit 0

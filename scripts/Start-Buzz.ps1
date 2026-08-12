<#
.SYNOPSIS
  Start TORQ Buzz permanent stack (C1: dry-run / plan only unless -ForceLive which is BLOCKED).

.DESCRIPTION
  C1 authorization: prepares and validates start plan; refuses live process start and Docker up.
  Live activation requires C5 (and related) operator authorization.
#>
[CmdletBinding()]
param(
    [string]$RunId = [guid]::NewGuid().ToString(),
    [string]$Root = "E:\TORQ-BUZZ",
    [switch]$DryRun = $true,
    [switch]$ForceLive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($ForceLive) {
    throw "ForceLive blocked under C1. Requires C5 operator authorization for permanent Compose/relay start."
}

$evidence = Join-Path $Root "evidence\c1\start\$RunId"
New-Item -ItemType Directory -Force -Path $evidence | Out-Null

$plan = [ordered]@{
    schema_version = 1
    role           = "start-plan"
    run_id         = $RunId
    dry_run        = [bool]$DryRun
    root           = $Root
    relay_env_template = (Join-Path $Root "config\relay.env.template")
    compose_file   = (Join-Path $Root "compose\compose.torq-buzz.yml")
    ports          = Get-Content (Join-Path $Root "config\ports.json") -Raw | ConvertFrom-Json
    steps_planned  = @(
        "preflight-config-present",
        "preflight-production-source-pin",
        "compose-up (C5)",
        "relay-start (C5)",
        "health-wait (C5)",
        "write-startup-receipt (C5)"
    )
    blocked_reason = "C1 only - no Docker mutation, no live relay start"
    utc            = (Get-Date).ToUniversalTime().ToString("o")
}

$plan | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidence "start-plan.json") -Encoding utf8
Write-Host "Start-Buzz dry-run plan written: $evidence\start-plan.json"
Write-Host "No processes started. No Docker changes."
exit 0

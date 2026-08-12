<#
.SYNOPSIS
  Install TORQ Buzz custom ACP harness definitions into the Buzz desktop app data directory.

.DESCRIPTION
  Copies only the reviewed JSON harness definitions from the repository's harnesses/
  directory. Existing files are preserved unless -Force is supplied. No credentials
  are read, printed, or modified.
#>
[CmdletBinding()]
param(
    [string]$Root = "E:\TORQ-BUZZ",
    [string]$AppDataRoot = (Join-Path $env:APPDATA "xyz.block.buzz.app"),
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sourceDir = Join-Path $Root "harnesses"
$targetDir = Join-Path $AppDataRoot "custom_harnesses"
if (-not (Test-Path $sourceDir)) { throw "Harness source directory not found: $sourceDir" }

New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

$installed = 0
$skipped = 0
foreach ($file in Get-ChildItem -Path $sourceDir -Filter "*.json" -File | Sort-Object Name) {
    $target = Join-Path $targetDir $file.Name
    if ((Test-Path $target) -and -not $Force) {
        Write-Host "Skipped existing harness: $($file.Name)"
        $skipped++
        continue
    }
    Copy-Item -Path $file.FullName -Destination $target -Force
    Write-Host "Installed harness: $($file.Name)"
    $installed++
}

Write-Host "Harness install complete: $installed installed, $skipped skipped."
exit 0

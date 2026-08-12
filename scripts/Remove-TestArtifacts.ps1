<#
.SYNOPSIS
  Remove only evidence artifacts registered for a run id under evidence/.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    [string]$Root = "E:\TORQ-BUZZ"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Only delete directories named exactly the run id under evidence
$hits = Get-ChildItem (Join-Path $Root "evidence") -Recurse -Directory -EA SilentlyContinue |
    Where-Object { $_.Name -eq $RunId }
foreach ($h in $hits) {
    # Safety: path must be under evidence
    if ($h.FullName -notlike (Join-Path $Root "evidence*")) {
        throw "Refusing path outside evidence: $($h.FullName)"
    }
    Remove-Item -Recurse -Force $h.FullName
    Write-Host "Removed $($h.FullName)"
}
Write-Host "Done. Never deletes pilot or Docker volumes."
exit 0

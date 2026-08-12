<#
.SYNOPSIS
  Stop TORQ Buzz permanent relay using receipt-owned matching only.

.DESCRIPTION
  NEVER kills by process name. Live stop requires every ownership field on
  state\relay-process.json to match the live process. Pilot or unrelated
  buzz-relay.exe processes are never stopped.

  Default Mode=DryRun (plan only). Live requires -Mode Live -ConfirmLiveStop.
#>
[CmdletBinding()]
param(
    [string]$RunId = [guid]::NewGuid().ToString(),
    [string]$Root = "E:\TORQ-BUZZ",
    [string]$ReceiptPath = "",
    [ValidateSet("DryRun", "Live")]
    [string]$Mode = "DryRun",
    [switch]$ConfirmLiveStop,
    # Test hooks
    [string]$TestInventoryPath = "",
    [switch]$AllowTestHarness
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RedactedCommandLineHash {
    param([string]$CommandLine)
    if ([string]::IsNullOrEmpty($CommandLine)) { return $null }
    $red = $CommandLine
    $red = $red -replace 'postgres://[^ \t"]+', 'postgres://***'
    $red = $red -replace '(?i)(PASSWORD|SECRET|KEY|TOKEN|NSEC)=[^ \t"]+', '$1=***'
    $red = $red -replace 'nsec1[a-z0-9]+', 'nsec1***'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($red)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Test-ReceiptOwnership {
    param(
        [Parameter(Mandatory = $true)]$Receipt,
        $Live
    )
    $errors = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Live) {
        $errors.Add("no live process for receipt pid")
        return @{ ok = $false; errors = @($errors) }
    }
    if ([int]$Live.pid -ne [int]$Receipt.pid) { $errors.Add("pid mismatch") }

    $livePath = ([string]$Live.executable_path).TrimEnd('\')
    $recPath = ([string]$Receipt.executable_path).TrimEnd('\')
    if ($livePath.ToLowerInvariant() -ne $recPath.ToLowerInvariant()) {
        $errors.Add("executable_path mismatch")
    }
    if ([string]$Live.executable_sha256 -ne [string]$Receipt.executable_sha256) {
        $errors.Add("executable_sha256 mismatch")
    }

    $role = [string]$Receipt.role
    if ($role -ne "permanent-relay" -and $role -ne "relay") {
        $errors.Add("role not permanent-relay (got '$role')")
    }
    if ($role -eq "relay") {
        if ($recPath -notmatch '(?i)[\\/]TORQ-BUZZ[\\/]bin[\\/]buzz-relay\.exe$') {
            $errors.Add("legacy role=relay without permanent bin path")
        }
    }

    if ($Receipt.PSObject.Properties.Name -contains "launcher_run_id" -and
        $Live.PSObject.Properties.Name -contains "launcher_run_id") {
        if ($Live.launcher_run_id -and $Receipt.launcher_run_id -and
            ([string]$Live.launcher_run_id -ne [string]$Receipt.launcher_run_id)) {
            $errors.Add("launcher_run_id mismatch")
        }
    }

    $recProps = @($Receipt.PSObject.Properties.Name)
    $liveProps = @($Live.PSObject.Properties.Name)

    if ($recProps -contains "command_line_redacted_sha256" -and $Receipt.command_line_redacted_sha256) {
        $liveHash = Get-RedactedCommandLineHash -CommandLine ([string]$Live.command_line)
        if (-not $liveHash -or $liveHash -ne [string]$Receipt.command_line_redacted_sha256) {
            $errors.Add("command_line_redacted_sha256 mismatch")
        }
    }

    if (($recProps -contains "creation_time_utc") -and ($liveProps -contains "creation_time_utc") -and
        $Receipt.creation_time_utc -and $Live.creation_time_utc) {
        $a = ([string]$Receipt.creation_time_utc)
        $b = ([string]$Live.creation_time_utc)
        $a = $a.Substring(0, [Math]::Min(19, $a.Length))
        $b = $b.Substring(0, [Math]::Min(19, $b.Length))
        if ($a -ne $b) { $errors.Add("creation_time_utc mismatch") }
    }

    return @{ ok = ($errors.Count -eq 0); errors = @($errors) }
}

function Get-LiveProcessInventory {
    param([int]$PidTarget)
    $p = Get-Process -Id $PidTarget -ErrorAction SilentlyContinue
    if (-not $p) { return $null }
    $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$PidTarget" -ErrorAction SilentlyContinue
    $path = $null
    if ($p.Path) { $path = $p.Path }
    elseif ($cim -and $cim.ExecutablePath) { $path = $cim.ExecutablePath }
    $hash = $null
    if ($path -and (Test-Path -LiteralPath $path)) {
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    $created = $null
    if ($cim -and $cim.CreationDate) {
        $created = $cim.CreationDate.ToUniversalTime().ToString("o")
    }
    return [pscustomobject]@{
        pid                 = $PidTarget
        executable_path     = $path
        executable_sha256   = $hash
        command_line        = if ($cim) { $cim.CommandLine } else { $null }
        creation_time_utc   = $created
        name                = $p.ProcessName
    }
}

if (-not $ReceiptPath) {
    $ReceiptPath = Join-Path $Root "state\relay-process.json"
}

$evidenceRoot = if ($AllowTestHarness) {
    Join-Path $Root "evidence\c5\stop-tests\$RunId"
} else {
    Join-Path $Root "evidence\c5\stop\$RunId"
}
New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null

$result = [ordered]@{
    schema_version = 1
    role           = "stop-result"
    run_id         = $RunId
    mode           = $Mode
    receipt_path   = $ReceiptPath
    stopped        = $false
    matched        = $false
    refused        = $false
    errors         = @()
    policy         = "receipt-owned-PID-only; never kill by process name"
    utc            = (Get-Date).ToUniversalTime().ToString("o")
}

if (-not (Test-Path -LiteralPath $ReceiptPath)) {
    $result.refused = $true
    $result.errors = @("receipt missing: $ReceiptPath")
    $result | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidenceRoot "stop-result.json") -Encoding utf8
    Write-Host "REFUSED: no receipt"
    exit 20
}

$receipt = Get-Content -LiteralPath $ReceiptPath -Raw -Encoding utf8 | ConvertFrom-Json

$live = $null
if ($TestInventoryPath -and $AllowTestHarness) {
    if (-not (Test-Path -LiteralPath $TestInventoryPath)) {
        throw "TestInventoryPath missing: $TestInventoryPath"
    }
    $live = Get-Content -LiteralPath $TestInventoryPath -Raw -Encoding utf8 | ConvertFrom-Json
} else {
    $live = Get-LiveProcessInventory -PidTarget ([int]$receipt.pid)
}

$match = Test-ReceiptOwnership -Receipt $receipt -Live $live
$result.matched = [bool]$match.ok
$result.errors = @($match.errors)

if (-not $match.ok) {
    $result.refused = $true
    $result | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidenceRoot "stop-result.json") -Encoding utf8
    Write-Host "REFUSED: ownership mismatch: $($match.errors -join '; ')"
    exit 21
}

if ($Mode -eq "DryRun" -or -not $ConfirmLiveStop) {
    $result.stopped = $false
    $result.note = "ownership matched; dry-run or missing -ConfirmLiveStop - process not stopped"
    $result | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidenceRoot "stop-result.json") -Encoding utf8
    Write-Host "MATCH dry-run: would stop PID $($receipt.pid) only (receipt-owned)."
    exit 0
}

if ($Mode -ne "Live") {
    throw "invalid mode"
}

# Live stop: re-check then Stop-Process -Id ONLY (never by name)
$recheck = if ($TestInventoryPath -and $AllowTestHarness) {
    $live
} else {
    Get-LiveProcessInventory -PidTarget ([int]$receipt.pid)
}
$match2 = Test-ReceiptOwnership -Receipt $receipt -Live $recheck
if (-not $match2.ok) {
    $result.refused = $true
    $result.errors = @($match2.errors)
    $result.note = "ownership lost before stop"
    $result | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidenceRoot "stop-result.json") -Encoding utf8
    Write-Host "REFUSED: ownership lost before stop"
    exit 22
}

if ($AllowTestHarness -and $TestInventoryPath) {
    # Harness live stop: do not kill real processes; record would_stop
    $result.stopped = $false
    $result.would_stop_pid = [int]$receipt.pid
    $result.note = "test harness simulated live stop (no process killed)"
    $result | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidenceRoot "stop-result.json") -Encoding utf8
    Write-Host "TEST HARNESS: would stop PID $($receipt.pid) only"
    exit 0
}

Stop-Process -Id ([int]$receipt.pid) -Force -ErrorAction Stop
$result.stopped = $true
$result.note = "stopped receipt-owned PID only"
$result | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidenceRoot "stop-result.json") -Encoding utf8
Write-Host "STOPPED PID $($receipt.pid) (receipt-owned only)"
exit 0

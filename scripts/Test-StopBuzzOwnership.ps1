<#
.SYNOPSIS
  Regression: Stop-Buzz refuses pilot/unrelated buzz-relay; matches permanent receipt only.
#>
[CmdletBinding()]
param(
    [string]$Root = "E:\TORQ-BUZZ",
    [string]$RunId = [guid]::NewGuid().ToString()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ev = Join-Path $Root "evidence\c5\stop-tests\$RunId"
New-Item -ItemType Directory -Force -Path $ev | Out-Null
$stopScript = Join-Path $Root "scripts\Stop-Buzz.ps1"
$failures = New-Object System.Collections.Generic.List[string]

function Invoke-Stop {
    param(
        [string]$ReceiptPath,
        [string]$Mode = "DryRun",
        [string]$SubRunId,
        [string]$TestInventoryPath = "",
        [switch]$ConfirmLiveStop
    )
    $argList = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $stopScript,
        "-Root", $Root,
        "-RunId", $SubRunId,
        "-ReceiptPath", $ReceiptPath,
        "-Mode", $Mode,
        "-AllowTestHarness"
    )
    if ($ConfirmLiveStop) { $argList += "-ConfirmLiveStop" }
    if ($TestInventoryPath) {
        $argList += @("-TestInventoryPath", $TestInventoryPath)
    }
    $p = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput (Join-Path $ev "$SubRunId.out") `
        -RedirectStandardError (Join-Path $ev "$SubRunId.err")
    return $p.ExitCode
}

# T1: pilot-shaped live process vs permanent receipt -> refuse 21
$r1 = Join-Path $ev "receipt-unrelated.json"
@{
    schema_version = 1; role = "permanent-relay"; launcher_run_id = "test-run"
    receipt_nonce = "nonce-1"; pid = 999001
    executable_path = "E:\TORQ-BUZZ\bin\buzz-relay.exe"
    executable_sha256 = ("A" * 64)
    creation_time_utc = "2026-01-01T00:00:00Z"
} | ConvertTo-Json | Set-Content $r1 -Encoding utf8
$l1 = Join-Path $ev "live-pilot-shaped.json"
@{
    pid = 999001
    executable_path = "E:\TORQ-CONSOLE\tmp\buzz-pilot\20260731-004310\source\buzz\target\debug\buzz-relay.exe"
    executable_sha256 = ("B" * 64)
    command_line = "pilot\buzz-relay.exe"
    creation_time_utc = "2026-01-01T00:00:00Z"
    name = "buzz-relay"
} | ConvertTo-Json | Set-Content $l1 -Encoding utf8
$c1 = Invoke-Stop -ReceiptPath $r1 -Mode Live -SubRunId "$RunId-t1" -TestInventoryPath $l1 -ConfirmLiveStop
if ($c1 -ne 21) { $failures.Add("T1 expected 21 got $c1") }

# T2: pilot role receipt refused even if path matches inventory
$r2 = Join-Path $ev "receipt-pilot-role.json"
@{
    schema_version = 1; role = "pilot-relay"; launcher_run_id = "pilot"
    receipt_nonce = "n2"; pid = 999002
    executable_path = "E:\TORQ-CONSOLE\tmp\buzz-pilot\20260731-004310\source\buzz\target\debug\buzz-relay.exe"
    executable_sha256 = ("C" * 64)
    creation_time_utc = "2026-01-01T00:00:00Z"
} | ConvertTo-Json | Set-Content $r2 -Encoding utf8
$l2 = Join-Path $ev "live-pilot.json"
@{
    pid = 999002
    executable_path = "E:\TORQ-CONSOLE\tmp\buzz-pilot\20260731-004310\source\buzz\target\debug\buzz-relay.exe"
    executable_sha256 = ("C" * 64)
    command_line = "pilot"
    creation_time_utc = "2026-01-01T00:00:00Z"
    name = "buzz-relay"
} | ConvertTo-Json | Set-Content $l2 -Encoding utf8
$c2 = Invoke-Stop -ReceiptPath $r2 -Mode Live -SubRunId "$RunId-t2" -TestInventoryPath $l2 -ConfirmLiveStop
if ($c2 -ne 21) { $failures.Add("T2 expected 21 got $c2") }

# T3: perfect permanent match dry-run succeeds without killing
$r3 = Join-Path $ev "receipt-good.json"
$h = "D" * 64
@{
    schema_version = 1; role = "permanent-relay"; launcher_run_id = "c5-test"
    receipt_nonce = "n3"; pid = 999003
    executable_path = "E:\TORQ-BUZZ\bin\buzz-relay.exe"
    executable_sha256 = $h
    creation_time_utc = "2026-08-03T15:00:00Z"
} | ConvertTo-Json | Set-Content $r3 -Encoding utf8
$l3 = Join-Path $ev "live-good.json"
@{
    pid = 999003
    executable_path = "E:\TORQ-BUZZ\bin\buzz-relay.exe"
    executable_sha256 = $h
    command_line = "E:\TORQ-BUZZ\bin\buzz-relay.exe"
    creation_time_utc = "2026-08-03T15:00:00.0000000Z"
    name = "buzz-relay"
} | ConvertTo-Json | Set-Content $l3 -Encoding utf8
$c3 = Invoke-Stop -ReceiptPath $r3 -Mode DryRun -SubRunId "$RunId-t3" -TestInventoryPath $l3
if ($c3 -ne 0) { $failures.Add("T3 expected 0 got $c3") }

# T4: executable code must not call Stop-Process with -Name
$lines = Get-Content $stopScript
$codeLines = $lines | Where-Object {
    $t = $_.Trim()
    -not $t.StartsWith("#") -and $t -notmatch 'policy\s*=' -and $t -notmatch 'never'
}
$bad = @($codeLines | Where-Object { $_ -match 'Stop-Process\s+-Name' })
if ($bad.Count -gt 0) { $failures.Add("T4 executable Stop-Process -Name present: $($bad[0])") }

# T5: missing receipt -> 20
$c5 = Invoke-Stop -ReceiptPath (Join-Path $ev "missing.json") -Mode Live -SubRunId "$RunId-t5" -ConfirmLiveStop
if ($c5 -ne 20) { $failures.Add("T5 expected 20 got $c5") }

# T6: harness live match does not kill (simulated)
$c6 = Invoke-Stop -ReceiptPath $r3 -Mode Live -SubRunId "$RunId-t6" -TestInventoryPath $l3 -ConfirmLiveStop
if ($c6 -ne 0) { $failures.Add("T6 expected 0 simulated live got $c6") }

$summary = [ordered]@{
    schema_version = 1
    run_id = $RunId
    failures = @($failures)
    pass = ($failures.Count -eq 0)
    utc = (Get-Date).ToUniversalTime().ToString("o")
}
$summary | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $ev "summary.json") -Encoding utf8
if ($failures.Count -gt 0) {
    Write-Host "FAIL: $($failures -join ' | ')"
    exit 1
}
Write-Host "PASS: Stop-Buzz ownership regression suite ($RunId)"
exit 0

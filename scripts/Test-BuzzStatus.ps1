<#
.SYNOPSIS
  Bounded test suite for Buzz-Status.ps1 live-state detection.
  Uses fixture receipts only; never replaces the live receipt, never
  starts/stops any process, never mutates Docker.
#>
[CmdletBinding()]
param(
    [string]$Root = "E:\TORQ-BUZZ",
    [string]$RunId = "status-fix-tests"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$failures = @()
$fixtures = Join-Path $Root "evidence\c5\status-tests\$RunId"
New-Item -ItemType Directory -Force -Path $fixtures | Out-Null

$liveReceipt = Join-Path $Root "state\relay-process.json"
$receiptRaw = Get-Content $liveReceipt -Raw
$receipt = $receiptRaw | ConvertFrom-Json
$livePid = [int]$receipt.pid

function Invoke-Status([string]$tag, [string]$receiptPath, [string]$composeFixture = "") {
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $Root "scripts\Buzz-Status.ps1"), "-RunId", $tag, "-Root", $Root)
    if (-not [string]::IsNullOrEmpty($receiptPath)) { $args += @("-ReceiptPath", $receiptPath) }
    if (-not [string]::IsNullOrEmpty($composeFixture)) { $args += @("-ComposeFixturePath", $composeFixture) }
    $out = & powershell @args 2>&1 | Out-String
    $code = $LASTEXITCODE
    $statusFile = Join-Path $Root "evidence\c5\status\$tag\status.json"
    if (-not (Test-Path $statusFile)) { throw "status.json not produced for $tag`n$out" }
    return @{ code = $code; json = (Get-Content $statusFile -Raw | ConvertFrom-Json); console = $out }
}

# T1: live receipt + live process
$t1 = Invoke-Status "$RunId-t1-live" ""
if ($t1.code -ne 0) { $failures.Add("T1 exit $($t1.code)") }
if ($t1.json.permanent_relay.state -ne "running") { $failures.Add("T1 state=$($t1.json.permanent_relay.state) detail=$($t1.json.permanent_relay.detail)") }
if ([int]$t1.json.permanent_relay.pid -ne $livePid) { $failures.Add("T1 pid=$($t1.json.permanent_relay.pid) expected $livePid") }
if (-not $t1.json.permanent_relay.port_3300.listening) { $failures.Add("T1 3300 not listening") }
if (-not $t1.json.permanent_relay.port_8380.listening) { $failures.Add("T1 8380 not listening") }
if (-not $t1.json.permanent_relay.port_9302.listening) { $failures.Add("T1 9302 not listening") }
foreach ($ep in @("liveness", "readiness", "status", "metrics")) {
    if (-not $t1.json.permanent_relay.endpoints.$ep.ok) { $failures.Add("T1 endpoint $ep not ok") }
}
foreach ($c in $t1.json.compose) {
    if (-not $c.present) { $failures.Add("T1 compose $($c.name) missing") }
}
$t1pg = $t1.json.compose | Where-Object { $_.name -eq "torq-buzz-postgres-1" }
$t1rd = $t1.json.compose | Where-Object { $_.name -eq "torq-buzz-redis-1" }
$t1mn = $t1.json.compose | Where-Object { $_.name -eq "torq-buzz-minio-1" }
if ($t1pg.health -ne "healthy" -or $t1pg.healthy -ne $true) { $failures.Add("T1 postgres health=$($t1pg.health)") }
if ($t1rd.health -ne "healthy" -or $t1rd.healthy -ne $true) { $failures.Add("T1 redis health=$($t1rd.health)") }
if ($t1mn.health -notin @("healthy", "up_no_healthcheck")) { $failures.Add("T1 minio health=$($t1mn.health)") }

# T2: pilot separation
$pilotAlive = $null -ne (Get-Process -Name "buzz-relay" -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $livePid })
if (-not $t1.json.pilot.present) { $failures.Add("T2 pilot not reported") }
if ($t1.json.pilot.permanent_owned -ne $false) { $failures.Add("T2 pilot marked permanent-owned") }
if ($pilotAlive -and [int]$t1.json.pilot.pid -eq $livePid) { $failures.Add("T2 pilot pid equals permanent pid") }
if ($t1.json.pilot.present -and [string]$t1.json.pilot.path -like "$Root*") { $failures.Add("T2 pilot path under permanent root") }

# T3: missing receipt fixture
$t3 = Invoke-Status "$RunId-t3-missing" (Join-Path $fixtures "no-such-receipt.json")
if ($t3.json.permanent_relay.state -ne "stale_receipt") { $failures.Add("T3 state=$($t3.json.permanent_relay.state)") }
if ($t3.json.permanent_relay.detail -ne "receipt_missing") { $failures.Add("T3 detail=$($t3.json.permanent_relay.detail)") }

# T4a: wrong-hash fixture
$badHash = $receiptRaw -replace '"executable_sha256":\s*"[^"]+"', '"executable_sha256": "0000000000000000000000000000000000000000000000000000000000000000"'
$fBadHash = Join-Path $fixtures "receipt-wrong-hash.json"
$badHash | Set-Content $fBadHash -Encoding utf8
$t4a = Invoke-Status "$RunId-t4a-wronghash" $fBadHash
if ($t4a.json.permanent_relay.state -ne "receipt_mismatch") { $failures.Add("T4a state=$($t4a.json.permanent_relay.state) detail=$($t4a.json.permanent_relay.detail)") }

# T4b: wrong-path fixture
$badPath = $receiptRaw -replace '"executable_path":\s*"[^"]+"', '"executable_path": "E:\\TORQ-CONSOLE\\tmp\\buzz-pilot\\20260731-004310\\source\\buzz\\target\\debug\\buzz-relay.exe"'
$fBadPath = Join-Path $fixtures "receipt-wrong-path.json"
$badPath | Set-Content $fBadPath -Encoding utf8
$t4b = Invoke-Status "$RunId-t4b-wrongpath" $fBadPath
if ($t4b.json.permanent_relay.state -ne "receipt_mismatch") { $failures.Add("T4b state=$($t4b.json.permanent_relay.state) detail=$($t4b.json.permanent_relay.detail)") }

# T5: dead-PID fixture
$deadPid = 999983
while ($null -ne (Get-Process -Id $deadPid -ErrorAction SilentlyContinue)) { $deadPid-- }
$dead = $receiptRaw -replace '"pid":\s*\d+', ('"pid":  ' + $deadPid)
$fDead = Join-Path $fixtures "receipt-dead-pid.json"
$dead | Set-Content $fDead -Encoding utf8
$t5 = Invoke-Status "$RunId-t5-deadpid" $fDead
if ($t5.json.permanent_relay.state -notin @("stale_receipt", "down")) { $failures.Add("T5 state=$($t5.json.permanent_relay.state)") }
if ($t5.json.permanent_relay.detail -ne "pid_not_alive") { $failures.Add("T5 detail=$($t5.json.permanent_relay.detail)") }

# T7a: compose fixture with an UNHEALTHY postgres must classify unhealthy (not healthy)
$fCompBad = Join-Path $fixtures "compose-unhealthy.txt"
@(
    "torq-buzz-postgres-1|Up 5 hours (unhealthy)",
    "torq-buzz-redis-1|Up 5 hours (healthy)",
    "torq-buzz-minio-1|Up 5 hours"
) | Set-Content $fCompBad -Encoding ascii
$t7a = Invoke-Status "$RunId-t7a-unhealthy" "" $fCompBad
$t7pg = $t7a.json.compose | Where-Object { $_.name -eq "torq-buzz-postgres-1" }
if ($t7pg.health -ne "unhealthy" -or $t7pg.healthy -ne $false) { $failures.Add("T7a postgres health=$($t7pg.health) healthy=$($t7pg.healthy)") }
$t7mn = $t7a.json.compose | Where-Object { $_.name -eq "torq-buzz-minio-1" }
if ($t7mn.health -ne "up_no_healthcheck" -or $t7mn.healthy -ne $false) { $failures.Add("T7a minio health=$($t7mn.health) healthy=$($t7mn.healthy)") }

# T7b: redis "Up" without healthcheck string must classify up_no_healthcheck (not healthy)
$fCompNoHc = Join-Path $fixtures "compose-no-healthcheck.txt"
@(
    "torq-buzz-postgres-1|Up 5 hours (healthy)",
    "torq-buzz-redis-1|Up 5 hours",
    "torq-buzz-minio-1|Up 5 hours"
) | Set-Content $fCompNoHc -Encoding ascii
$t7b = Invoke-Status "$RunId-t7b-nohealthcheck" "" $fCompNoHc
$t7rd = $t7b.json.compose | Where-Object { $_.name -eq "torq-buzz-redis-1" }
if ($t7rd.health -ne "up_no_healthcheck" -or $t7rd.healthy -ne $false) { $failures.Add("T7b redis health=$($t7rd.health) healthy=$($t7rd.healthy)") }

# T8: Buzz-Status redaction rules must be verbatim-identical to Stop-Buzz canonical rules
function Get-RedactLines([string]$path) {
    $raw = Get-Content $path -Raw
    $m = [regex]::Match($raw, '(?ms)function Get-RedactedCommandLineHash.*?(?=\r?\n\})')
    if (-not $m.Success) { return @() }
    return @([regex]::Matches($m.Value, "-replace\s+'.+'") | ForEach-Object { $_.Value })
}
$sl = Get-RedactLines (Join-Path $Root "scripts\Stop-Buzz.ps1")
$bl = Get-RedactLines (Join-Path $Root "scripts\Buzz-Status.ps1")
if ($sl.Count -lt 3) { $failures.Add("T8 could not extract Stop-Buzz redaction rules") }
if ($bl.Count -lt 3) { $failures.Add("T8 could not extract Buzz-Status redaction rules") }
if (($sl -join "|") -ne ($bl -join "|")) { $failures.Add("T8 redaction rules differ from Stop-Buzz canonical") }

# T8b: fixture receipt carrying the CORRECT redacted command-line hash must still report running
$cimLive = Get-CimInstance Win32_Process -Filter "ProcessId=$livePid" -ErrorAction SilentlyContinue
if ($null -eq $cimLive) { $failures.Add("T8b live permanent process $livePid not found") }
else {
    $red = [string]$cimLive.CommandLine
    $red = $red -replace 'postgres://[^ \t"]+', 'postgres://***'
    $red = $red -replace '(?i)(PASSWORD|SECRET|KEY|TOKEN|NSEC)=[^ \t"]+', '$1=***'
    $red = $red -replace 'nsec1[a-z0-9]+', 'nsec1***'
    $shaObj = [System.Security.Cryptography.SHA256]::Create()
    try { $cmdHash = ([BitConverter]::ToString($shaObj.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($red))) -replace '-', '').ToLowerInvariant() }
    finally { $shaObj.Dispose() }
    $withCmd = $receiptRaw -replace '("receipt_nonce":\s*"[^"]+")', ('$1,' + "`n    `"command_line_redacted_sha256`": `"$cmdHash`"")
    $fCmd = Join-Path $fixtures "receipt-with-cmdhash.json"
    $withCmd | Set-Content $fCmd -Encoding utf8
    $t8b = Invoke-Status "$RunId-t8b-cmdhash" $fCmd
    if ($t8b.json.permanent_relay.state -ne "running") { $failures.Add("T8b state=$($t8b.json.permanent_relay.state) detail=$($t8b.json.permanent_relay.detail)") }
    # and a deliberately WRONG cmd hash must mismatch
    $withBad = $withCmd -replace $cmdHash, ('0' * 64)
    $fCmdBad = Join-Path $fixtures "receipt-with-bad-cmdhash.json"
    $withBad | Set-Content $fCmdBad -Encoding utf8
    $t8c = Invoke-Status "$RunId-t8c-badcmdhash" $fCmdBad
    if ($t8c.json.permanent_relay.state -ne "receipt_mismatch") { $failures.Add("T8c state=$($t8c.json.permanent_relay.state)") }
    if ([string]$t8c.json.permanent_relay.detail -notmatch "command_line_hash") { $failures.Add("T8c detail=$($t8c.json.permanent_relay.detail)") }
}

# T6: no process harmed - both relays still alive, live receipt untouched
$perm = Get-Process -Id $livePid -ErrorAction SilentlyContinue
if ($null -eq $perm) { $failures.Add("T6 permanent relay $livePid died during tests") }
$pilotStill = Get-Process -Name "buzz-relay" -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $livePid }
if ($pilotAlive -and $null -eq $pilotStill) { $failures.Add("T6 pilot relay died during tests") }
if ((Get-Content $liveReceipt -Raw) -ne $receiptRaw) { $failures.Add("T6 live receipt changed during tests") }

$result = [ordered]@{
    run_id = $RunId
    tests  = @("T1 live running", "T2 pilot separation", "T3 missing receipt", "T4a wrong hash", "T4b wrong path", "T5 dead pid", "T7a unhealthy fixture", "T7b no-healthcheck fixture", "T8 redaction parity", "T8b/c cmdline hash fixtures", "T6 no process harmed")
    failures = $failures
    pass   = ($failures.Count -eq 0)
    utc    = (Get-Date).ToUniversalTime().ToString("o")
}
$result | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $fixtures "test-result.json") -Encoding utf8

if ($failures.Count -gt 0) {
    Write-Host "FAIL: Buzz-Status test suite"
    $failures | ForEach-Object { Write-Host "  - $_" }
    exit 1
}
Write-Host "PASS: Buzz-Status test suite ($RunId)"
exit 0

<#
.SYNOPSIS
  Status report for TORQ Buzz permanent deployment (read-only, live-state).

.DESCRIPTION
  Probes live state only. Never starts/stops processes, never mutates Docker,
  never writes receipts or runtime configuration. Evidence JSON goes to
  evidence\c5\status\<RunId>\status.json.
#>
[CmdletBinding()]
param(
    [string]$Root = "E:\TORQ-BUZZ",
    [string]$RunId = [guid]::NewGuid().ToString(),
    [string]$ReceiptPath = "",   # test fixtures may point elsewhere; default = live receipt
    [string]$ComposeFixturePath = ""   # test fixtures: file of "name|status" lines; default = live docker ps
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$evidence = Join-Path $Root "evidence\c5\status\$RunId"
New-Item -ItemType Directory -Force -Path $evidence | Out-Null

if ([string]::IsNullOrEmpty($ReceiptPath)) { $ReceiptPath = Join-Path $Root "state\relay-process.json" }
$permExe = Join-Path $Root "bin\buzz-relay.exe"

function Get-Prop($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    $p = $obj.PSObject.Properties[$name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Get-ListenerOwner([int]$port) {
    $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $c) { return [ordered]@{ port = $port; listening = $false; pid = $null; address = $null } }
    return [ordered]@{ port = $port; listening = $true; pid = [int]$c.OwningProcess; address = $c.LocalAddress }
}

function Test-Http([string]$url) {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 3
        $body = [string]$r.Content
        if ($body.Length -gt 200) { $body = $body.Substring(0, 200) }
        return [ordered]@{ url = $url; ok = ($r.StatusCode -eq 200); code = [int]$r.StatusCode; body = $body }
    } catch {
        return [ordered]@{ url = $url; ok = $false; code = 0; body = [string]$_.Exception.Message }
    }
}

function Get-RedactedErrors([string]$logDir, [int]$max = 5) {
    $out = @()
    if (-not (Test-Path $logDir)) { return $out }
    $files = Get-ChildItem -Path $logDir -Filter "relay-*.stderr.log" -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        $hits = Select-String -Path $f.FullName -Pattern '"level":"ERROR"' -ErrorAction SilentlyContinue | Select-Object -Last $max
        foreach ($h in $hits) {
            $t = [string]$h.Line
            $t = [regex]::Replace($t, '://[^/\s:@]+:[^@\s]+@', '://<redacted>@')
            $t = [regex]::Replace($t, '(?i)(password|secret|token|api[_-]?key|private[_-]?key)("\s*:\s*"|=)[^,\s}"]+', '$1$2<redacted>')
            if ($t.Length -gt 300) { $t = $t.Substring(0, 300) }
            $out += [ordered]@{ log = $f.Name; line = $t }
        }
    }
    return $out
}

# Canonical redacted command-line hash - identical rules to Stop-Buzz.ps1 Get-RedactedCommandLineHash.
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

# Strict docker health classification: "Up ... (unhealthy)" must NOT count as healthy.
function Get-ComposeHealthState([string]$status) {
    if ([string]::IsNullOrEmpty($status)) { return "missing" }
    if ($status -match "unhealthy") { return "unhealthy" }
    if ($status -match "\(healthy\)") { return "healthy" }
    if ($status -match "^Up") { return "up_no_healthcheck" }
    return "unknown"
}

# ---- production source pin (kept from C1 status) ----
$prod = Join-Path $Root "source\buzz"
$pin = $null; $dirty = @("missing production source")
if (Test-Path $prod) {
    Push-Location $prod
    $pin = (git rev-parse HEAD 2>$null)
    $dirty = @(git status --porcelain 2>$null)
    Pop-Location
}

# ---- permanent relay: receipt vs live process ----
$receipt = $null
$receiptReadError = $null
if (Test-Path $ReceiptPath) {
    try { $receipt = Get-Content $ReceiptPath -Raw | ConvertFrom-Json }
    catch { $receiptReadError = [string]$_.Exception.Message }
}

$relayState = "stale_receipt"
$relayDetail = "receipt_missing"
$relayPid = $null; $relayRunId = $null; $relayExe = $null
$mismatches = @()

if ($null -ne $receipt) {
    $relayPid   = Get-Prop $receipt 'pid'
    $relayRunId = Get-Prop $receipt 'launcher_run_id'
    $rRole      = Get-Prop $receipt 'role'
    $rPath      = Get-Prop $receipt 'executable_path'
    $rSha       = Get-Prop $receipt 'executable_sha256'
    $rCtime     = Get-Prop $receipt 'creation_time_utc'
    $rCmdHash   = Get-Prop $receipt 'command_line_redacted_sha256'
    $relayExe   = $rPath

    $proc = $null
    if ($null -ne $relayPid) { $proc = Get-Process -Id ([int]$relayPid) -ErrorAction SilentlyContinue }

    if ($null -eq $proc) {
        $relayState = "stale_receipt"
        $relayDetail = "pid_not_alive"
    } else {
        if ($rRole -ne "permanent-relay") { $mismatches += "role=$rRole" }
        $livePath = [string]$proc.Path
        if ([string]::IsNullOrEmpty($livePath) -or ($livePath -ine [string]$rPath)) { $mismatches += "executable_path" }
        if (-not [string]::IsNullOrEmpty($livePath)) {
            $liveSha = (Get-FileHash $livePath -Algorithm SHA256).Hash
            if ($liveSha -ine [string]$rSha) { $mismatches += "executable_sha256" }
        }
        if (-not [string]::IsNullOrEmpty([string]$rCtime)) {
            try {
                $rc = [datetime]::Parse([string]$rCtime).ToUniversalTime()
                $delta = [math]::Abs(($proc.StartTime.ToUniversalTime() - $rc).TotalSeconds)
                if ($delta -gt 2) { $mismatches += "creation_time" }
            } catch { $mismatches += "creation_time_unparseable" }
        }
        if ($null -ne $rCmdHash) {
            $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$relayPid)" -ErrorAction SilentlyContinue
            if ($null -ne $cim -and $null -ne $cim.CommandLine) {
                # redact BEFORE hashing; never log the raw command line
                $liveCmdHash = Get-RedactedCommandLineHash ([string]$cim.CommandLine)
                if ($liveCmdHash -ine [string]$rCmdHash) { $mismatches += "command_line_hash" }
            }
        }

        if ($mismatches.Count -gt 0) {
            $relayState = "receipt_mismatch"
            $relayDetail = ($mismatches -join ",")
        } else {
            $relayState = "running"
            $relayDetail = "receipt_matches_live_process"
        }
    }
} elseif ($null -ne $receiptReadError) {
    $relayDetail = "receipt_unparseable"
}

# ---- port ownership + endpoint probes (only meaningful when relayState running) ----
$port3300 = Get-ListenerOwner 3300
$port8380 = Get-ListenerOwner 8380
$port9302 = Get-ListenerOwner 9302

$endpoints = [ordered]@{
    liveness  = Test-Http "http://127.0.0.1:8380/_liveness"
    readiness = Test-Http "http://127.0.0.1:8380/_readiness"
    status    = Test-Http "http://127.0.0.1:8380/_status"
    metrics   = Test-Http "http://127.0.0.1:9302/metrics"
}
if ($relayState -eq "running") {
    if (-not ($endpoints.liveness.ok -and $endpoints.readiness.ok -and $endpoints.status.ok -and $endpoints.metrics.ok)) {
        $relayState = "unhealthy"
        $relayDetail = "endpoint_probe_failed"
    }
}

# ---- compose (read-only docker ps, or test fixture of "name|status" lines) ----
$composeExpected = @("torq-buzz-postgres-1", "torq-buzz-redis-1", "torq-buzz-minio-1")
$compose = @()
$dockerLines = @()
if (-not [string]::IsNullOrEmpty($ComposeFixturePath)) {
    $dockerLines = @(Get-Content $ComposeFixturePath)
} else {
    $dockerLines = @(& docker ps --filter "name=torq-buzz-" --format "{{.Names}}|{{.Status}}" 2>$null)
}
foreach ($name in $composeExpected) {
    $found = $null
    foreach ($line in $dockerLines) {
        $parts = ([string]$line) -split "\|", 2
        if ($parts[0] -eq $name) { $found = $parts[1]; break }
    }
    $healthState = Get-ComposeHealthState $found
    $compose += [ordered]@{
        name    = $name
        present = ($null -ne $found)
        status  = $found
        health  = $healthState
        healthy = ($healthState -eq "healthy")
    }
}

# ---- support port ownership ----
$supportPorts = @(Get-ListenerOwner 55432; Get-ListenerOwner 16379; Get-ListenerOwner 19000; Get-ListenerOwner 19001)

# ---- pilot (informational only, never permanent-owned) ----
$pilot = [ordered]@{ present = $false; pid = $null; path = $null; port_3000 = (Get-ListenerOwner 3000); permanent_owned = $false }
$allRelay = Get-CimInstance Win32_Process -Filter "Name='buzz-relay.exe'" -ErrorAction SilentlyContinue
foreach ($rp in @($allRelay)) {
    if ($null -ne $rp.ExecutablePath -and ($rp.ExecutablePath -ine $permExe)) {
        $pilot.present = $true
        $pilot.pid = [int]$rp.ProcessId
        $pilot.path = [string]$rp.ExecutablePath
    }
}

# ---- recent permanent relay errors (redacted) ----
$recentErrors = @(Get-RedactedErrors (Join-Path $Root "logs") 5)

$status = [ordered]@{
    schema_version = 2
    run_id         = $RunId
    root           = $Root
    receipt_path   = $ReceiptPath
    production_source = $prod
    pinned_commit_expected = "3e48f1b2365d326ee1c9582448d86a99b44ecd5d"
    pinned_commit_actual   = $pin
    pin_ok         = ($pin -eq "3e48f1b2365d326ee1c9582448d86a99b44ecd5d")
    worktree_dirty = $dirty
    copy_selected  = "VERIFIED_COPY_STEP"
    permanent_relay = [ordered]@{
        state          = $relayState
        detail         = $relayDetail
        pid            = $relayPid
        executable     = $relayExe
        receipt_run_id = $relayRunId
        port_3300      = $port3300
        port_8380      = $port8380
        port_9302      = $port9302
        endpoints      = $endpoints
    }
    compose        = $compose
    support_ports  = $supportPorts
    pilot          = $pilot
    recent_relay_errors = $recentErrors
    utc            = (Get-Date).ToUniversalTime().ToString("o")
}

$json = $status | ConvertTo-Json -Depth 10
$json | Set-Content (Join-Path $evidence "status.json") -Encoding utf8

# ---- human-readable summary ----
Write-Host "=== TORQ Buzz Status ($RunId) ==="
Write-Host "pin_ok: $($status.pin_ok)  dirty: $($dirty -join '; ')"
Write-Host "permanent_relay: $relayState ($relayDetail) pid=$relayPid run=$relayRunId"
Write-Host "  3300: listening=$($port3300.listening) pid=$($port3300.pid) addr=$($port3300.address)"
Write-Host "  8380: listening=$($port8380.listening) pid=$($port8380.pid) addr=$($port8380.address)"
Write-Host "  9302: listening=$($port9302.listening) pid=$($port9302.pid) addr=$($port9302.address)"
Write-Host "  liveness=$($endpoints.liveness.code) readiness=$($endpoints.readiness.code) status=$($endpoints.status.code) metrics=$($endpoints.metrics.code)"
foreach ($c in $compose) { Write-Host "compose: $($c.name) present=$($c.present) health=$($c.health) status=$($c.status)" }
foreach ($sp in $supportPorts) { Write-Host "support port $($sp.port): listening=$($sp.listening) pid=$($sp.pid) addr=$($sp.address)" }
Write-Host "pilot (informational, never permanent-owned): present=$($pilot.present) pid=$($pilot.pid) port3000_listening=$($pilot.port_3000.listening)"
Write-Host "recent_relay_errors: $($recentErrors.Count)"
Write-Host "evidence: $evidence\status.json"
exit 0

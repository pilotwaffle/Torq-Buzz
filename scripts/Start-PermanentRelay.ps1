<#
.SYNOPSIS
  Start or adopt the TORQ Buzz permanent relay (idempotent).

.DESCRIPTION
  Starts ONLY E:\TORQ-BUZZ\bin\buzz-relay.exe with config\relay.env after
  the torq-buzz Docker support stack is healthy. If that exe is already
  running and ready, refreshes state\relay-process.json and exits 0.

  Does not mutate Docker. Does not touch a pilot buzz-relay. Does not
  kill by process name. Never prints env values.

  Used after reboot (Windows Update kills the relay; Docker comes back
  via restart:unless-stopped; the desktop does not start the relay).

  Without -Direct, this script only adopts a live relay or asks the
  scheduled task TORQ-Buzz-PermanentRelay to start one. That keeps the
  exe out of agent Job Objects (KILL_ON_JOB_CLOSE), which previously
  killed PID 22832 and PID 5024 mid-request with no crash record.
#>
[CmdletBinding()]
param(
    [string]$Root = "E:\TORQ-BUZZ",
    [string]$RunId = ("recovery-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")),
    [int]$DockerWaitSeconds = 300,
    [int]$ReadyWaitSeconds = 90,
    [string]$TaskName = "TORQ-Buzz-PermanentRelay",
    [switch]$Direct
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Exe      = Join-Path $Root "bin\buzz-relay.exe"
$EnvFile  = Join-Path $Root "config\relay.env"
$StateDir = Join-Path $Root "state"
$Receipt  = Join-Path $StateDir "relay-process.json"
$LogDir   = Join-Path $Root "logs"
$Evidence = Join-Path $Root ("evidence\c5\" + $RunId)

if (-not (Test-Path $Exe))     { throw "permanent relay exe missing: $Exe" }
if (-not (Test-Path $EnvFile)) { throw "relay.env missing: $EnvFile" }

function Get-PermanentRelayProcess {
    Get-CimInstance Win32_Process -Filter "Name='buzz-relay.exe'" -ErrorAction SilentlyContinue |
        Where-Object { [string]$_.ExecutablePath -ieq $Exe }
}

function Test-Ready {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:8380/_readiness" -TimeoutSec 2
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

function Wait-SupportStack {
    param([int]$Seconds)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $pg = docker inspect --format "{{.State.Health.Status}}" torq-buzz-postgres-1 2>$null
        $rd = docker inspect --format "{{.State.Health.Status}}" torq-buzz-redis-1 2>$null
        if ($pg -eq "healthy" -and $rd -eq "healthy") { return }
        if ((Get-Date) -ge $deadline) {
            throw "support stack not healthy within ${Seconds}s (postgres='$pg' redis='$rd'). Is Docker Desktop running?"
        }
        Start-Sleep -Seconds 5
    } while ($true)
}

function Write-RelayReceipt {
    param($Proc)
    $relayPid = [int]$Proc.ProcessId
    $live = Get-Process -Id $relayPid
    $exeSha = (Get-FileHash $Exe -Algorithm SHA256).Hash
    $cfgSha = (Get-FileHash $EnvFile -Algorithm SHA256).Hash
    $obj = [ordered]@{
        schema_version    = 1
        role              = "permanent-relay"
        launcher_run_id   = $RunId
        receipt_nonce     = [guid]::NewGuid().ToString()
        pid               = $relayPid
        ppid              = [int]$Proc.ParentProcessId
        creation_time_utc = $live.StartTime.ToUniversalTime().ToString("o")
        executable_path   = $Exe
        executable_sha256 = $exeSha
        relay_url         = "ws://127.0.0.1:3300"
        ports             = @(
            [ordered]@{ port = 3300; pid = $relayPid; address = "127.0.0.1" },
            [ordered]@{ port = 8380; pid = $relayPid; address = "127.0.0.1" },
            [ordered]@{ port = 9302; pid = $relayPid; address = "127.0.0.1" }
        )
        config_sha256     = $cfgSha
        started_utc       = (Get-Date).ToUniversalTime().ToString("o")
        readiness_ok      = $true
    }
    New-Item -ItemType Directory -Force -Path $StateDir, $Evidence | Out-Null
    if (Test-Path $Receipt) {
        Copy-Item $Receipt (Join-Path $Evidence "relay-process.previous.json") -Force
    }
    $json = $obj | ConvertTo-Json -Depth 8
    $bytes = New-Object System.Text.UTF8Encoding $false
    $tmp = Join-Path $StateDir ("relay-process.json.tmp-" + $RunId)
    [System.IO.File]::WriteAllBytes($tmp, $bytes.GetBytes($json))
    Move-Item -Path $tmp -Destination $Receipt -Force
    Copy-Item $Receipt (Join-Path $Evidence "relay-process.fresh.json") -Force
    $written = Get-Content $Receipt -Raw | ConvertFrom-Json
    if ([int]$written.pid -ne $relayPid) {
        throw "receipt write did not persist (on-disk pid=$($written.pid) expected $relayPid)"
    }
}

function Wait-ReadyAndAdopt {
    param([int]$Seconds, [string]$Action)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $have = @(Get-PermanentRelayProcess)
        if ($have.Count -eq 1 -and (Test-Ready)) {
            Write-RelayReceipt -Proc $have[0]
            Write-Output ("PERMANENT_RELAY_PID=" + $have[0].ProcessId)
            Write-Output "READINESS_OK=True"
            Write-Output ("ACTION=" + $Action)
            return
        }
        if ((Get-Date) -ge $deadline) {
            throw "relay not ready within ${Seconds}s after $Action"
        }
        Start-Sleep -Seconds 1
    } while ($true)
}

$existing = @(Get-PermanentRelayProcess)
if ($existing.Count -gt 1) {
    throw "multiple permanent buzz-relay.exe processes; refuse to start another"
}
if ($existing.Count -eq 1) {
    if (-not (Test-Ready)) {
        throw "permanent relay PID $($existing[0].ProcessId) is up but readiness failed; not killing it"
    }
    Write-RelayReceipt -Proc $existing[0]
    Write-Output ("PERMANENT_RELAY_PID=" + $existing[0].ProcessId)
    Write-Output "READINESS_OK=True"
    Write-Output "ACTION=adopted-existing"
    exit 0
}

if (-not $Direct) {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        throw "scheduled task '$TaskName' missing; run scripts\Install-PermanentRelayAutostart.ps1"
    }
    Start-ScheduledTask -TaskName $TaskName
    Wait-ReadyAndAdopt -Seconds $ReadyWaitSeconds -Action "started-via-task"
    exit 0
}

Wait-SupportStack -Seconds $DockerWaitSeconds

$existing = @(Get-PermanentRelayProcess)
if ($existing.Count -gt 1) {
    throw "multiple permanent buzz-relay.exe processes; refuse to start another"
}
if ($existing.Count -eq 1) {
    if (-not (Test-Ready)) {
        throw "permanent relay PID $($existing[0].ProcessId) is up but readiness failed; not killing it"
    }
    Write-RelayReceipt -Proc $existing[0]
    Write-Output ("PERMANENT_RELAY_PID=" + $existing[0].ProcessId)
    Write-Output "READINESS_OK=True"
    Write-Output "ACTION=adopted-existing"
    exit 0
}

foreach ($port in 3300, 8380, 9302) {
    $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $c) {
        throw "port $port already listening (PID $($c.OwningProcess)) but not the permanent relay; abort"
    }
}

Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
    $i = $_.IndexOf('='); if ($i -lt 1) { return }
    Set-Item -Path ("env:" + $_.Substring(0, $i)) -Value $_.Substring($i + 1)
}

New-Item -ItemType Directory -Force -Path $LogDir, $Evidence | Out-Null
$stdout = Join-Path $LogDir ("relay-" + $RunId + ".stdout.log")
$stderr = Join-Path $LogDir ("relay-" + $RunId + ".stderr.log")

$p = Start-Process -FilePath $Exe -WorkingDirectory $Root `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
    -WindowStyle Hidden -PassThru

$ready = $false
for ($i = 0; $i -lt $ReadyWaitSeconds; $i++) {
    Start-Sleep -Seconds 1
    if ($p.HasExited) { throw "permanent relay exited during startup; see $stderr" }
    if (Test-Ready) { $ready = $true; break }
}
if (-not $ready) { throw "readiness not OK within ${ReadyWaitSeconds}s; see $stderr" }

$cim = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)"
Write-RelayReceipt -Proc $cim
Write-Output ("PERMANENT_RELAY_PID=" + $p.Id)
Write-Output "READINESS_OK=True"
Write-Output "ACTION=started"
exit 0

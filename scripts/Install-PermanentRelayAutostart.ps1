<#
.SYNOPSIS
  Register a current-user logon task that starts the permanent Buzz relay.

.DESCRIPTION
  After reboot, Docker containers come back (restart: unless-stopped) but
  buzz-relay.exe does not. This task runs Start-PermanentRelay.ps1 at logon
  so the desktop can connect to ws://127.0.0.1:3300.

  Current-user Interactive only. Does not run as SYSTEM. Idempotent register.
#>
[CmdletBinding()]
param(
    [string]$Root = "E:\TORQ-BUZZ",
    [string]$TaskName = "TORQ-Buzz-PermanentRelay"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script = Join-Path $Root "scripts\Start-PermanentRelay.ps1"
if (-not (Test-Path $script)) { throw "missing $script" }

$userId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument ("-NoProfile -ExecutionPolicy Bypass -File `"$script`" -Direct")
$logon = New-ScheduledTaskTrigger -AtLogOn -User $userId
$logon.Delay = "PT45S"
$watch = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) `
    -RepetitionInterval (New-TimeSpan -Minutes 2) `
    -RepetitionDuration (New-TimeSpan -Days 3650)
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 15) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($logon, $watch) `
    -Principal $principal -Settings $settings -Force `
    -Description "Start TORQ Buzz permanent relay at logon and every 2 minutes if it is down. Uses -Direct so the exe is not in an agent Job Object." | Out-Null

$t = Get-ScheduledTask -TaskName $TaskName
Write-Output ("TASK=" + $t.TaskName)
Write-Output ("STATE=" + $t.State)
Write-Output ("USER=" + $userId)
Write-Output ("SCRIPT=" + $script)
exit 0

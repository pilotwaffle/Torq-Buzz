<#
.SYNOPSIS
  Service-free regression: Invoke-TorqMigration.ps1 must fail closed when the
  pre-sign duplicate-check relay query fails (no copy created), and must reject
  plans with missing required fields.

.DESCRIPTION
  Invoke-RestMethod is mocked by a function defined in a wrapper script, so no
  network or relay is touched. Each case runs in a child pwsh process.
  Exit code 0 = all pass, 1 = failure.
#>
[CmdletBinding()]
param(
    [string]$Pwsh = (Get-Process -Id $PID).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = Join-Path $scriptDir "Invoke-TorqMigration.ps1"
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("torq-mig-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$failures = New-Object System.Collections.Generic.List[string]

$pk = ("ab" * 32)
function New-Plan {
    param([string]$Path, [string]$RunId, [string[]]$Omit = @())
    $p = [ordered]@{
        migration_run_id       = $RunId
        source_event_id        = ("11" * 32)
        source_event_author    = ("22" * 32)
        source_channel_id      = "chan-src"
        destination_channel_id = "chan-dst"
        destination_public_key = $pk
        content                = "TORQ_BUZZ_RUNTIME_ACCEPTANCE_001"
    }
    foreach ($o in $Omit) { $p.Remove($o) }
    $p | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding utf8
}

# Wrapper: mocks Invoke-RestMethod (query -> throws; /event -> recorded), runs the target.
$wrapper = Join-Path $work "wrapper.ps1"
@'
param([string]$Target, [string]$PlanPath, [string]$EvidenceDir, [string]$NsecPath, [string]$PostLog)
function Invoke-RestMethod {
    param([string]$Method, [string]$Uri, $Body, [string]$ContentType, [int]$TimeoutSec)
    if ($Uri -match "/event$") { Add-Content -LiteralPath $PostLog -Value "POST_EVENT"; return }
    throw "mock relay query failure"
}
try {
    & $Target -PlanPath $PlanPath -EvidenceDir $EvidenceDir -DryRun:$false `
        -AllowPermanentHumanSign -PermanentHumanNsecPath $NsecPath
    exit $LASTEXITCODE
} catch {
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 1
}
'@ | Set-Content -LiteralPath $wrapper -Encoding utf8

function Invoke-Case {
    param([string]$Name, [string]$RunId, [string[]]$Omit = @())
    $caseDir = Join-Path $work $Name
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $plan = Join-Path $caseDir "plan.json"
    New-Plan -Path $plan -RunId $RunId -Omit $Omit
    $ev = Join-Path $caseDir "ev"
    $runDir = Join-Path $ev $RunId
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    # A valid pre-signed PUBLIC event, so a buggy run WOULD reach publish (copy created).
    @{ id = ("33" * 32); sig = ("44" * 64); pubkey = $pk; kind = 9; content = "TORQ_BUZZ_RUNTIME_ACCEPTANCE_001" } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDir "signed-event.json") -Encoding utf8
    $nsec = Join-Path $caseDir "dummy-secret-path.txt"
    Set-Content -LiteralPath $nsec -Value "placeholder-not-a-key"
    $postLog = Join-Path $caseDir "posts.log"
    $out = & $Pwsh -NoProfile -File $wrapper -Target $target -PlanPath $plan -EvidenceDir $ev -NsecPath $nsec -PostLog $postLog 2>&1 | Out-String
    $code = $LASTEXITCODE
    $posted = (Test-Path -LiteralPath $postLog)
    $state = $null
    $statePath = Join-Path $runDir "copy-selected-state.json"
    if (Test-Path -LiteralPath $statePath) { $state = (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).current_state }
    [pscustomobject]@{ Code = $code; Posted = $posted; Output = $out; State = $state }
}

function Assert-That {
    param([bool]$Cond, [string]$Msg)
    if ($Cond) { Write-Host "  PASS: $Msg" } else { Write-Host "  FAIL: $Msg"; $failures.Add($Msg) }
}

try {
    Write-Host "Case 1: relay query failure in pre-sign duplicate check must fail closed"
    $r = Invoke-Case -Name "c1" -RunId "run-relay-fail"
    Assert-That ($r.Code -ne 0) "exit code is non-zero (got $($r.Code))"
    Assert-That (-not $r.Posted) "no copy created (no POST to relay /event)"
    Assert-That ($r.State -ne "DUPLICATE_CHECKED" -and $r.State -ne "SIGNED" -and $r.State -ne "PUBLISHED") "journal never advanced past PLANNED (state=$($r.State))"
    Assert-That ($r.Output -match "(?i)duplicate check failed") "clear error message mentions 'duplicate check failed'"
    Assert-That ($r.Output -notmatch "DUPLICATE_CHECKED \(0 valid copies\)") "relay failure is not reported as 0 valid copies"

    Write-Host "Case 2: plan missing a required field is rejected with the field-presence error"
    $r2 = Invoke-Case -Name "c2" -RunId "run-missing-field" -Omit @("destination_public_key")
    Assert-That ($r2.Code -ne 0) "exit code is non-zero (got $($r2.Code))"
    Assert-That ($r2.Output -match "migration plan missing field: destination_public_key") "error names the missing field"
    Assert-That (-not $r2.Posted) "nothing published"
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host ("FAILED: {0} assertion(s)" -f $failures.Count)
    exit 1
}
Write-Host "ALL PASSED"
exit 0

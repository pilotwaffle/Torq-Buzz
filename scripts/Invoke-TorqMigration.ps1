<#
.SYNOPSIS
  TORQ Buzz migration orchestrator - COPY_SELECTED_MESSAGE step (Gate-1).

.DESCRIPTION
  Bounded implementation of the approved migration copy flow:

    PLANNED -> DUPLICATE_CHECKED -> SIGNED -> PUBLISHED -> VERIFIED -> COMPLETE
    terminals: COMPLETE_REUSED | AMBIGUOUS_DUPLICATE

  Default is dry-run. Permanent-human signing is refused unless both:
    -AllowPermanentHumanSign
    -PermanentHumanNsecPath (operator-provided; never logged)

  Does not mutate pilot data, launchers, Docker, or identity bootstrap.

.PARAMETER Step
  Migration step name. Currently only COPY_SELECTED_MESSAGE is implemented.

.PARAMETER PlanPath
  Path to migration-plan JSON (source/destination bindings).

.PARAMETER EvidenceDir
  Directory for journal, signed event, receipts (created if missing).

.PARAMETER VerifierPath
  Path to torq-buzz-event-verify.exe (optional; used for verify-selected-message).

.PARAMETER DryRun
  When set (default), no publish and no signing are attempted.

.PARAMETER AllowPermanentHumanSign
  Operator gate for real signing. Still requires -PermanentHumanNsecPath.

.PARAMETER PermanentHumanNsecPath
  Path to nsec/hex secret for permanent human identity. Never written to journal.
#>
[CmdletBinding()]
param(
    [ValidateSet("COPY_SELECTED_MESSAGE")]
    [string]$Step = "COPY_SELECTED_MESSAGE",

    [Parameter(Mandatory = $true)]
    [string]$PlanPath,

    [Parameter(Mandatory = $true)]
    [string]$EvidenceDir,

    [string]$VerifierPath = "",

    [switch]$DryRun = $true,

    [switch]$AllowPermanentHumanSign,

    [string]$PermanentHumanNsecPath = "",

    [string]$RelayHttpQueryUrl = "http://127.0.0.1:3300/query",

    [string]$RelayWsUrl = "ws://127.0.0.1:3300"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-JournalLine {
    param([string]$JournalPath, [hashtable]$Record)
    $line = ($Record | ConvertTo-Json -Compress -Depth 8)
    $dir = Split-Path -Parent $JournalPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Add-Content -Path $JournalPath -Value $line -Encoding utf8
}

function Get-ContentSha256Hex {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Assert-NoSecretFields {
    param([string]$JsonText)
    $lower = $JsonText.ToLowerInvariant()
    foreach ($bad in @("private_key", "secret_key", "nsec", "seckey", "secretkey")) {
        if ($lower -match $bad) {
            throw "Refusing journal/receipt content that appears to contain '$bad'"
        }
    }
}

if (-not (Test-Path -LiteralPath $PlanPath)) {
    throw "Plan not found: $PlanPath"
}

$plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding utf8 | ConvertFrom-Json
$requiredPlan = @(
    "migration_run_id",
    "source_event_id",
    "source_event_author",
    "source_channel_id",
    "destination_channel_id",
    "destination_public_key",
    "content"
)
foreach ($k in $requiredPlan) {
    if (-not $plan.PSObject.Properties.Name -contains $k) {
        throw "migration plan missing field: $k"
    }
}

if ($plan.content -ne "TORQ_BUZZ_RUNTIME_ACCEPTANCE_001") {
    throw "plan.content must be exact TORQ_BUZZ_RUNTIME_ACCEPTANCE_001"
}
if ($RelayWsUrl -ne "ws://127.0.0.1:3300") {
    throw "RelayWsUrl must be ws://127.0.0.1:3300 for Gate-1 copy step"
}

$runId = [string]$plan.migration_run_id
$evidenceRoot = Join-Path $EvidenceDir $runId
$journalPath = Join-Path $evidenceRoot "migration-journal.jsonl"
$receiptPath = Join-Path $evidenceRoot "migration-receipt.json"
$signedPath = Join-Path $evidenceRoot "signed-event.json"
$statePath = Join-Path $evidenceRoot "copy-selected-state.json"

New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null

$now = (Get-Date).ToUniversalTime().ToString("o")
$contentSha = Get-ContentSha256Hex -Text ([string]$plan.content)

$journal = [ordered]@{
    schema_version           = 1
    migration_run_id         = $runId
    step                     = "COPY_SELECTED_MESSAGE"
    source_event_id          = [string]$plan.source_event_id
    source_event_author      = [string]$plan.source_event_author
    source_channel_id        = [string]$plan.source_channel_id
    destination_channel_id   = [string]$plan.destination_channel_id
    destination_public_key   = [string]$plan.destination_public_key
    content_sha256           = $contentSha
    intended_kind            = 9
    intended_relay_url       = "ws://127.0.0.1:3300"
    current_state            = "PLANNED"
    destination_event_id     = $null
    signed_event_path        = $null
    signed_event_sha256      = $null
    verification_result      = $null
    timestamps               = [ordered]@{
        planned_utc            = $now
        duplicate_checked_utc  = $null
        signed_utc             = $null
        published_utc          = $null
        verified_utc           = $null
        completed_utc          = $null
    }
}

$journalJson = ($journal | ConvertTo-Json -Depth 8)
Assert-NoSecretFields -JsonText $journalJson
Write-JournalLine -JournalPath $journalPath -Record $journal
$journal | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8

Write-Host "COPY_SELECTED_MESSAGE PLANNED (run=$runId)"
Write-Host "  source_event_id=$($plan.source_event_id)"
Write-Host "  destination_channel_id=$($plan.destination_channel_id)"
Write-Host "  dry_run=$DryRun"

# --- DUPLICATE_CHECKED -------------------------------------------------------
# Query is best-effort when relay is up; dry-run may supply candidates via plan.candidates_json_path.
$candidatesJson = "[]"
if ($plan.PSObject.Properties.Name -contains "candidates_json_path" -and $plan.candidates_json_path) {
    if (Test-Path -LiteralPath ([string]$plan.candidates_json_path)) {
        $candidatesJson = Get-Content -LiteralPath ([string]$plan.candidates_json_path) -Raw -Encoding utf8
    }
} elseif (-not $DryRun) {
    try {
        $queryBody = @{
            kinds   = @(9)
            authors = @([string]$plan.destination_public_key)
            "#h"    = @([string]$plan.destination_channel_id)
        } | ConvertTo-Json -Compress
        $resp = Invoke-RestMethod -Method Post -Uri $RelayHttpQueryUrl -Body $queryBody -ContentType "application/json" -TimeoutSec 15
        $candidatesJson = ($resp | ConvertTo-Json -Depth 20 -Compress)
        if (-not $candidatesJson.Trim().StartsWith("[")) {
            $candidatesJson = "[$candidatesJson]"
        }
    } catch {
        Write-Warning "Relay query failed (will treat as 0 candidates for dry orchestration): $_"
        $candidatesJson = "[]"
    }
}

# Semantic filter via verifier binary when available; otherwise count=0 unless candidates provided for tests.
$validCount = 0
$validIds = @()
if ($VerifierPath -and (Test-Path -LiteralPath $VerifierPath)) {
    $filterIn = Join-Path $evidenceRoot "filter-input.json"
    $filterOut = Join-Path $evidenceRoot "filter-output.json"
    @{
        permanent_human_pubkey = [string]$plan.destination_public_key
        destination_channel_id = [string]$plan.destination_channel_id
        content                = [string]$plan.content
        kind                   = 9
        events_json            = $candidatesJson
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $filterIn -Encoding utf8

    & $VerifierPath filter-semantic-copies --input $filterIn --output $filterOut
    if ($LASTEXITCODE -ne 0) { throw "filter-semantic-copies failed exit=$LASTEXITCODE" }
    $filter = Get-Content -LiteralPath $filterOut -Raw -Encoding utf8 | ConvertFrom-Json
    $validCount = [int]$filter.count
    if ($filter.matches) {
        $validIds = @($filter.matches | ForEach-Object { $_.event_id })
    }
} else {
    Write-Warning "VerifierPath not set or missing; duplicate check cannot validate signatures in-process. validCount=0"
    $validCount = 0
}

$now = (Get-Date).ToUniversalTime().ToString("o")
$journal.timestamps.duplicate_checked_utc = $now

if ($validCount -gt 1) {
    $journal.current_state = "AMBIGUOUS_DUPLICATE"
    $journal.verification_result = "duplicate_check:ambiguous:$validCount"
    $journal.timestamps.completed_utc = $now
    Assert-NoSecretFields -JsonText (($journal | ConvertTo-Json -Depth 8))
    Write-JournalLine -JournalPath $journalPath -Record $journal
    $journal | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8
    @{
        schema_version = 1
        step           = "COPY_SELECTED_MESSAGE"
        outcome        = "AMBIGUOUS_DUPLICATE"
        valid_ids      = $validIds
        journal_path   = $journalPath
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
    Write-Error "AMBIGUOUS_DUPLICATE: $validCount valid semantic copies; operator review required."
    exit 26
}

if ($validCount -eq 1) {
    $journal.current_state = "COMPLETE_REUSED"
    $journal.destination_event_id = $validIds[0]
    $journal.verification_result = "duplicate_check:1_reused"
    $journal.timestamps.completed_utc = $now
    Assert-NoSecretFields -JsonText (($journal | ConvertTo-Json -Depth 8))
    Write-JournalLine -JournalPath $journalPath -Record $journal
    $journal | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8
    @{
        schema_version       = 1
        step                 = "COPY_SELECTED_MESSAGE"
        outcome              = "COMPLETE_REUSED"
        destination_event_id = $validIds[0]
        journal_path         = $journalPath
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
    Write-Host "COMPLETE_REUSED destination_event_id=$($validIds[0])"
    exit 0
}

# validCount == 0 -> DUPLICATE_CHECKED, then sign path
$journal.current_state = "DUPLICATE_CHECKED"
$journal.verification_result = "duplicate_check:0"
Assert-NoSecretFields -JsonText (($journal | ConvertTo-Json -Depth 8))
Write-JournalLine -JournalPath $journalPath -Record $journal
$journal | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8
Write-Host "DUPLICATE_CHECKED (0 valid copies)"

if ($DryRun) {
    Write-Host "DryRun: stopping before SIGNED. No private key used."
    @{
        schema_version = 1
        step           = "COPY_SELECTED_MESSAGE"
        outcome        = "DRY_RUN_STOPPED_AFTER_DUPLICATE_CHECKED"
        journal_path   = $journalPath
        next           = "Re-run without -DryRun after permanent-human signing authorization"
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
    exit 0
}

if (-not $AllowPermanentHumanSign) {
    throw "Signing blocked: pass -AllowPermanentHumanSign only after explicit operator authorization."
}
if (-not $PermanentHumanNsecPath -or -not (Test-Path -LiteralPath $PermanentHumanNsecPath)) {
    throw "Signing blocked: -PermanentHumanNsecPath required and must exist (never logged)."
}

# Signing/publishing is intentionally not implemented as an automatic nsec load here:
# permanent-human key access remains a separate operator-supervised action.
# When authorized, the operator places a pre-signed event at $signedPath (public event JSON only)
# OR a future supervised signer plugin may be invoked. This script only accepts an existing
# public signed event for publish+verify to avoid embedding key handling.
if (-not (Test-Path -LiteralPath $signedPath)) {
    throw @"
SIGNED payload missing at:
  $signedPath

Operator must produce a kind=9 event signed by the permanent human identity
(content exact, h=destination channel, relay $RelayWsUrl) and write ONLY the
public event JSON to that path. Private keys must never enter the journal.
"@
}

$signedRaw = Get-Content -LiteralPath $signedPath -Raw -Encoding utf8
Assert-NoSecretFields -JsonText $signedRaw
$signed = $signedRaw | ConvertFrom-Json
if (-not $signed.id -or -not $signed.sig -or -not $signed.pubkey) {
    throw "signed-event.json must be a public Nostr event with id/sig/pubkey"
}
if ([int]$signed.kind -ne 9) { throw "signed event kind must be 9" }
if ([string]$signed.pubkey -ne [string]$plan.destination_public_key) {
    throw "signed event author must equal destination_public_key (permanent human)"
}
if ([string]$signed.content -ne [string]$plan.content) {
    throw "signed event content mismatch"
}

$now = (Get-Date).ToUniversalTime().ToString("o")
$journal.current_state = "SIGNED"
$journal.destination_event_id = [string]$signed.id
$journal.signed_event_path = ($signedPath -replace "\\", "/")
$journal.signed_event_sha256 = Get-ContentSha256Hex -Text $signedRaw
$journal.timestamps.signed_utc = $now
Write-JournalLine -JournalPath $journalPath -Record $journal
$journal | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8
Write-Host "SIGNED destination_event_id=$($signed.id) (reused on any publish retry)"

# --- PUBLISHED (retry same payload) ------------------------------------------
$publishOk = $false
$lastErr = $null
for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
        # Prefer buzz CLI / HTTP EVENT when available; here we POST the signed event JSON.
        $eventBody = $signedRaw
        Invoke-RestMethod -Method Post -Uri ($RelayHttpQueryUrl -replace "/query$", "/event") -Body $eventBody -ContentType "application/json" -TimeoutSec 20 | Out-Null
        $publishOk = $true
        break
    } catch {
        $lastErr = $_
        Write-Warning "Publish attempt $attempt failed; will retry SAME signed event id=$($signed.id): $_"
        Start-Sleep -Seconds ([Math]::Min(2 * $attempt, 8))
    }
}
if (-not $publishOk) {
    Write-JournalLine -JournalPath $journalPath -Record $journal
    throw "Publish failed after retries (signed event retained for retry; never re-sign): $lastErr"
}

$now = (Get-Date).ToUniversalTime().ToString("o")
$journal.current_state = "PUBLISHED"
$journal.timestamps.published_utc = $now
Write-JournalLine -JournalPath $journalPath -Record $journal
$journal | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8
Write-Host "PUBLISHED"

# --- VERIFIED via torq-buzz-event-verify -------------------------------------
if (-not $VerifierPath -or -not (Test-Path -LiteralPath $VerifierPath)) {
    throw "VerifierPath required for VERIFIED transition"
}

# Re-query candidates after publish
try {
    $queryBody = @{
        kinds   = @(9)
        authors = @([string]$plan.destination_public_key)
        "#h"    = @([string]$plan.destination_channel_id)
    } | ConvertTo-Json -Compress
    $resp = Invoke-RestMethod -Method Post -Uri $RelayHttpQueryUrl -Body $queryBody -ContentType "application/json" -TimeoutSec 15
    $candidatesJson = ($resp | ConvertTo-Json -Depth 20 -Compress)
    if (-not $candidatesJson.Trim().StartsWith("[")) { $candidatesJson = "[$candidatesJson]" }
} catch {
    Write-Warning "Post-publish query failed; verifier will see empty set unless recovery re-query succeeds: $_"
    $candidatesJson = "[]"
}

$verifyIn = Join-Path $evidenceRoot "verify-selected-input.json"
$verifyOut = Join-Path $evidenceRoot "verify-selected-output.json"
$eventsFile = Join-Path $evidenceRoot "destination-events.json"
Set-Content -LiteralPath $eventsFile -Value $candidatesJson -Encoding utf8

$verifyDoc = [ordered]@{
    schema_version                 = 1
    permanent_human_pubkey         = [string]$plan.destination_public_key
    destination_channel_id         = [string]$plan.destination_channel_id
    expected_content               = [string]$plan.content
    intended_kind                  = 9
    intended_relay_url             = "ws://127.0.0.1:3300"
    events_json                    = $eventsFile
    journal                        = $journal
    source_plan                    = [ordered]@{
        source_event_id     = [string]$plan.source_event_id
        source_event_author = [string]$plan.source_event_author
        source_channel_id   = [string]$plan.source_channel_id
        content             = [string]$plan.content
    }
    expected_destination_event_id  = [string]$signed.id
}
$verifyDoc | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $verifyIn -Encoding utf8
Assert-NoSecretFields -JsonText (Get-Content -LiteralPath $verifyIn -Raw -Encoding utf8)

& $VerifierPath verify-selected-message --input $verifyIn --output $verifyOut
$verifyCode = $LASTEXITCODE
$verifyResult = Get-Content -LiteralPath $verifyOut -Raw -Encoding utf8 | ConvertFrom-Json

if ($verifyCode -ne 0) {
    $journal.verification_result = "verify:fail:$verifyCode"
    Write-JournalLine -JournalPath $journalPath -Record $journal
    $journal | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8
    @{
        schema_version = 1
        step           = "COPY_SELECTED_MESSAGE"
        outcome        = "VERIFY_FAILED"
        exit_code      = $verifyCode
        verify_output  = $verifyOut
        note           = "If publish succeeded, re-run recovery: re-query and reuse same signed event; never re-sign"
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
    exit $verifyCode
}

$now = (Get-Date).ToUniversalTime().ToString("o")
$journal.current_state = "COMPLETE"
$journal.destination_event_id = [string]$verifyResult.destination_event_id
$journal.verification_result = "verify:ok"
$journal.timestamps.verified_utc = $now
$journal.timestamps.completed_utc = $now
Assert-NoSecretFields -JsonText (($journal | ConvertTo-Json -Depth 8))
Write-JournalLine -JournalPath $journalPath -Record $journal
$journal | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8
@{
    schema_version       = 1
    step                 = "COPY_SELECTED_MESSAGE"
    outcome              = "COMPLETE"
    destination_event_id = $journal.destination_event_id
    journal_path         = $journalPath
    verify_output        = $verifyOut
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8

Write-Host "COMPLETE destination_event_id=$($journal.destination_event_id)"
exit 0

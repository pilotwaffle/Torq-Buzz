# C2–C5 Execution Plan (Planning Packet Only)

**Status:** Planning only — **no live execution authorized by this document**
**Recorded after independent C1 verdict:** `C1_VERIFIED_READY_FOR_C2_C5_PLANNING`
**C1 evidence:** `E:\TORQ-BUZZ\evidence\c1\independent-verify-c1\verify.log`
**Frozen component:** `COPY_SELECTED_MESSAGE` = **VERIFIED_COPY_STEP** (do not redesign)

This packet prepares controlled operator checkpoints **C2–C7**.
It does **not** authorize identity creation, signing, publishing, Compose up, permanent relay start, pilot stop, or Gate 1 complete claim.

---

## 0. Recorded C1 status

| Field | Value |
|---|---|
| Verdict | **C1_VERIFIED_READY_FOR_C2_C5_PLANNING** |
| Production worktree | `E:\TORQ-BUZZ\source\buzz` |
| HEAD | `3e48f1b2365d326ee1c9582448d86a99b44ecd5d` |
| Production dirty (only) | `crates/buzz-relay/src/{config,main,metrics}.rs` |
| Pilot dirty (only) | `crates/buzz-db/src/replica_fence.rs` |
| Dry-run scripts | Exit 0, non-mutating |
| T01 / T02 / T03 / T29 | PASS |
| Copy tests | 15 unit + 9 integration; EXIT_IO/24 present |
| Secret scan | PASS |
| `torq-buzz` containers | None started |
| Live permanent deployment | Not performed |

---

## 1. Recommended execution order for C2–C5

**Recommended order (safety-first):**

```text
C5  →  (optional readiness hold)  →  C2  →  C3  →  C4
```

| Step | Gate | Why this order |
|---|---|---|
| 1 | **C5** | Permanent Compose + live permanent relay must exist before destination publish/verify against `ws://127.0.0.1:3300` is meaningful. Signing without a permanent relay forces later re-publish and risks wrong target. |
| 2 | **C2** | Establish permanent-human identity material under ACL; **no signing yet**. |
| 3 | **C3** | Produce **exactly one** public kind-9 destination event (sign only); write public JSON only to journal path. |
| 4 | **C4** | Publish that same signed event to permanent relay; run verifier; advance journal. |
| Later | **C6** | Pilot stop/retirement — only after permanent stack proven (T17/T23 family green). |
| Last | **C7** | Claim Gate 1 complete only after acceptance evidence sealed. |

### 7. Should C5 run before C2/C3/C4?

**Yes — recommended.**

| If C5 first | Benefit |
|---|---|
| Relay already on permanent ports | C3/C4 target real permanent stack |
| Process receipts exist | Stop/ownership rules can protect permanent processes |
| Migration dry-run can be upgraded to live verify path | Uses same `COPY_SELECTED_MESSAGE` machine |

| If C2/C3 before C5 | Risk |
|---|---|
| Sign with nowhere permanent to publish | Orphan signed event / wrong later destination |
| Publish to pilot ports by mistake | Violates permanent boundary (`3300` permanent vs pilot `3000`) |

**Allowed exception:** Operator may run **C2 alone** (identity material prep offline) before C5, provided **no C3/C4** until permanent relay is live and receipt-owned.

**Forbidden without separate GO:** C3 or C4 against pilot relay, or any publish to non-`ws://127.0.0.1:3300`.

---

## 2–5. Per-checkpoint command plan, preconditions, evidence, stop/rollback

### C2 — Permanent-human identity (no signing)

**Purpose:** Create/import/select the permanent human identity under operator control without exposing private keys in logs, journals, or chat.

#### Preconditions

- C1 verified
- Operator physical control of machine
- ACL-capable secrets directory (e.g. `E:\TORQ-BUZZ\secrets\` with restrictive NTFS ACL; **not in git**)
- Pilot remains running or not — **do not stop pilot**
- No requirement that C5 already ran for C2-only (identity offline OK)

#### Identity-safety process (no private key exposure)

1. Operator creates identity **outside agent transcript** (local `buzz-admin generate-key` or hardware wallet export) in a private terminal.
2. Write secret **only** to ACL-restricted path, e.g.
   `E:\TORQ-BUZZ\secrets\permanent-human.nsec` (or hex seckey file).
   Permissions: current user only; no inheritance to Everyone.
3. Derive **public** key only into non-secret path:
   `E:\TORQ-BUZZ\config\permanent-human.pubkey.txt` (64 hex chars).
4. Agents/scripts may read **pubkey file only**.
   Agents must **never** `Get-Content` / log / journal the nsec path contents.
5. Update migration plan `destination_public_key` with pubkey only:
   `E:\TORQ-BUZZ\schemas\migration\migration-plan.live.json` (no secrets).
6. Optional: run `torq-buzz-profile-helper plan-remove-identity` dry-run on public maps only.
7. Record C2 receipt with **pubkey hash / path to pubkey**, never nsec.

#### Command plan (operator-supervised; illustrative)

```powershell
# Operator-private terminal only — do not paste nsec into agent chat
# 1) Generate or import key material into ACL path (operator action)
# 2) Extract pubkey only:
#    (example) buzz-admin generate-key  → store secret privately; copy Public key line to:
New-Item -ItemType Directory -Force -Path E:\TORQ-BUZZ\secrets | Out-Null
# icacls E:\TORQ-BUZZ\secrets /inheritance:r
# icacls E:\TORQ-BUZZ\secrets /grant:r "$env:USERNAME:(OI)(CI)F"

# 3) Write PUBLIC key only (operator fills exact hex):
# Set-Content E:\TORQ-BUZZ\config\permanent-human.pubkey.txt -Value "<64-hex-pubkey>" -Encoding ascii

# 4) Evidence (no secrets):
$RunId = [guid]::NewGuid().ToString()
New-Item -ItemType Directory -Force -Path "E:\TORQ-BUZZ\evidence\c2\$RunId" | Out-Null
# Copy pubkey file into evidence; write c2-receipt.json with pubkey only + file hashes
```

#### Expected evidence

| Path | Content |
|---|---|
| `E:\TORQ-BUZZ\evidence\c2\<run-id>\c2-receipt.json` | schema, run_id, pubkey (or pubkey sha256), ACL check boolean, **no nsec** |
| `E:\TORQ-BUZZ\config\permanent-human.pubkey.txt` | public only |
| `E:\TORQ-BUZZ\schemas\migration\migration-plan.live.json` | plan with `destination_public_key` filled |

#### Stop / rollback

| Stop if | Action |
|---|---|
| nsec appears in any evidence/log/chat | **STOP**; scrub logs; rotate identity if exposure confirmed; new C2 |
| Pubkey not 64 hex | Fail closed; do not proceed to C3 |
| Agent requests to display secret | Refuse; re-do C2 under operator-only terminal |

Rollback: delete pubkey reference from plan; optionally destroy nsec file under operator control; **do not** leave copies in evidence.

---

### C3 — Sign exactly one destination kind-9 event

**Purpose:** Produce **one** public signed Nostr event for permanent destination channel.

#### Signing boundary (hard)

| Rule | Value |
|---|---|
| Count | **Exactly one** new signed event for this acceptance copy (unless COMPLETE_REUSED later) |
| Kind | **9** only |
| Content | **Exact** `TORQ_BUZZ_RUNTIME_ACCEPTANCE_001` |
| Author | Permanent human pubkey from C2 **only** |
| `h` tag | Destination channel UUID from approved migration plan |
| Relay intent | Permanent `ws://127.0.0.1:3300` (recorded; publish is C4) |
| Not allowed | Pilot identity, permanent relay signer, arbitrary kinds/content, re-sign on retry |
| Output | **Public event JSON only** at journal `signed_event_path` |

Uses frozen `COPY_SELECTED_MESSAGE` state machine: after DUPLICATE_CHECKED with 0 matches → SIGNED.

#### Preconditions

- C2 complete (pubkey known; secret accessible only to operator signer)
- **Strongly preferred:** C5 complete (permanent channel UUID exists on permanent stack)
- Migration plan: source event
  `5ff77c3fb4c15b8362c23398a998e45a9fe77d13622adcd9a88cd2f3115dd670`
  content exact; destination channel UUID set
- Duplicate check: 0 valid semantic copies (else COMPLETE_REUSED / AMBIGUOUS — no new sign)

#### Command plan (operator-supervised)

```powershell
# 1) Ensure plan complete (pubkey + destination_channel_id)
# 2) Dry-run migration still OK:
# pwsh -File E:\TORQ-BUZZ\scripts\Invoke-TorqMigration.ps1 -PlanPath <plan> -EvidenceDir E:\TORQ-BUZZ\evidence\migration -DryRun

# 3) Operator signs offline (private terminal) with permanent human key:
#    kind=9, content exact, h=<destination_channel_uuid>
#    Write ONLY public event JSON to:
#    E:\TORQ-BUZZ\evidence\migration\<run-id>\signed-event.json

# 4) Never pass nsec as CLI arg in agent session if avoidable.
# 5) Record c3-receipt.json with destination_event_id + signed_event_sha256 (public)
```

Integration with frozen orchestrator (when live path authorized):
`-AllowPermanentHumanSign` only after C3 GO; script already refuses auto nsec load and requires public `signed-event.json`.

#### Expected evidence

| Path | Content |
|---|---|
| `...\signed-event.json` | Public event only (`id`, `pubkey`, `sig`, `kind`, `content`, `tags`) |
| `...\migration-journal.jsonl` | State → `SIGNED`; no secrets |
| `E:\TORQ-BUZZ\evidence\c3\<run-id>\c3-receipt.json` | event id, content sha256, author pubkey |

#### Stop / rollback

| Stop if | Action |
|---|---|
| Content ≠ exact string | Discard; do not publish |
| Author ≠ C2 pubkey | Discard |
| Kind ≠ 9 | Discard |
| Second signature created for retry | **Violation** — use first signed event only |
| nsec in journal | STOP; rotate |

Rollback: leave event unpublished; delete public signed file only if invalid; never “fix” by re-signing a valid event.

---

### C4 — Publish to permanent relay only

**Purpose:** Publish the **same** signed event from C3; verify with frozen verifier.

#### Publish boundary (hard)

| Rule | Value |
|---|---|
| Relay | **Only** `ws://127.0.0.1:3300` (HTTP query/event on permanent ports per config) |
| Event | Same `destination_event_id` as C3; **never re-sign** |
| Verifier | `Event::verify()` + kind 9 + author + `h` + exact content + exactly one semantic copy |
| Source | Pilot source event **unchanged** |
| Retry | Republish **same** signed payload only |

#### Preconditions

- C3 signed-event.json valid
- **C5** permanent relay ready (`/_readiness` 200 on permanent health bind)
- Plan + journal consistent
- Not publishing to pilot `:3000`

#### Command plan

```powershell
# Build verifier if needed:
# cargo build --manifest-path E:\TORQ-BUZZ\crates\torq-buzz-event-verify\Cargo.toml --release

# Live migration publish path (only after C4 GO) — example shape:
# pwsh -File E:\TORQ-BUZZ\scripts\Invoke-TorqMigration.ps1 `
#   -PlanPath E:\TORQ-BUZZ\schemas\migration\migration-plan.live.json `
#   -EvidenceDir E:\TORQ-BUZZ\evidence\migration `
#   -VerifierPath E:\TORQ-BUZZ\crates\torq-buzz-event-verify\target\release\torq-buzz-event-verify.exe `
#   -AllowPermanentHumanSign `
#   # (signed-event.json already present; DryRun NOT set)

# Explicit verify-selected-message:
# torq-buzz-event-verify verify-selected-message --input verify-selected-input.json --output verify-selected-output.json
# Expect exit 0; exits 22/23/24/26/27 fail closed
```

#### Expected evidence

| Path | Content |
|---|---|
| Journal states | `PUBLISHED` → `VERIFIED` → `COMPLETE` (or `COMPLETE_REUSED`) |
| `verify-selected-output.json` | `ok: true`, exit 0 |
| `c4-receipt.json` | destination_event_id, relay URL, verifier exit |

#### Stop / rollback

| Stop if | Action |
|---|---|
| Publish to wrong host/port | STOP; do not retry to pilot |
| Verifier nonzero | Do not re-sign; re-query; fix relay/query; republish same event if needed |
| AMBIGUOUS_DUPLICATE | Operator review; no further publish |
| Source plan drift (27) | STOP; fix plan |

Rollback: permanent event may already be immutable on relay — do not attempt delete via SQL; document and operator-review only.

---

### C5 — Permanent Compose + live permanent relay

**Purpose:** Start permanent support stack and receipt-owned permanent relay **without stopping pilot**.

#### Live-start boundary (hard)

| Item | Value |
|---|---|
| Compose project name | `torq-buzz` (env `TORQ_BUZZ_COMPOSE_PROJECT`, default in compose file) |
| Compose file | `E:\TORQ-BUZZ\compose\compose.torq-buzz.yml` |
| Volumes | `torq_buzz_pgdata`, `torq_buzz_minio` only (named in compose) |
| Postgres | `127.0.0.1:55432` |
| Redis | `127.0.0.1:16379` |
| MinIO | `127.0.0.1:19000` (console 19001) |
| Relay WS | `127.0.0.1:3300` / `ws://127.0.0.1:3300` |
| Health | `127.0.0.1:8380` |
| Metrics | `127.0.0.1:9302` |
| Process receipts | `E:\TORQ-BUZZ\state\relay-process.json` (+ startup receipt under `evidence/c5/<run-id>/`) |
| Pilot | **Do not stop** pilot relay/containers |
| Docker scope | Only project `torq-buzz`; no prune; no pilot compose down |

#### Preconditions

- C1 verified
- Image digests resolved (`Resolve-ComposeImages.ps1` live path after C5 GO)
- Secrets in ACL files for postgres/minio/relay env (**not** in git)
- Port free check: 3300, 8380, 9302, 55432, 16379, 19000 — no conflict with pilot (`3000` pilot OK to leave)
- Production source pin still `3e48f1b` + approved deltas only

#### Command plan

```powershell
$RunId = [guid]::NewGuid().ToString()
# 1) Resolve digests → config/compose.images.env (after C5 GO)
# 2) Populate config/postgres.env, minio.env, relay.env from templates + secrets (operator)
# 3) docker compose -f E:\TORQ-BUZZ\compose\compose.torq-buzz.yml --env-file ... up -d
# 4) Wait health: postgres/redis; then start permanent buzz-relay.exe with relay.env
# 5) Wait http://127.0.0.1:8380/_readiness → 200
# 6) Write process receipt (pid, path, sha256, ports, run_id, nonce) — no secrets in receipt
# 7) Buzz-Status.ps1 evidence under evidence/c5/<RunId>/
```

Use `Start-Buzz.ps1` **only after** live path is unlocked (today forces plan-only without C5 GO / ForceLive remains blocked until code path authorized).

#### Expected evidence

| Path | Content |
|---|---|
| `evidence/c5/<run-id>/compose-ps.json` | container names/ids for torq-buzz only |
| `evidence/c5/<run-id>/readiness.json` | health body |
| `state/relay-process.json` | ownership fields |
| `evidence/c5/<run-id>/startup-receipt.json` | run_id, hashes |

#### Stop / rollback

| Stop if | Action |
|---|---|
| Bind conflict on 3300 | Do not kill pilot; free permanent-only conflict or abort |
| Readiness never 200 | Stop **only** receipt-owned permanent processes; leave pilot |
| Wrong compose project | Abort; do not `down -v` pilot |
| Volume wipe temptation | **Forbidden** without separate DR GO |

Rollback (C5): `Stop-Buzz` against receipt-owned permanent relay only; `docker compose -p torq-buzz stop` (not `-v` unless separate DR); pilot untouched.

---

### C6 — Pilot stop / retirement (later)

#### Preconditions

- Permanent stack proven (C5 + C4 path green; T17/T23-class evidence)
- Explicit C6 GO
- Pilot retirement preflight receipt

#### Boundary

- Stop pilot processes **only** with ownership match
- No delete of pilot volumes without separate DR
- Capture `pilot-retirement-preflight.json` then `pilot-retirement-complete.json`

#### Stop if

Any uncertainty of process ownership; permanent stack unhealthy.

---

### C7 — Claim Gate 1 complete (later)

#### Preconditions

- C1–C5 done for deployment path used
- C4 COMPLETE / COMPLETE_REUSED with verifier exit 0
- Required T-cases green for the claimed scope
- Explicit C7 GO

#### Boundary

- Write sealed completion receipt only
- No further silent mutation

---

## 6. What remains blocked until operator approval

| Activity | Blocked until |
|---|---|
| Identity create/import / key access | **C2** |
| Sign destination kind-9 | **C3** (and usually C5 first) |
| Publish to permanent relay | **C4** (requires C3 + live C5 relay) |
| `docker compose up` project `torq-buzz` | **C5** |
| Permanent `buzz-relay` live start | **C5** |
| Pilot stop / retirement | **C6** |
| “Gate 1 complete” claim | **C7** |
| Rewrite `COPY_SELECTED_MESSAGE` | New independent defect + GO |
| Model-council / harness | Separate program GO |
| Docker prune / volume destroy | Separate DR GO |

---

## 8. C2 identity-safety (summary)

- Secrets only under ACL `secrets\`; never git; never agent paste
- Agents/scripts: **pubkey only**
- Evidence: pubkey + hashes + ACL boolean
- Exposure → rotate + stop

(See C2 section above for full process.)

---

## 9. C3 signing boundary (summary)

- One kind-9 event
- Content exact: `TORQ_BUZZ_RUNTIME_ACCEPTANCE_001`
- Permanent human author only
- Destination `h` tag required
- Public JSON only; no re-sign on retry

---

## 10. C4 publish boundary (summary)

- Target **only** `ws://127.0.0.1:3300`
- Same signed event ID
- Verifier: `Event::verify()` + semantic equality + exit 0

---

## 11. C5 live-start boundary (summary)

| Item | Value |
|---|---|
| Project | `torq-buzz` |
| Ports | 3300, 8380, 9302, 55432, 16379, 19000 |
| Receipts | `state/relay-process.json` + `evidence/c5/...` |
| Pilot | Never stop under C5 |

---

## 12. Operator-ready GO strings

Copy exactly when authorizing a single gate:

### C2 only

```text
AUTHORIZE C2 ONLY — permanent-human identity material under ACL.
Pubkey may be written to config; private key never logged or journaled.
No C3 signing. No C4 publish. No C5 Compose/relay. No pilot stop.
```

### C5 only

```text
AUTHORIZE C5 ONLY — start Compose project torq-buzz and permanent relay on
127.0.0.1 ports 3300/8380/9302 with support 55432/16379/19000.
Write process receipts. Do not stop pilot. No C2/C3/C4 identity/sign/publish.
No volume prune. No Gate 1 complete claim.
```

### C3 only

```text
AUTHORIZE C3 ONLY — sign exactly one kind-9 destination event as permanent human.
Content exact TORQ_BUZZ_RUNTIME_ACCEPTANCE_001. Destination h tag required.
Write public signed-event.json only. No publish (C4). No re-sign policy.
No pilot signer. No relay signer. No arbitrary events.
```

### C4 only

```text
AUTHORIZE C4 ONLY — publish the existing C3 signed event to ws://127.0.0.1:3300 only.
Reuse same event ID. Run torq-buzz-event-verify verify-selected-message.
Fail closed on 22/23/24/26/27. No re-sign. No pilot publish. No C6/C7.
```

### C6 only

```text
AUTHORIZE C6 ONLY — pilot retirement/stop with ownership match and preflight receipts.
Do not delete pilot volumes without separate DR GO. Permanent stack must remain healthy.
```

### C7 only

```text
AUTHORIZE C7 ONLY — seal Gate 1 completion receipt after required evidence.
No further deployment mutation in this GO. No model-council work.
```

### Combined (optional later; not default)

```text
AUTHORIZE SEQUENCE C5 THEN C2 THEN C3 THEN C4
— Stop between gates on any verifier or ownership failure
— Pilot remains protected until separate C6
— No C7 until operator review of evidence bundle
```

---

## Evidence index for this plan

| Item | Path |
|---|---|
| This plan | `E:\TORQ-BUZZ\docs\C2-C5-EXECUTION-PLAN.md` |
| C1 independent verify | `E:\TORQ-BUZZ\evidence\c1\independent-verify-c1\verify.log` |
| Gate 1 status | `E:\TORQ-BUZZ\GATE1-STATUS.md` |
| Rollback | `E:\TORQ-BUZZ\docs\ROLLBACK-PLAN.md` |
| Ports | `E:\TORQ-BUZZ\config\ports.json` |
| Compose | `E:\TORQ-BUZZ\compose\compose.torq-buzz.yml` |

---

## Stop

Planning packet only.
**No C2–C7 execution. No identity, sign, publish, Compose, permanent relay, pilot stop, or Gate 1 complete claim.**

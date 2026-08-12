# TORQ Buzz Gate 1 — Status Packet

**Updated:** 2026-08-03 (C5 incident containment)

| Layer | Status |
|---|---|
| C1 | **C1_VERIFIED_READY_FOR_C2_C5_PLANNING** |
| C5 live stack | **C5_PARTIAL_WITH_PILOT_PROCESS_REGRESSION** |
| Stop-logic fix | **DONE** (receipt-owned only; regression PASS) |
| Pilot process | **Down** (port 3000); recovery **held** for operator GO |
| Permanent compose | **Up** (torq-buzz postgres/redis/minio) |
| Permanent relay | **Down** at last inventory (was PID 3552 during C5) |
| C2–C4, C6–C7 | **Not authorized / not started** |
| `COPY_SELECTED_MESSAGE` | **Still frozen VERIFIED** (not live-run) |

## Incident package

`E:\TORQ-BUZZ\evidence\c5\pilot-stop-incident\INCIDENT-REPORT.md`

## Stop rule (mandatory)

Never: `Stop-Process -Name buzz-relay`
Only: `Stop-Buzz.ps1` with receipt match → `Stop-Process -Id <receipt.pid>`

## Next

1. Independent re-verify containment
2. Operator: pilot recovery GO (command prepared, not run)
3. Operator: optional permanent relay restart
4. Then C2 planning/execution only with new GO

**Do not begin C2 without separate authorization.**

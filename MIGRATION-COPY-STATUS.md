# COPY_SELECTED_MESSAGE — implementation status

**Status:** **VERIFIED_COPY_STEP** (independent Grok re-verify after EXIT_IO test fix)
**Recorded in main packet:** `E:\TORQ-BUZZ\GATE1-STATUS.md`
**Date:** 2026-08-03

## Authorization history

| Event | Result |
|---|---|
| Operator `go` — migration logic only | Authorized build |
| Independent verify (pre EXIT_IO test) | RETURN_TO_BUILDER (exit 24 untested) |
| Bounded test fix | `t_copy_verifier_exit_io_malformed_events_json` |
| Independent re-verify | **VERIFIED_COPY_STEP** |

**Still not authorized:** permanent-human signing, live publish, pilot mutation, runtime deploy, Docker/launcher changes, full Gate 1 remainder.

## Built (verified)

| Artifact | Path |
|---|---|
| State machine + journal + retry/recovery | `crates/torq-buzz-event-verify/src/` |
| Verifier CLI (`verify-selected-message`, `filter-semantic-copies`) | `crates/torq-buzz-event-verify` |
| Journal JSON Schema | `schemas/migration/copy_selected_message.schema.json` |
| Orchestrator (dry-run default) | `scripts/Invoke-TorqMigration.ps1` |
| Integration tests | `crates/torq-buzz-event-verify/tests/copy_selected_message.rs` |

## Contract

- Source event: `5ff77c3fb4c15b8362c23398a998e45a9fe77d13622adcd9a88cd2f3115dd670`
- Content: `TORQ_BUZZ_RUNTIME_ACCEPTANCE_001`
- Kind: `9` · Relay: `ws://127.0.0.1:3300` · Author: permanent human only
- States: `PLANNED → DUPLICATE_CHECKED → SIGNED → PUBLISHED → VERIFIED → COMPLETE`
- Terminals: `COMPLETE_REUSED`, `AMBIGUOUS_DUPLICATE`
- Duplicate: 0 sign once · 1 reuse · >1 stop
- Publish retry: same signed event ID only
- Exit codes tested: **0, 22, 23, 24, 26, 27**

## Test evidence

| Item | Value |
|---|---|
| Command | `cargo test --manifest-path E:\TORQ-BUZZ\crates\torq-buzz-event-verify\Cargo.toml --all-targets` |
| CWD | `E:\TORQ-BUZZ` |
| Exit | 0 |
| Unit | 15 passed |
| Integration | 9 passed |
| EXIT_IO test | `t_copy_verifier_exit_io_malformed_events_json` |
| Re-verify log | `evidence/migration/reverify-exit-io/` |

## Pilot tree

**Unchanged.** Implementation lives under `E:\TORQ-BUZZ` only.
Pilot dirty path remains only accepted `replica_fence.rs`.

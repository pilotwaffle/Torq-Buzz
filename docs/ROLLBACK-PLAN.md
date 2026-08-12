# TORQ Buzz Gate 1 — Rollback Plan (C1)

## Scope

Software / pointer rollback only under C1. **No live volume destroy** under C1.
DR overwrite of live data is separately gated (T34 / C5+).

## What C1 can roll back safely

1. **Production worktree code deltas** (CTRL_BREAK / bind-address):
   ```text
   cd E:\TORQ-BUZZ\source\buzz
   git checkout -- crates/buzz-relay/src/config.rs crates/buzz-relay/src/main.rs crates/buzz-relay/src/metrics.rs
   ```
   Or remove the worktree and re-add clean pin `3e48f1b`.

2. **Deployment scaffolding under E:\TORQ-BUZZ** (scripts/config/compose):
   - Restore from git if TORQ-BUZZ is versioned, or re-run Initialize from templates.
   - Do **not** delete `crates/torq-buzz-event-verify` (VERIFIED_COPY_STEP) unless operator explicitly orders it.

3. **Evidence / dry-run artifacts**:
   ```powershell
   pwsh -File E:\TORQ-BUZZ\scripts\Remove-TestArtifacts.ps1 -RunId <run-id>
   ```

## What C1 must never do

- `docker compose down -v` / volume prune
- Pilot stop or pilot file deletion
- Secret rotation without separate auth
- Claiming permanent cutover rolled back when C5 never started (nothing live)

## Future (C5+) rollback outline

1. Stop only receipt-owned permanent processes (Stop-Buzz with ownership match).
2. Swap `releases/current` pointer to previous release manifest hash.
3. Restart with prior binaries; keep volumes unless DR approved.
4. Re-verify readiness + selected history.
5. Write `rollback-receipt.json`.

## Pilot

Pilot remains the recovery path until C6 retirement authorization.
Pilot path: `E:\TORQ-CONSOLE\tmp\buzz-pilot\20260731-004310`

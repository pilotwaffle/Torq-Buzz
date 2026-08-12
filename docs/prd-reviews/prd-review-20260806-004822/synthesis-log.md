# Synthesis Log

## Cycle 1 disposition

All Critical and High findings were accepted because they materially improve authorization correctness, revocation safety, recovery determinism, scope control, and testability.

| Finding | Disposition | Revision |
|---|---|---|
| Authorization hierarchy incomplete | Accepted | Added distinct connection role/principal kind/membership role definitions and normative command matrix |
| Revocation concurrency undefined | Accepted | Added auth/member/channel epochs, coordinator lock, commit linearization point, queue purge, and pre-socket-write validation |
| Task bridge exactly-once gap | Accepted by scope removal | Task bridge moved to a separate follow-on PRD; no task dispatch in v1 |
| State machines deferred | Accepted | Added normative principal, credential, membership, channel, message/tombstone, and subscription transitions |
| Data constraints incomplete | Accepted | Added concrete tables, checks, composite FK for same-channel targets, unique idempotency, strict payload schemas, and transaction checks |
| Credential security unresolved | Accepted | Froze 256-bit bearer format, HMAC-SHA-256 with 32-byte deployment pepper, rate limits, rotation, bootstrap retirement, backup, and locked recovery |
| Hidden-channel timing vague | Accepted | Defined identical code/shape contract, same prepared query requirement, and a bounded regression harness |
| Reduce v1 scope | Accepted | Deferred task bridge, FTS, Git, threads, reactions, edits, and hash chain to separate PRDs |
| Single operator plus agents | Accepted | v1 has exactly one active operator and operator-owned agents |
| Exclude edits/reactions | Accepted | v1 messages are immutable; operator tombstones only |

No material reviewer finding was rejected.

## Resulting artifact

`E:\TORQ-BUZZ\docs\PRD-TCLAW-COLLABORATION-SUBSTRATE-001-v0.2.md`

The version 0.1 input remains preserved unchanged.

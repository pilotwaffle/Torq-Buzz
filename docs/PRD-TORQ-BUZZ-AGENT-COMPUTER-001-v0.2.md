# PRD-TORQ-BUZZ-AGENT-COMPUTER-001

Status: Draft for operator review — **v0.2e, contract implementation available; archive deletion approval and live §16 evidence pending**
Version: 0.2e
Date: 2026-09-04
Owner: TORQ-BUZZ operator (sole human principal)
Target: Windows-first, self-hosted, single-operator deployment on the existing Torq-BUZZ installation (`E:\TORQ-BUZZ`); interfaces must not preclude a future always-on remote "computer" host
Implementation repositories: `E:\TORQ-BUZZ\source\buzz` (desktop + `buzz-acp`, `buzz-workflow`, relay handlers)
Supersedes: v0.1 (`docs/PRD-TORQ-BUZZ-AGENT-COMPUTER-001.md`, preserved unmodified)

## 0. Revision notes v0.2 (response to council review)

| # | Verdict finding | Disposition |
|---|---|---|
| 1 | Fatal: ACP agents are protocol subprocesses; ConPTY keystrokes would corrupt NDJSON ACP traffic (`crates/buzz-acp/src/acp.rs`). | **Accepted.** buzz-terminald removed from design. Live visibility built on the existing observer stream; raw terminal takeover demoted to an optional Phase-2 outcome of the §16 spike, gated on proof it preserves ACP traffic. |
| 2 | Major: duplicates existing systems — `desktop/src-tauri/src/terminal_runtime.rs`, `buzz-acp/src/observer.rs`, relay live-activity frames, `buzz-workflow` cron/approvals/claims/run history. | **Accepted.** New daemons removed; all features are extensions of observer, the encrypted control plane, and the workflow engine. |
| 3 | Critical: "terminal events never contain secrets" unachievable via redaction. | **Accepted.** Raw activity is **encrypted, owner-scoped, ephemeral by default**, retained locally only under explicit bounded opt-in policy. Redaction is defense-in-depth, never the boundary. Relay-persisted raw frames eliminated. |
| 4 | Major: visibility ≠ authorization. | **Accepted in v0.2; superseded by v0.2b finding 21.** The initial grant-intersection proposal was narrowed after implementation research found no grants subsystem. |
| 5 | Major: "exactly once" unachievable. | **Accepted.** All dispatch specified as **at-least-once** with durable claim keys, idempotency, crash recovery, missed-window policy, duplicate suppression. |
| 6 | Major: premature estimates; relay frame volume (~1.3M events/day) unrealistic. | **Accepted.** Estimates removed until after the spike; frame-persistence design eliminated, removing the volume problem. |
| 7 | Editorial: future dating, "fan-off", "handoff" name collision with `crates/buzz-agent/src/handoff.rs` (context compaction). | **Accepted.** Dated correctly; capability renamed **delegation** throughout. |
| — | P2: per-agent git invariant deferred. | **Accepted.** Deferred pending explicit workspace isolation/migration design. |

No findings were rejected. The riskiest assumption in v0.1 (external daemon observing/driving ACP subprocesses it does not own) is retired; the new riskiest assumption is §16.

**Post-verdict addition (operator token-usage audit, 2026-09-03):** required per-routine and per-delegation token budgets with auto-pause were added to FR-3/FR-4 after analysis of the operator's own bills showed unattended agent loops × long context as the burn pattern (~1.09B cache-read tokens over 46 active hours on Grokbot; a $290 Claude session producing ~3.4k added lines with a $59 marginal spend for ~0 net lines).

### Revision notes v0.2a (second review pass, 2026-09-03 — verified against source)

| # | Finding | Disposition |
|---|---|---|
| 8 | "buzz-acp untouched" (§1) conflicts with pause/resume and new control envelopes. | **Accepted.** Restated: ACP wire protocol and harness CLIs unchanged; `buzz-acp` takes bounded extensions. |
| 9 | Pause was specified as a capability ACP does not have. `ControlSignal` provides Cancel/Interrupt/Steer/Rotate/SwitchModel only (`crates/buzz-acp/src/pool.rs`); no pause exists. | **Accepted.** Pause redefined as a queue hold at the next safe boundary (§6.6), mirroring the existing `WorkflowStatus::Disabled` semantics rather than inventing a second meaning. |
| 10 | Leases applied to one-shot commands. | **Accepted.** Cancel/steer are `command_id`-scoped one-shot commands; pause is the only leased control (§6.7, FR-2). |
| 11 | "Grant intersection" named no execution mechanism. | **Accepted in v0.2a; superseded by v0.2b finding 21.** `ExecutionAuthorityContext` is replaced by a non-authorizing `DelegationExecutionContext`; see §6.4, FR-4, and §17. |
| 12 | `task_json` persisted as cleartext relay metadata (§10). | **Accepted.** Task body removed from the record; `origin_event_id` references the encrypted originating message. |
| 13 | Archive claimed opt-in; shipped default is enabled (`desktop/src-tauri/src/commands/observer_archive.rs`). | **Partly implemented.** Fresh identities default off and SQLite subscription state is the sole consent authority. Legacy kind-24200 rows cannot distinguish automatic seeding from explicit consent. Resetting those subscriptions requires operator approval and has not been implemented; existing rows and history remain (§6.3). |
| 14 | "No absolute host paths in payloads" unachievable — tool args/output legitimately contain paths. | **Accepted.** Weakened to: new envelope metadata introduces no host paths; displayed tool content minimized and redacted best-effort (§6.8). |
| 15 | Steer question was not binary — capability-aware steering with fallback already ships (`pool.rs`), and the transcript already parses steer messages (`desktop/src/features/agents/ui/agentSessionTranscript.ts`). | **Accepted.** §17 resolved as layered intent/delivery; no new steer transport built. |
| 16 | Relay suitability unknown. | **Resolved, not changed.** Kind 24200 already provides owner-gated encrypted telemetry, subscription gating, verification, freshness, and rate limiting (`crates/buzz-relay/src/handlers/event.rs`). Confirm end-to-end in Slice 0. |
| 17 | 48-hour spike mixed Phase-2 discovery (PTY probe) into the Phase-1 gating path. | **Accepted.** Spike replaced with five contract-freezing tests; the PTY probe moves out of the window (§16). |
| 18 | Residual phrasing: "daemon/relay restart", "byte-identical behavior". | **Accepted.** Corrected to "workflow executor/relay restart" and "existing wire contracts and smoke behavior unchanged". |
| 19 | FR-4 cost cap defaulted to "source agent's remaining run budget" — no such primitive exists. | **Accepted.** Default removed; `max_turns` is the enforceable limit, `cost_cap_microusd` optional, unknown cost refuses under a specified cap. |
| 20 | Anti-enumeration was prose with no test hook; pause-lease expiry was not separately audited. | **Accepted.** Enumeration probe is a Slice-0 fixture; pause lease lifecycle events added to FR-5. |

### Revision notes v0.2b (implementation research, 2026-09-04)

| # | Finding | Disposition |
|---|---|---|
| 21 | No grants subsystem exists, so a three-principal grant intersection cannot be implemented or revalidated honestly. | **Resolved by narrowing scope.** Initial delegation transfers work, not permissions: same-owner agents only, operator approval before dispatch, and the target runs under its existing authority and approval gates. Autonomous authority transfer is deferred. |
| 22 | Fresh identities currently archive observer activity automatically, contrary to the opt-in invariant. | **Implemented.** Fresh identities and recovered databases default off. Startup never recreates consent from browser storage; only an explicit UI action creates the authoritative SQLite kind-24200 subscription. |
| 23 | Current UI exposes ACP, observer-frame, kind, and pubkey terminology to the operator. | **Implemented.** Primary copy now uses “Live activity” and “Agent activity history”; protocol terminology remains in diagnostics only. |

### Revision notes v0.2d (Slice-0 delegation hardening, 2026-09-04)

| # | Finding | Disposition |
|---|---|---|
| 24 | Hop count alone cannot detect an A→B→A delegation cycle. | **Resolved.** The immutable request binds a bounded `agent_path` plus the parent approval id for nested hops. The child must extend an opaque lineage token minted from the current durable execution permit by exactly one target. A fresh direct record cannot erase active ancestry. |
| 25 | Approval expiry was not stored in the record or cryptographically bound. | **Resolved.** `expires_at` is part of the immutable request hash, approval content, and approval tags; `now >= expires_at` fails closed. |
| 26 | Replay is stateful and cannot honestly be rejected by JSON-schema validation. | **Resolved.** Stateless context validation is separated from a durable atomic three-key claim plus durable enqueue. Delegation id, approval id, and tenant/caller-scoped idempotency uniqueness are reserved together; exact pending/completed duplicates collapse, conflicting reuse is rejected, and store failure fails closed. |
| 27 | Workflow approval kind `46030` has incompatible client/relay token shapes and does not bind a delegation request. | **Resolved.** Delegation approval receives a dedicated inert kind `43007` and strict signed envelope. Relay ingestion remains disabled until the feature-gated Slice-4 handler exists. |
| 28 | Raw replay keys and request hashes can collide across tenants or sibling agents. | **Resolved.** The immutable request hash includes the server-resolved `CommunityId`; uniqueness keys are `(community_id, delegation_id)`, `(community_id, approval_event_id)`, and `(community_id, operator_pubkey, source_agent, idempotency_key)`. Claim markers remain through signed expiry. |
| 29 | Checking cost before dispatch is a TOCTOU and post-run actual cost cannot enforce a hard cap under concurrency. | **Resolved.** Capped actions require a conservative enforceable reservation. A tenant-scoped CAS atomically checks committed cost/turns, reserves cost, decrements a turn, and records the action before dispatch; settlement releases unused reservation. Unknown or unenforceable bounds refuse. |
| 30 | A named fixture manifest can drift without exercising the declared outcomes. | **Resolved.** The shared 40-case delegation matrix executes validation and reference-classifier paths, including duplicate states, all three claim-key conflicts, sequential turn attenuation, revision-only ownership changes before CAS and outbox dispatch, cross-tenant claim/action/parent, stale/stripped lineage, cycles, expiry, and cost overflow. Durable storage integration remains a Slice-4 gate. |
| 31 | Statelessly validated context could mint reusable parent lineage, bypassing live-run/tenant/expiry proof. | **Resolved.** `ResolvedDelegationLineage` has no public Slice-0 constructor. Slice 4 may mint it only from its private live execution permit; it binds community, run/delegation identity, approval/hash, signer, expiry, and path. Unavailable lineage fails closed. |
| 32 | Caller-selected `delegation_id` was not uniquely claimed, so two approvals could target one action row. | **Resolved.** `(community_id, delegation_id)` is a third atomic conflict key, reserved with approval/idempotency keys and durable enqueue. |
| 33 | A pre-expiry action token could be consumed after expiry or against a different approved claim. | **Resolved.** The opaque action token carries community, delegation id, approval id, request hash, and expiry. The transaction rechecks time and exact claim identity before its CAS commits. |
| 34 | A pre-expiry claim token could reserve keys/enqueue after expiry. | **Resolved.** `DelegationClaim` exposes transaction-time freshness validation; the atomic claim transaction must check its own current time before reserving any key or outbox row. |

### Revision notes v0.2e (Slice-0 integration hardening, 2026-09-04)

| # | Finding | Disposition |
|---|---|---|
| 35 | A pause transition id could be forgotten after a newer lease replaced the current row, allowing a still-fresh historical pause to look new. | **Contract defined.** Slice 2 must atomically claim a separate tenant-scoped transition tombstone with lease state; historical exact retries must not mutate the current row. Slice-0 fixtures cover reference classification, not persistence or crash recovery. |
| 36 | Delegation used the context turn count as an equality, so action two failed after action one decremented durable state. | **Resolved.** Context turns are an immutable ceiling; each action token carries the exact durable pre-CAS value, permitting N→N-1 while refusing upward escalation. |
| 37 | Delegation and structured controls could lose ownership authority between validation, durable commit, and effect. | **Resolved at the Slice-0 contract seam.** Opaque tokens bind monotonic owner/visibility revisions; transactions and outbox consumers must re-resolve them. A stale persisted pause releases rather than holding a new owner's queue. |
| 38 | Observer consent existed in both localStorage and SQLite, so a failed browser write could silently reverse an OFF decision after restart. | **Resolved.** SQLite subscription state is the sole authority; browser markers cannot create or repair consent. Buffered frames recheck consent inside the same immediate write transaction. |
| 39 | The existing observer archive had no enforced age, event-count, or logical-byte retention bound. | **Partly addressed.** New-save admission limits can stop growth without deleting history. Automatic age/count/byte pruning and the legacy subscription reset were rejected by automatic approval review pending explicit operator authorization. No startup pruning or seven-day expiry is implemented. |
| 40 | `invoke_agent` could drift into a parallel scheduler or admit underspecified destinations/prompts. | **Resolved.** It is a strict action on the existing workflow engine with exact target/channel/idempotency fields, post-template validation, and a minimum 15-minute schedule cadence; execution remains inert until Slice 3. |

## 1. Executive decision

Deliver the three Grokbot-style capabilities — **live visibility into agent work, safe operator intervention, and scheduled + delegated agent work** — by extending systems Buzz already ships:

1. **Live Activity**: render the existing encrypted observer stream (`buzz-acp/src/observer.rs`) as a human-readable activity timeline in the desktop app, sub-two-second latency.
2. **Structured controls**: cancel / pause / steer / resume, sent through the existing encrypted control path — no raw keyboard takeover in this release. Cancel and steer are one-shot commands; only pause holds a renewable lease (§6.7, FR-2).
3. **Routines and delegation**: an `invoke_agent` action on the existing `buzz-workflow` engine (which already has cron/interval schedule triggers, approvals, claims, and run history), plus an operator-approved typed delegation contract between same-owner agents.

No new daemons. No relay-persisted raw terminal frames. The ACP wire protocol and the harness CLIs remain unchanged; `buzz-acp` receives bounded extensions for control routing and queue-level pause state.

Remote-computer evolution (agents on an always-on server so the PC can be off) remains a stated future milestone; the only v0.2 carry-over constraints are `computer_id` tagging in new events and loopback-safe service boundaries — full hardening moves to that milestone's own PRD.

## 2. Problem

Unchanged from v0.1 §2: agents are black boxes; nothing can be scheduled; the operator is the router between agents; closing the PC stops everything. The council's framing is adopted: the operator needs **visibility and safe intervention**, not necessarily a literal terminal.

## 3. Research basis

Unchanged from v0.1 §3, plus:

- **Internal architecture audit (2026-09-03, verified)**: `desktop/src-tauri/src/terminal_runtime.rs` (existing PTY sessions + terminal UI), `crates/buzz-acp/src/observer.rs` (encrypted, owner-scoped activity and control frames), `crates/buzz-relay/src/handlers/event.rs` (author-only/owner-scoped delivery gates), `crates/buzz-workflow/src/schema.rs:57-62` (`TriggerDef::Schedule { cron, interval }`, approvals, claims, run history), `crates/buzz-agent/src/handoff.rs` (existing context-compaction "handoff" — hence the rename to delegation).
- **OpenBot correction (accepted)**: OpenBot keeps Activity browser-local and persists audit *metadata* rather than raw command output — safer than v0.1's relay-persisted frames. v0.2 adopts that posture.

## 4. Target user and jobs

Unchanged from v0.1 §4, with "watch its terminal live" restated as "watch a readable Live Activity stream of what it is doing," and "take control of its terminal" restated as "cancel, pause, steer, or resume its work safely."

## 5. Measurable outcomes

- Live Activity for any connected agent renders with ≤ 2 s latency, readable (tool calls, progress, output excerpts) — not raw NDJSON.
- Operator can cancel a running agent turn within 2 s; pause/steer/resume complete within 5 s; every control action is audited with operator identity, and pause additionally with lease identity and duration.
- A routine created by chat fires on its cron/interval schedule, routes through the existing approval path where required, and posts results to the originating channel; duplicate firings after workflow executor/relay restart are suppressed by claim key.
- A delegation between two agents produces exactly one collapsed summary line plus one attributed relayed answer; hop budget and turn limit enforced at execution time.
- Feature-off: all flags off → existing wire contracts and smoke behavior unchanged.
- Spike outcomes (§16) are recorded and drive the go/no-go for any Phase-2 terminal work.

## 6. Product principles and invariants

1. Reuse over rebuild: observer, control plane, workflow engine, relay gates. No parallel stacks.
2. buzz-acp owns its process and protocol. Nothing external writes to an ACP subprocess's stdin.
3. Raw activity is encrypted and owner-scoped. Fresh identities and recovered databases default to ephemeral operation: the authoritative opt-in is the current identity+relay SQLite `owner_p` subscription containing kind 24200, and browser storage cannot create or repair consent. Existing subscriptions remain unchanged; ambiguous legacy rows may have been automatically seeded. A reset of those rows and automatic seven-day/count/byte pruning require explicit operator approval. Until then, new-save limits stop additional growth without deleting history. Redaction remains display-layer defense-in-depth.
4. **Delegation transfers work, not authority.** Initial-release targets must be owned by the same operator. The source agent may draft a request, but dispatch requires operator approval; the target then runs under its own existing authority and approval gates. A `DelegationExecutionContext` carries provenance, signed bounded ancestry (`agent_path` plus parent approval for nested hops), hop count, limits, expiry, and idempotency through the run but grants no permissions. Parent lineage can be minted only from the private durable live-run permit; tenant, lineage, monotonic owner/visibility revisions, expiry, turns, exact claim identity, and any cost reservation are revalidated from trusted runtime state at validation, durable commit, and immediately before effects. Missing, forged, expired, replayed, lineage-stripped, tenant-mismatched, or owner-mismatched context fails closed. Stateless validation must be followed by atomic three-key claim plus durable enqueue; a caller-asserted replay flag is not authority. Autonomous agent-to-agent authority transfer is deferred until Buzz has a real grants model.
5. All dispatch is at-least-once: durable claim keys, idempotent handlers, explicit missed-window policy, duplicate suppression. No "exactly once" claims anywhere.
6. **Pause means: hold new work at the next safe boundary.** ACP supports cancellation and steering; it cannot suspend a model call already executing. Pause therefore holds the agent's queue — the in-flight turn runs to its boundary — and resume releases that hold. Freezing an in-flight turn is explicitly out of scope (§7.2). This mirrors the existing `WorkflowStatus::Disabled` semantics in `crates/buzz-db/src/workflow.rs` ("paused and will not fire") and must not introduce a second, divergent meaning of pause.
7. Control actions require operator identity and are audited. **Cancel and steer are one-shot commands** carrying `command_id`, expiry, and acknowledgement — not leases. **Pause is the only leased control**: it owns renewable persistent state and expires safely to resume.
8. New events carry `computer_id`, `agent_pubkey`, `run_id`, monotonic sequence. New envelope metadata does not introduce host paths; displayed tool content is minimized and redacted best-effort (tool arguments and output may legitimately contain paths).
9. Feature flags default off; each capability ships independently.

## 7. Scope

### 7.1 In scope

- **Live Activity panel** in the desktop app: render observer events (tool calls, progress, bounded output excerpts, status) as a timeline; busy indicators on the roster.
- **Structured controls**: cancel / pause / steer (inject an operator message via the agent's normal ACP session path) / resume, over the encrypted control plane, with leases and audit events.
- **`invoke_agent` workflow action**: target agent, prompt/context, channel for results; composable with existing schedule triggers → routines; existing approvals/claims/run history apply unchanged.
- **Delegation contract**: typed record (origin event, source agent, same-owner target agent, operator approval event, constraints, hop budget, turn/cost limits, idempotency key); collapsed summary line + attributed relayed answer in the originating thread; failure notices.
- Audit events for control actions, routine lifecycle, delegation lifecycle. Bounded local metrics.

### 7.2 Non-goals (unchanged, plus)

- No raw terminal takeover, no buzz-terminald, no xterm.js rendering of ACP streams (Phase-2 spike outcome only).
- No new scheduling daemon (workflow engine owns scheduling).
- No relay persistence of raw activity frames.
- No per-agent workspace/git invariant in this release (deferred, pending isolation/migration design).
- Voice, mobile, per-agent containers/sandboxing, CEL policy engine, multi-operator support — unchanged from v0.1.
- Server/remote-computer deployment — future milestone, own PRD.

## 8. User flows

### 8.1 Watch an agent work

Open agent conversation → Live Activity panel renders the observer stream (status, tool calls, output excerpts) within 2 s. Scrolling back loads bounded, policy-retained history; a stale/disconnected state is shown explicitly.

### 8.2 Intervene safely

Operator selects Cancel / Pause / Steer / Resume on the active run. The action travels over the encrypted control path, is acknowledged by buzz-acp, and appears in the audit trail: cancel and steer as one-shot commands with `command_id` and expiry, pause with its lease and expiry. Steer delivers a structured operator message the agent sees at its next decision point — never keystrokes. Pause holds the queue at the next safe boundary rather than freezing the running turn (§6.6).

### 8.3 Create a routine in chat

Operator asks an agent for recurring work → the agent (via granted workflow tools) drafts an `invoke_agent` routine bound to a schedule trigger → operator confirms (existing approval UI) → the routine runs with existing claims/run history; results post to the channel; failures follow the engine's existing failure semantics plus 10-strike auto-pause.

### 8.4 Agent delegates to agent

Source agent drafts a typed delegation request. The operator reviews and approves it; only then may the same-owner target agent start a session. The target receives a `DelegationExecutionContext` for provenance and limits but runs under its own existing authority and approval gates—no permissions move from source to target. The originating thread shows one collapsed summary and one attributed answer. Hop budget and turn limit (plus an optional cost cap) are enforced per action. Missed/dead delegations produce a plain-language notice after max attempts.

## 9. Functional requirements

### FR-1: Live Activity rendering

- Timeline view over observer events with ≤ 2 s end-to-end latency; tool calls collapsible; output excerpts bounded (byte cap per event; "show more" loads from bounded local retention if enabled).
- Roster busy indicator sourced from observer status events.
- Never renders raw protocol frames; a readability layer maps events to structured entries. Prototype readability is a Slice-1 gate (council: buyer concern).

### FR-2: Structured controls

- cancel/pause/steer/resume over the existing encrypted control plane, operator-identity-only, audited.
- **Cancel and steer are one-shot commands**, not leases: each carries `command_id`, an expiry after which an unacknowledged command is abandoned, and a required acknowledgement. Replays of a spent `command_id` are rejected.
- **Steer**: a durable new operator message is the intent; delivery is an optimization. The existing capability-aware path is reused as-is — native `_goose/unstable/session/steer`, then the cross-adapter `_session/steering` method when the agent advertised `_meta.steering.supported`, then the universal cancel-and-merge fallback (`crates/buzz-acp/src/pool.rs`, `ControlSignal::Steer`). If the agent is idle the message starts a turn normally. No new steer transport is built.
- **Pause is the only leased control** (default 5 min, renewable). It holds the agent's queue at the next safe boundary per §6.6; the in-flight turn is not frozen. Resume releases the hold. Lease lapse auto-releases to resume, and the release is audited.
- Pause state is persistent and must survive process restart; recovery re-reads the lease and its expiry rather than assuming a paused agent is running.
- buzz-acp remains the sole owner of its process; cancel and steer map to ACP session semantics already supported, and pause is enforced at the queue layer above ACP.

### FR-3: invoke_agent action (routines)

- New action type on `buzz-workflow`: `{ agent_pubkey, prompt, result_channel, idempotency_key }`.
- Composable with existing `TriggerDef::Schedule { cron | interval }`; 15-minute minimum interval; 20 enabled routines per agent cap; runs under the creating principal's grants; existing approval gates unchanged.
- At-least-once firing with durable claim keys; missed windows skipped, never replayed in bulk; duplicate deliveries collapse by idempotency key.
- **Token budget per routine (required)**: every routine spec carries `token_budget_per_run` and `token_budget_per_day`. A run exceeding its per-run budget is terminated and counted as a failure; breaching the daily budget auto-pauses the routine with one notice (independent of the 10-strike rule). (Added 2026-09-03 after operator bill analysis: unattended loops × long context were the burn pattern — see §0.)

### FR-4: Delegation contract

- Typed record; free-text agent-to-agent chatter is not delegation and is not surfaced as such.
- **Token budget per delegation (required)**: the immutable request carries an explicit token budget; consumption is enforced in the same per-action boundary as `max_turns`/cost reservations (see below); exhaustion terminates the run as `failed(budget)`; hops consume the budget, never extend it. (Added 2026-09-03 after operator bill analysis — see §0.)
- **Authority boundary**: every agent in the signed `agent_path` must resolve in the current tenant to the operator who signed the approval. Nested requests also bind the parent approval id and must extend an opaque lineage token from the current durable live-run permit by exactly one target. That token binds tenant, run/delegation identity, approval/hash, signer, expiry, and parent path; it cannot be minted from stateless context. The source can draft, but the target cannot start until an operator-signed kind `43007` approval references the delegation id and its tenant-bound immutable request hash. The target uses its normal authority and existing approval gates; delegation never copies, unions, or intersects permissions.
- **Execution context**: `DelegationExecutionContext` contains the immutable request (delegation id, origin event id, optional parent approval event id, source agent, target agent, bounded `agent_path`, hop budget, max turns, optional cost cap, idempotency key, expiry), operator approval event id, immutable request hash, hop count, and remaining turn limit. It is provenance and constraint data, not an authorization grant. Missing, forged, expired, lineage-stripped, tenant-mismatched, or owner-mismatched context fails closed.
- **Replay boundary**: `validate_for_claim` verifies the complete approval event, server-resolved tenant and parent lineage, current owners, bindings, expiry, and constraints. At transaction time, freshness is rechecked; then a durable transaction atomically claims `(community_id, delegation_id)`, `(community_id, approval_event_id)`, and `(community_id, operator_pubkey, source_agent, idempotency_key)` **and commits a durable work/outbox row**. Exact matching retries collapse only when work is durably pending or completed; any key reused with different binding data returns `approval_replay`; claim-store failure returns `authority_unavailable`. Claim rows remain through signed expiry. Only the Slice-4 transaction seam may create a private execution permit.
- **Per-action boundary**: before every action, revalidate tenant, expiry, current path ownership, durable remaining turns, and committed cost. The opaque action token carries tenant, delegation id, approval id, immutable hash, expiry, expected turn/cost state, and reservation. For a specified cost cap, require a conservative enforceable reservation. Inside the transaction, recheck current time, CAS the exact claim identity and state, decrement one turn, add the reservation, and record the action before dispatch. Settle actual cost afterward by releasing unused reservation. Unknown bounds, overflow, post-validation expiry, stale CAS, or inability to enforce the reservation refuse the action.
- **Hop budget**: default 1, hard maximum 2 for the initial release.
- **Limits**: `max_turns` is the enforceable budget (it exists today as `max_turns_per_session` in `crates/buzz-acp/src/config.rs`). An optional integer `cost_cap_microusd` may be set; when a monetary cap is specified and a conservative action-cost reservation is unknown or unenforceable, the action is refused rather than silently passed. There is no implicit "remaining run budget" default, because no such budget primitive exists.
- Refusal wording identical for invisible/nonexistent targets (anti-enumeration); this is a Slice-0 fixture, not prose only.
- Relay-back answer attributed to the target agent; failure notice after max attempts; all transitions audited.

### FR-5: Audit and metrics

- Audit events: control_issued/ack/expired, **pause_lease_granted/renewed/released/expired** (the expiry path silently releases a queue hold, so it is audited distinctly), routine created/approved/fired/succeeded/failed/auto-paused, delegation offered/approved/refused/delivered/failed, **delegation_context_denied** (missing, invalid, expired, replayed, or owner-mismatched `DelegationExecutionContext`).
- Metrics: control latency, routine fire latency/failure counts, delegation counts by outcome. No bodies or prompts in metrics.

### FR-6: Feature flags

- `BUZZ_LIVE_ACTIVITY`, `BUZZ_AGENT_CONTROLS`, `BUZZ_ROUTINES`, `BUZZ_DELEGATION` — all default off; off means no new events and unchanged behavior.

## 10. Data contracts (proposed; frozen in Slice 0)

```text
delegation_records     (relay-persisted metadata only; no raw activity, no task body)
  request: id, origin_event_id, parent_approval_event_id nullable,
           source_agent, target_agent, agent_path,
           hop_budget, max_turns, cost_cap_microusd nullable,
           idempotency_key, expires_at
  operator_approval_event_id nullable,
  immutable_request_hash = SHA-256(domain + server-resolved community_id + request),
  state(offered|approved|refused|delivered|failed|expired),
  answer_event_id nullable, created_at, updated_at
  -- The task body is NOT persisted here. It stays in the encrypted originating
  -- message; `origin_event_id` is the reference. Task instructions can carry
  -- sensitive content, so only identifiers, state, limits, and timestamps are
  -- stored in cleartext relay metadata.

routine specs          (existing workflow tables; invoke_agent action params)
routine claim key      routine_id+fire_instant — durable, atomic, idempotent
delegation claim keys  community_id+delegation_id |
                       community_id+approval_event_id |
                       community_id+operator_pubkey+source_agent+idempotency_key
                       — retained through expiry; atomic with work/outbox enqueue
delegation action row  community_id+delegation_id+approval_event_id+immutable_request_hash+
                       remaining_turns+committed_cost_microusd+expires_at
                       — exact-claim CAS rechecks time, then reserves one turn and bounded cost
```

Raw activity: **not persisted to relay**; observer's existing encrypted ephemeral channel is the transport. The desktop archive retains encrypted observer content plus routing metadata when its SQLite subscription is enabled. New-save admission limits are 256 KiB per raw event, 10,000 events, and 64 MiB logical raw JSON per identity+relay; existing over-limit history is preserved and further new saves are refused. Automatic pruning, including the proposed seven-day age limit, and resetting ambiguous legacy subscriptions await explicit approval. These are logical-data limits, not a physical SQLite/WAL size promise (§6.3).

## 11. Security and privacy

- Activity visibility follows the existing owner-scoped, encrypted observer gates; relay delivery gates (`event.rs` author-only paths) are the chokepoint and are not widened.
- Local archive (if enabled): observer content remains NIP-44 ciphertext, routing metadata is local, retention is bounded, access is operator-only, and redaction is applied at display time. A fresh identity must not begin archiving activity before the operator has made a choice (§6.3); this is an acceptance test, not an assumption.
- Delegation cannot widen authority (§6.4): current same-owner validation covers the complete signed `agent_path`; nested hops must extend server-derived parent lineage; and operator approval gates dispatch while the target's existing authority and approval path govern execution. Tenant/owner changes, approval expiry, exhausted turns, or an unavailable cost reservation halt the delegation before its next action.
- Control actions are operator-only and audited; cancel/steer are one-shot and pause is leased (§6.7). No path injects bytes into ACP protocol streams.
- Delegation task bodies are never persisted as cleartext relay metadata (§10); only identifiers, state, limits, and timestamps are.
- Threat model additions: stale lease reuse, **replay of a spent `command_id`**, **a delegation context, parent lineage, or operator approval stripped, forged, expired, replayed, cross-tenant, or owner-mismatched (must fail closed)**, cross-record delegation-cycle evasion, replay-key squatting, concurrent cost-cap overspend, routine prompt injection (agent treats routine prompt as untrusted, existing invariant), archived-activity theft (local encryption), observer-stream replay (run_id + seq).

## 12. Non-functional requirements

- Live Activity latency ≤ 2 s p95; controls acknowledged ≤ 2 s, effective ≤ 5 s.
- Routine fire-to-agent-inject ≤ 60 s p95; scheduler restart recovers due work without double-firing.
- No relay write-amplification: ephemeral activity traffic uses the existing observer channel, not new persistent kinds; delegation/routine/audit events are low-volume by construction.
- Accessibility: panel, controls, and delegation dividers keyboard-navigable; busy/idle not color-only.

## 13. Implementation slices and exit gates

Estimates are deliberately **not committed** until the §16 spike completes; ordering is fixed.

- **Slice 0 — Contract freeze.** Delegation record and `DelegationExecutionContext` schemas (no task body—§10; provenance and constraints only), tenant-bound request hash, signed `agent_path` with sealed live-parent binding, dedicated operator approval, three-key claim and durable-enqueue contract, pre-action expiry/turn/cost/owner-revision CAS contract, invoke_agent parameters, one-shot cancel/steer and leased pause envelopes, default-off flags, and executable adversarial fixtures. Archive prerequisites: SQLite-only consent, an in-transaction consent check, and limits on new saves. The proposed legacy-consent reset and automatic retention pruning remain pending authorization. Gate: all declared fixtures execute; validators reject malformed evidence; crate-private reference classifiers reject conflicting replay and classify authority changes as requiring stale-pause release. Actual storage adapters and release effects ship in Slices 2 and 4. Full closure also requires §16 evidence and resolution of the archive privacy decision.
- **Slice 1 — Live Activity panel.** Observer → timeline rendering; readability prototype gate (council buyer concern: must not feel like NDJSON). Gate: §5 latency outcome on two different harness agents (Claude + one other); fresh-identity archive posture and bounded-history UX verified.
- **Slice 2 — Structured controls.** Cancel/steer as acknowledged one-shot commands; pause/resume as a leased queue hold over the encrypted control plane. Gate: §5 outcomes; non-operator identity refused; pause lease expiry releases the hold and is audited; pause state survives restart.
- **Slice 3 — Routines via workflow engine.** invoke_agent + schedule triggers + chat-mediated creation (agent drafts inert, operator signs and enables) + panel. Gate: fire→result→post end to end; restart duplicate-suppression demonstrated by injection; a drafted-but-unsigned routine never fires.
- **Slice 4 — Delegation.** Same-owner contract, operator approval, `DelegationExecutionContext` threading and fail-closed behavior, collapsed summary + relayed answer, failure notices. Gate: §8.4 end to end; cross-owner dispatch refused; unsigned and replayed approvals refused; hop/turn refusal proven; a call stripped of its context is refused; enumeration probe returns identical refusals.
- **Slice 5 — Close-out.** Flags audit, metrics, docs, rollback rehearsal. Gate: all flags off = existing wire contracts and smoke behavior unchanged; promotion checklist clean.

The contract fixtures above exercise reference decisions. Slices 2 and 4 must prove actual durable claims, crash recovery, and atomic release/audit through their storage adapters. The archive legacy reset and automatic pruning are pending explicit operator authorization; the current implementation instead refuses new saves at capacity and preserves existing records. Slice 0 is not fully closed while these privacy decisions and §16 evidence remain pending.

## 14. Acceptance criteria

- Live Activity readable and ≤ 2 s on at least two harnesses; stale states explicit.
- Controls effective and audited; cancel/steer acknowledged one-shot (replayed `command_id` rejected), pause leased and restart-durable; no ACP stream corruption (asserted by harness session continuity tests).
- Pause holds new work and resume releases it; an expired pause lease releases the hold and emits its own audit event.
- Routine fired from a chat-created schedule; results posted; no duplicate after induced crash; 10-strike auto-pause demonstrable; an agent-drafted routine cannot fire before the operator signs it.
- Delegation end to end between same-owner agents; operator approval binds the tenant-scoped immutable request hash, sealed live-parent `agent_path`, and expiry; cross-owner/tenant, unsigned, expired/post-expiry, conflicting three-key replay, cyclic, stale/stripped lineage, context-free, and unbounded-cost dispatches fail closed; exact retries collapse only against durable pending/completed work; exact-claim pre-action expiry/turn/cost CAS and the target's ordinary approval gates remain effective.
- Seeded-secret display test: redaction layer active in UI; no raw activity persisted on relay, and no delegation task body in relay metadata (relay store scan).
- Fresh-identity archive posture matches §6.3 (no archiving before an operator choice).
- Flags off: existing smoke evidence passes unchanged.

## 15. Rollout and rollback

- Flag enable order: Live Activity → controls → routines → delegation. Rollback: reverse order; persisted metadata (delegation records, routine specs, audit events) remains readable; nothing auto-deleted.

## 16. Risks and the 48-hour spike

**Riskiest assumption**: that observer streaming + structured controls deliver enough of the "watch and steer the bot" experience without a literal terminal.

**Spike (before Slice 1 estimate commitments)** — five tests, each freezing one contract that would otherwise be discovered wrong in Slice 2 or Slice 4:

1. Render the existing transcript/activity data in the proposed UX; measure latency and readability.
2. Send a real operator message during an active turn; record native-steer versus cancel-and-merge behavior across two harnesses.
3. Prototype queue-level Pause with expiry and crash recovery (§6.6).
4. Trace one operator-approved, same-owner delegated run through `DelegationExecutionContext`; prove cross-owner, unsigned, expired, replayed, and context-stripped variants fail closed while the target's ordinary approval gate still applies.
5. Verify a fresh identity does not archive activity without the decided consent posture (§6.3).

**Exit rule**: these five pass with frozen schemas and failure fixtures.

**Moved out of the gating path — Phase-2 discovery, not Phase-1 gating**: probing PTY ownership (`terminal_runtime`) to see whether an ACP harness can run inside an owned PTY without corrupting protocol/permission traffic. This was already declared evidence-only with no product dependency, and it gates Phase-2 scope rather than any Slice-0 contract, so it does not belong in a 48-hour window that must also freeze contracts. Run it separately. Its decision rule is unchanged: if it corrupts ACP traffic or yields only NDJSON, raw terminal takeover is removed from any Phase-2 plan; if it succeeds across Claude, Codex, and Kimi, a terminal-view proposal may be drafted as a separate PRD.

## 17. Open questions and decision deadlines

All six original v0.2 design questions are **decided** (2026-09-03). They remain listed with their resolutions so the rationale is not lost. The subsequent archive cleanup and legacy-consent reset still require explicit authorization; existing history and subscriptions remain preserved until then.

| Question | Decision |
|---|---|
| Steer semantics: inject as new user message vs. queued interrupt? | **Both, layered.** A durable new operator message is the intent; the queued/native interrupt is a delivery optimization. Reuse the existing capability-aware path (native steer → `_session/steering` → cancel-and-merge). If the agent is idle, the message starts a turn normally. Not a binary choice — this is already implemented in `crates/buzz-acp/src/pool.rs`. |
| Routine creation: agent-drafted-then-approve vs. operator-only form? | **Agent drafts an inert routine**; the operator reviews, edits, signs, and enables it. The form remains an alternate editor. Drafting grants no authority. |
| Local archive: ship Slice 1 or defer until requested? | **Use the existing archive**, with fresh/recovered identities off and SQLite as the sole consent authority. Existing history and subscriptions remain. The proposed legacy reset and automatic pruning need explicit operator approval before the full privacy prerequisite can close (§6.3). |
| Delegation hop budget default (1 vs. 2) and cost-cap units? | **Hop default 1, hard maximum 2** initially. `max_turns` is the universally enforceable limit; optional integer `cost_cap_microusd`. A capped action requires an enforceable conservative micro-USD reservation; unknown bounds refuse (FR-4). |
| Roster busy indicator: all agents or pilot subset (Stan/Dick personas first)? | **All locally managed agents.** Pilot rollout may be feature-flagged, but data semantics must not depend on specific personas. |
| Does the relay already expose owner-scoped ephemeral subscribe suitable for Live Activity, or is a handler extension needed? | **Suitable; no handler extension expected.** Kind 24200 already carries encrypted agent→owner telemetry with owner-gated publication, cleartext `p`-tag subscription gating, signature verification, a freshness window, and rate limiting (`crates/buzz-relay/src/handlers/event.rs`, `handle_agent_observer_event`). Confirm end-to-end in Slice 0. |

**Delegation authority decision (closed in v0.2b; wire contract hardened in v0.2d):** Buzz has no grants subsystem, so the initial release does not transfer or intersect authority. Delegation is same-owner and operator-approved; the target runs under its existing authority and approval gates. `DelegationExecutionContext` carries provenance and constraints only. Kind `43007` binds operator approval to the tenant-scoped immutable request, including expiry; nested ancestry is accepted only through a sealed token from the durable live-run permit. Replay safety comes from scoped three-key atomic claims plus durable enqueue, not the schema; action consumption rechecks exact claim identity/expiry, and hard cost caps require pre-dispatch reservations. Autonomous agent-to-agent authority transfer is deferred to a separate grants-model PRD.

## 18. First 48-hour proof

1. Contract implementation: AO has 55 executable fixture cases and DG has 40, including cross-owner, invalid-approval, revision-only ABA, and pre-outbox authority checks. The store-outcome classifiers are crate-private reference models; durable adapters, tombstone persistence, and atomic release/audit still require runtime evidence in Slices 2 and 4.
2. Live proof remains pending: the five tests in §16 have not been executed with recorded relay/harness evidence. Passing schema fixtures and mocked desktop tests does not close this gate.
3. Slice 1 estimates remain uncommitted until that live proof passes. The Phase-2 terminal go/no-go stays with its separate PTY probe (§16).

# PRD-TCLAW-COLLABORATION-SUBSTRATE-001

Status: Draft for Gate 1 review
Version: 0.1
Date: 2026-08-06
Owner: TORQCLAW product and engineering
Target: Windows-first self-hosted TORQCLAW deployment; portable architecture
Implementation repository: `E:\TorqClaw`

## 1. Executive decision

Build a bounded collaboration substrate inside TORQCLAW so a human operator and governed agents can work in shared channels where messages, task execution, approvals, results, Git references, and receipts appear in one searchable timeline.

The implementation extends TORQCLAW's existing gateway, SQLite event persistence, session bus, receipts, approvals, and `role: channel` adapter. It does not embed the Buzz relay, introduce a second execution engine, or replace Hermes, LOCAL_EDGE, the MCP bridge, or current governance.

The first release ships in four independently gated slices:

1. Principal identity and revocation.
2. Channels, membership, threads, and durable replay.
3. Agent task bridging, approval-safe timeline projection, and search.
4. Git reference ingestion and optional tamper-evident channel audit chains.

Principal identity is first because TORQCLAW's current connection `role` is an authorization class, not a durable person or agent identity. Shared-channel ACLs are not credible until every read, write, subscription, and task submission is attributable to a revocable principal.

## 2. Problem

TORQCLAW is a governed execution control plane with durable sessions, task events, receipts, cost controls, and approval-gated tools. It is currently session-centric: one console or channel adapter resumes one session and sees that session's task stream. It does not yet provide a shared workspace where multiple humans and agents can participate in a channel, reply in threads, search prior collaboration, or see the complete evidence for why a task or code change exists.

Teams therefore have to split context across TORQCLAW, chat, Git, issue trackers, and CI surfaces. The execution record is strong, but the collaboration record is fragmented.

Buzz demonstrates the product value of putting humans, agents, messages, Git events, workflow actions, and evidence in one room and one search surface. TORQCLAW should adopt that collaboration model while retaining its stronger execution controls: privacy-first routing, budget enforcement, gateway-owned grants, approval before write, scoped MCP tools, and evidence-backed receipts.

## 3. Target user and jobs

### 3.1 Primary user

A self-hosting technical operator or small engineering team that uses TORQCLAW to run local and cloud agents against code, research, and operations tasks.

### 3.2 Jobs to be done

- Create a project channel and add selected human and agent principals.
- Ask an agent to investigate or implement work inside that channel.
- See routing, tool calls, approval pauses, decisions, terminal results, and receipts without leaving the channel.
- Reply to a specific message or task in a durable thread.
- Search messages, task summaries, receipt facts, and Git references with clear provenance.
- Revoke an agent or credential and stop all subsequent channel reads, writes, subscriptions, and task submissions.
- Reconnect after a client interruption and resume from a monotonic cursor without missed or duplicated channel events.

## 4. Measurable outcomes

The release is successful when all of the following are demonstrated in TORQCLAW's own test harness:

- One operator and two distinct agent principals can collaborate in one private channel while a non-member principal cannot infer that the channel exists.
- A channel mention can create exactly one governed TORQCLAW task, link that task to the originating event, and project its terminal result and receipt back into the same thread.
- A write-capable tool still pauses on the existing operator-only approval path; neither an agent nor a `role: channel` client can approve it.
- Revoking a principal prevents its next read, write, subscription, resume, and task submission without waiting for process restart.
- Reconnect replay produces an ordered, duplicate-free suffix using a monotonic channel cursor.
- Search over 100,000 synthetic channel events returns the first page within 150 ms p95 on the reference Windows development machine, measured after warm-up and reported with machine specifications.
- Timeline retrieval of 100 events returns within 100 ms p95 on the same reference machine.
- Existing TORQCLAW feature-off behavior and accepted Phase 1 tests remain unchanged.

These are test targets, not current benchmark claims.

## 5. Product principles and invariants

1. The TORQCLAW gateway remains the only execution and authorization authority.
2. A connection role is not an identity. Every collaboration action binds to a persisted principal.
3. The existing `events`, `tasks`, `tool_approvals`, and `run_receipts` records remain execution truth. Collaboration rows link to them; they do not duplicate or override them.
4. Channel membership is checked before existence is disclosed, before backlog reads, before live subscription registration, before writes, and before task creation.
5. Revocation is evaluated on every privileged operation and active subscriptions are terminated or filtered immediately after revocation.
6. Clients cannot inject principal identity, membership, grants, receipt facts, task state, or approval state.
7. Only a live operator principal may decide a tool approval. Replayed timeline rows and historical approval rows are inert.
8. Privacy, execution mode, budget, MCP capability, path scope, and approval rules pass unchanged into channel-originated tasks.
9. A message-to-task bridge is idempotent. Reconnect, retry, and duplicate delivery cannot create a second task for the same accepted request.
10. Search results carry channel, actor, event kind, timestamp, and source-task provenance. Summaries are labeled as summaries.
11. Feature-off operation performs no collaboration migrations beyond additive tables that old code safely ignores and does not change existing session semantics.
12. No Phase 2 governed-learning or Phase 3 verified-skill capability is assumed or activated by this product.

## 6. Scope

### 6.1 In scope

- Persisted principals for operator, managed agent, and external channel-adapter identities.
- Revocable, hashed principal credentials with rotation support.
- Private channels, channel metadata, archive state, and explicit membership.
- Channel roles: `owner`, `moderator`, `member`, and `agent`.
- Text messages, thread replies, mentions, lightweight reactions, and system evidence events.
- Durable channel sequence cursors and live WebSocket subscription.
- Linking channel events to TORQCLAW tasks, approvals, terminal results, and receipts.
- Operator UI for channel list, timeline, thread view, member management, task evidence, and search.
- Session-safe agent dispatch through the existing gateway and execution pipeline.
- FTS5 search over bounded collaboration fields.
- Git provider references for repository, branch, commit, pull request, issue, status, and diff metadata.
- Optional per-channel tamper-evident hash chain, clearly described as tamper evidence rather than non-repudiation.
- Additive migrations, feature flags, observability, backup, rollback, and repair tooling.

### 6.2 Non-goals

- Nostr protocol compatibility, relay federation, web-of-trust reputation, or portable Nostr identities.
- Multi-tenant hosted communities selected by domain.
- Direct import or vendoring of Buzz source code.
- Buzz YAML workflows or its current workflow approval implementation.
- DMs, voice huddles, canvases, media hosting, mobile clients, push notifications, or culture features.
- Git hosting, Git credential helpers, or replacing GitHub/GitLab.
- New shell, file-edit, or host-wide developer tools.
- Automatic workflow approval, agent self-approval, or approval through a headless adapter.
- Learned-skill activation, remote skill registry, provider failover redesign, or execution-profile redesign.
- Cryptographic actor signatures or claims of non-repudiation in v1.

## 7. User flows

### 7.1 Create a governed project channel

1. An authenticated operator creates a private channel.
2. The gateway persists the channel and owner membership in one transaction.
3. The operator adds an existing managed-agent principal.
4. The gateway emits a membership event that contains no credential material.
5. Only members can list, open, search, or subscribe to the channel.

### 7.2 Ask an agent for work

1. A member posts a message mentioning an agent principal.
2. The gateway validates membership for both author and target agent.
3. A deterministic bridge key is derived from channel event ID, target agent ID, and requested action version.
4. The bridge creates one standard TORQCLAW task using the existing routing, privacy, budget, memory, tool, and approval paths.
5. The channel records an inert `task_linked` event with the task ID and origin event ID.
6. Execution events remain in the existing execution log. A collaboration projector emits bounded `task_status`, `approval_required`, `task_result`, and `receipt_available` references into the thread.
7. The result is authored by the agent principal but built from the recorded terminal result; the client cannot supply it.

### 7.3 Handle a tool approval

1. Execution reaches an existing `PENDING_APPROVAL` terminal event.
2. The collaboration timeline displays an inert approval-required card linked to the authoritative approval ID and task.
3. Agent and channel principals cannot call `APPROVE_TOOL`.
4. A live operator uses the existing approval action in the console.
5. The gateway reads tool name and arguments from its own approval record and re-mints the task using the existing one-shot grant path.
6. The collaboration projector updates the thread with the observed decision and subsequent terminal result.

### 7.4 Revoke an agent

1. An operator revokes the agent principal or one credential.
2. The gateway marks the principal or credential revoked in a committed transaction.
3. Active channel subscriptions for the principal are cancelled or stop receiving events before the revocation command returns success.
4. Subsequent resume, list, read, search, write, mention handling, and task creation fail with a generic authorization response.
5. Historical events remain attributed to the revoked principal and are never rewritten.

### 7.5 Search project history

1. A member searches within one or more channels they can access.
2. The server resolves accessible channel IDs before constructing the FTS query.
3. Search returns bounded snippets and provenance, never raw hidden-channel matches or existence counts.
4. Selecting a result opens the exact event or thread and can link to an authoritative task receipt.

## 8. Functional requirements

### FR-1: Principal identity and credentials

- Add a persisted principal ID distinct from `role` and `sessionId`.
- Principal kinds are `human`, `agent`, and `adapter`.
- Principal state is `active`, `suspended`, or `revoked`.
- Credentials are random bearer secrets stored only as a salted password-grade hash or keyed hash; plaintext is shown once at creation and never persisted or logged.
- Credential rows support creation, rotation, expiry, and revocation.
- The existing bootstrap gateway token may create or authenticate the initial operator only in explicit migration mode. It must not silently represent every future operator.
- `ConnectFrame` v2 binds role, principal ID, credential proof, client information, and optional session ID.
- Resuming a session requires the same principal ID and persisted role. A mismatch fails closed and does not create a fallback session.
- Principal status and credential status are checked on every command, backlog read, subscription, and task-dispatch boundary.
- A managed agent has an optional owner principal. Owner suspension or revocation suspends the agent's execution and channel access until explicitly restored by an operator.

### FR-2: Channels and membership

- Operators can create, rename, archive, unarchive, and describe channels.
- Channels are private-by-membership in v1. There is no implicit global channel.
- Channel creation and owner membership are atomic.
- Membership changes require `owner` or `moderator` authority; only an owner can grant or remove owner status.
- Removing the final owner is rejected.
- Membership reads do not expose non-member principals beyond display information already visible in the channel.
- Archived channels are read-only except for owner unarchive and administrative export.
- Every channel operation is scoped by server-resolved principal and channel IDs; client-provided labels never authorize access.

### FR-3: Messages, threads, mentions, and reactions

- Message bodies are UTF-8 text, 1 to 32,000 characters.
- Thread replies reference one root event and an optional direct parent; both must belong to the same channel.
- Mention targets must be current channel members.
- Editing creates a new immutable edit event referencing the prior event. Deletion creates a tombstone; source rows are retained for audit and excluded from normal rendering/search.
- Reactions are idempotent per actor, target event, and reaction value.
- Client idempotency keys are scoped to principal and channel and expire only after the server's documented retention window.
- Event payloads are validated with strict Zod schemas and generated JSON Schema where they cross the Python boundary.

### FR-4: Durable replay and subscriptions

- Collaboration events use a monotonic SQLite sequence cursor; timestamps are display metadata only.
- Backlog authorization completes before subscription registration.
- Live fan-out filters by current membership at delivery time, not only subscription time.
- A revoked or removed principal receives no later channel event even if its socket remains open.
- Reconnect accepts a last-seen cursor and returns an ordered suffix with no duplicate event IDs.
- Backlog pages have explicit event-count and byte caps with cursor continuation.
- Slow consumers are disconnected after a bounded queue policy and resume from their last acknowledged cursor.

### FR-5: Governed task bridge

- A message can request work from one managed-agent principal at a time in v1.
- The bridge creates a normal `GatewayRequest`; it cannot create internal grants or bypass `authorize`.
- Privacy, sensitivity, execution mode, budget, memory use, attachments, and source channel are copied from explicit operator/channel policy and validated server-side.
- Channel-level defaults can only become stricter than global policy without operator confirmation.
- The bridge persists its idempotency record before dispatch. A crash between acceptance and dispatch is recoverable without duplicate task creation.
- A task can be linked to one origin event and one channel thread; cross-posting uses separate reference events, not ownership changes.
- The collaboration projector reads existing task/event/approval/receipt truth and writes only collaboration references. It cannot mutate execution truth.
- Historical projections are inert and cannot dispatch, approve, cancel, or re-run work.

### FR-6: Search

- Index message text, operator-approved task summaries, terminal-result summaries, receipt labels, and Git reference metadata.
- Do not index raw tool arguments, raw tool results, assembled context, secrets, credentials, attachment contents, or safe-export omissions.
- Search queries are scoped to server-resolved accessible channel IDs before FTS execution.
- Search responses are capped by count, bytes, and snippet length.
- Deleted/tombstoned content disappears from the live index while its audit event remains.
- Search-index writes are transactional with source-event state or recoverable through a deterministic rebuild command.
- Rebuilds do not change source collaboration events.

### FR-7: Git references

- Support inbound normalized references from GitHub first: repository, branch, commit, pull request, issue, check/status, and bounded diff metadata.
- Verify webhook signatures before parsing or persistence.
- Map each configured repository to one channel through an operator-owned mapping.
- Delivery IDs are idempotency keys; duplicate deliveries cannot create duplicate events.
- Store reference metadata and provider URLs, not repository credentials or complete unbounded diffs.
- Git events do not trigger tools or tasks automatically in v1. An explicit operator or member message is required.
- A future provider adapter must conform to the same normalized contract and cannot widen channel membership.

### FR-8: Timeline integrity

- Collaboration source events are immutable after insert; edit and delete are new events.
- If tamper-evident chaining is enabled, each channel has a gateway-computed chain over canonical event bytes and the previous accepted hash.
- Chain head update and event insert occur in one transaction.
- Publish positive and negative canonicalization vectors before enabling the chain.
- The chain proves detectable modification or omission relative to a trusted head; it does not prove actor non-repudiation and must not be marketed as a signature.
- Provide a read-only audit command that verifies event IDs, sequence continuity, references, membership invariants, search projection consistency, and optional chain integrity.

### FR-9: Console experience

- Add channel navigation, unread cursor, member list, timeline, thread drawer, search, and Git reference cards to the existing Next.js console.
- Preserve route preview, current-task route chip, receipts, costs, safe export, and approval cards.
- Approval actions appear only on the live authoritative card for an operator principal.
- Every agent-authored result visibly identifies the agent, selected tier, terminal state, and receipt link when available.
- Stale or failed refreshes are shown explicitly. Cached content is never presented as freshly synchronized after authorization or network failure.
- Browser cache and query keys include gateway instance, principal ID, channel ID, and relevant cursor to prevent cross-principal or cross-instance reuse.
- Keyboard navigation, visible focus, semantic labels, and screen-reader announcements cover channel switching, new messages, pending approvals, and errors.

## 9. Proposed data contracts

Exact names may change during contract freeze, but equivalent constraints are mandatory.

### 9.1 Tables

```text
principals
  id UUID PK
  kind human|agent|adapter
  display_name
  owner_principal_id nullable FK principals
  status active|suspended|revoked
  created_at, updated_at, revoked_at

principal_credentials
  id UUID PK
  principal_id FK principals
  secret_hash
  expires_at nullable
  revoked_at nullable
  created_at, last_used_at

collab_channels
  id UUID PK
  name
  description
  state active|archived
  created_by_principal_id FK principals
  created_at, updated_at

collab_members
  channel_id FK collab_channels
  principal_id FK principals
  role owner|moderator|member|agent
  state active|removed
  joined_at, removed_at
  PRIMARY KEY(channel_id, principal_id)

collab_events
  seq INTEGER PRIMARY KEY AUTOINCREMENT
  id UUID UNIQUE
  channel_id FK collab_channels
  actor_principal_id FK principals
  kind message|edit|tombstone|reaction|membership|task_linked|task_status|approval_required|approval_decided|task_result|receipt_available|git_reference|system
  thread_root_id nullable
  parent_event_id nullable
  source_task_id nullable FK tasks(request_id)
  client_idempotency_key nullable
  content_json
  previous_hash nullable
  event_hash nullable
  created_at

collab_task_links
  origin_event_id
  agent_principal_id
  bridge_version
  task_id UNIQUE FK tasks(request_id)
  state accepted|dispatched|terminal|uncertain
  created_at, updated_at
  UNIQUE(origin_event_id, agent_principal_id, bridge_version)
```

An external-content FTS5 table indexes approved searchable projections from `collab_events`. Trigger-based or explicit transaction-based maintenance must include insert, update/tombstone, delete-rebuild, and corruption-repair tests.

### 9.2 Command families

- `CREATE_PRINCIPAL`, `ROTATE_PRINCIPAL_CREDENTIAL`, `SET_PRINCIPAL_STATUS`
- `CREATE_CHANNEL`, `UPDATE_CHANNEL`, `ARCHIVE_CHANNEL`
- `ADD_CHANNEL_MEMBER`, `UPDATE_CHANNEL_MEMBER`, `REMOVE_CHANNEL_MEMBER`
- `POST_CHANNEL_EVENT`, `EDIT_CHANNEL_MESSAGE`, `DELETE_CHANNEL_MESSAGE`, `REACT_CHANNEL_EVENT`
- `LIST_CHANNELS`, `GET_CHANNEL_TIMELINE`, `GET_THREAD`, `SEARCH_CHANNELS`
- `SUBSCRIBE_CHANNELS`, `ACK_CHANNEL_CURSOR`
- `REQUEST_AGENT_TASK`
- `CONFIGURE_GIT_CHANNEL`, `INGEST_GIT_EVENT`

Operator-only mutations, member mutations, and read actions must be enumerated in `authorize`; all unmapped actions remain denied for non-operator roles.

## 10. Security and privacy requirements

- Threat model includes stolen adapter tokens, revoked agents with open sockets, session-ID replay, role/principal mismatch, hidden-channel enumeration, forged membership, duplicate webhook delivery, forged Git webhook signatures, FTS query injection, unbounded payloads, stale browser caches, cross-channel references, replayed approval cards, and collaboration content containing prompt injection.
- Principal credentials never appear in collaboration events, execution events, receipts, logs, safe exports, metrics, or error strings.
- Generic not-found responses make absent and unauthorized channels/events indistinguishable to non-members.
- Agent ownership is persisted in authorization context and rechecked at each task and message boundary. Owner suspension/revocation affects already-connected agents.
- Prompt content from channels is untrusted data. System prompts delimit it and must not treat channel history, Git text, or search results as higher-authority instructions.
- Existing MCP path scopes and approval gates remain authoritative. This release adds no filesystem permission and no new execution bypass.
- In production mode, inbound Git webhooks require HTTPS termination, signature verification, payload limits, and replay protection.
- Safe export remains operator-only. Collaboration export is a separate future decision and is not implied by search or timeline access.
- Data retention defaults to local persistence until explicit operator deletion. Any retention automation requires a later PRD because audit, tombstone, receipt, and Git-reference lifetimes differ.

## 11. Non-functional requirements

### 11.1 Performance

- Timeline query: 100 events in 100 ms p95 on the documented reference machine.
- Search: first 50 results over 100,000 events in 150 ms p95 after warm-up.
- Message acceptance excluding network transit: 75 ms p95 without task dispatch.
- Live fan-out: 250 ms p95 from committed insert to delivery for 25 concurrent local clients.
- Benchmark reports include database size, WAL state, hardware, cold/warm distinction, and percentile method.

### 11.2 Capacity and limits

- Maximum message: 32,000 UTF-8 characters.
- Maximum collaboration event JSON after encoding: 64 KiB.
- Maximum page: 100 events and 512 KiB encoded response.
- Maximum initial release channel members: 100.
- Maximum active channel subscriptions per connection: 100.
- Larger limits require measured evidence and explicit configuration.

### 11.3 Reliability

- SQLite remains the single-node source of truth in v1 with WAL and foreign keys enabled.
- Every accepted mutation is transactional and idempotent.
- Projection failures never fabricate a successful task or mutate execution truth.
- Startup audit detects orphan task links, broken references, projection lag, invalid owner counts, and optional hash-chain failure.
- Backup and restore cover the database plus any encryption or key material required to authenticate principals.

### 11.4 Accessibility

- Meet WCAG 2.2 AA for new console controls.
- Channel, thread, unread, agent, terminal-state, and approval information cannot rely on color alone.
- New events and approval-required states use non-disruptive live-region announcements.

## 12. Analytics and observability

Collect bounded, local metrics without message bodies or credentials:

- Active channels and members by principal kind.
- Messages, threads, mentions, reactions, and Git references by day.
- Mention-to-task acceptance and completion rate.
- Duplicate bridge requests prevented.
- Approval-required, approved, rejected, and abandoned counts.
- Revocation enforcement counts by boundary.
- Replay pages, cursor lag, slow-consumer disconnects, and reconnect recovery.
- Search latency, result count, zero-result rate, and index-rebuild outcomes.
- Projection lag and repair counts.
- Unauthorized operation counts by action class, with bounded cardinality.

Metrics never include channel names, message bodies, prompts, tool arguments/results, Git diff text, tokens, principal display names, or event IDs as labels.

## 13. Implementation slices and exit gates

### Slice 0: Contract and threat-model freeze

- Freeze principal, membership, event, reference, idempotency, cursor, and authorization contracts.
- Publish state machines for principal lifecycle, membership lifecycle, message-to-task bridging, approval projection, and revocation.
- Add deterministic malicious fixtures for cross-channel references, principal/role mismatch, cursor tampering, duplicate delivery, forged webhook signatures, FTS syntax, oversized content, and prompt injection.
- Exit gate: strict schemas reject every malformed fixture; authorization matrix is complete and default-deny; no runtime wiring.

### Slice 1: Principal identity and revocation

- Add principal and credential tables, bootstrap migration, credential rotation, session binding, and live revocation enforcement.
- Do not enable channels until this slice passes.
- Exit gate: all identity acceptance criteria pass, including owner-ban propagation to an already-connected agent and role/principal resume mismatch.

### Slice 2: Channels, threads, and replay

- Add channel/member/event tables, commands, authorization, subscription registry, replay, console navigation, and timeline/thread UI.
- Keep agent task bridging off.
- Exit gate: membership isolation, ordered reconnect, slow-client recovery, edit/tombstone/reaction semantics, accessibility, and feature-off compatibility pass.

### Slice 3: Agent tasks, approvals, receipts, and search

- Add the idempotent task bridge, evidence projector, operator-only approval projection, FTS index, search UI, and repair command.
- Exit gate: mention-to-task flow completes end to end; duplicate delivery produces one task; approval cannot be decided from any historical or non-operator surface; search isolation and benchmark targets pass.

### Slice 4: Git references and optional audit chain

- Add GitHub webhook adapter, repository-channel mapping, normalized reference cards, delivery deduplication, and bounded metadata.
- Add the optional hash chain only after canonicalization vectors and repair behavior pass independent review.
- Exit gate: forged and replayed webhooks fail; duplicate deliveries are idempotent; hidden repository/channel mappings do not leak; chain audit catches every maintained tamper fixture when enabled.

## 14. Acceptance criteria

### Identity and authorization

- Given a valid credential for principal A, the gateway binds a new session to A and persists role and principal separately.
- Given principal A's session ID and principal B's credential, resume fails without creating a replacement session.
- Given a revoked credential, every connection and resume attempt fails.
- Given a revoked principal with an open socket, the next command, backlog read, and live delivery fail; active subscriptions are removed before revocation reports success.
- Given an agent whose owner becomes suspended or revoked, the agent cannot read, write, subscribe, resume, or create a task until an operator explicitly restores eligibility.

### Channel isolation

- A non-member cannot list, open, search, subscribe to, post to, or infer the existence of a private channel.
- A message cannot reference a thread root, parent, mention target, task, or Git mapping from another channel.
- Removing a member prevents subsequent delivery on its existing socket.
- Archiving a channel blocks new messages and tasks while preserving authorized reads.

### Replay and idempotency

- Reconnecting from cursor N returns each authorized event with sequence greater than N exactly once in ascending order.
- Replaying the same client idempotency key returns the original accepted event and creates no new row.
- Crashing after bridge acceptance but before dispatch recovers to exactly one linked task or an explicit terminal `uncertain` state; it never creates two tasks.
- Duplicate Git delivery IDs create one reference event.

### Governed execution

- A channel-originated task traverses the same classifier, router, budget, privacy, memory, MCP scope, approval, cancellation, and receipt paths as a console-originated task.
- A pending write tool creates an inert channel card and remains undecided until an authorized live operator uses the existing approval command.
- Agent, member, adapter, replay, receipt, search, and Git-event surfaces cannot approve or widen a grant.
- A collaboration projection failure cannot change task state or terminal execution output.

### Search and UI

- Search first resolves accessible channel IDs and returns no hidden-channel count, snippet, or timing-specific existence signal beyond ordinary bounded variance.
- Tombstoned message text is absent from normal search after the committed tombstone transaction or deterministic rebuild.
- Search results identify whether text is original, summarized, or projected evidence.
- Failed refresh and stale cache states are visible and do not present unauthorized or stale repository/channel content as current.
- New controls pass keyboard-only and screen-reader acceptance tests.

### Compatibility and operations

- With `TORQCLAW_COLLAB_ENABLED` off, existing commands, events, sessions, receipts, approvals, builds, and tests behave as before.
- Additive migration succeeds on a copy of the accepted Phase 1 database and backup restore returns byte-consistent source records.
- Audit and search rebuild commands modify only derived state.
- Rollback disables channel writes/subscriptions while preserving readable data and existing TORQCLAW execution history.

## 15. Rollout and rollback

- Feature flags independently gate identity-v2 acceptance, channel writes, task bridging, search, Git ingestion, and audit chaining.
- Developer rollout begins with synthetic principals and channels on a copied database.
- Operator pilot is local-only with one operator and one agent, no Git adapter, and no automatic task triggers beyond explicit mentions.
- Team pilot enables multiple principals only after revocation and hidden-channel tests pass.
- Git ingestion enables per repository after signature and deduplication tests.
- Audit chaining defaults off until canonicalization vectors and restoration procedures pass Gate 2.

Rollback order:

1. Disable new message-to-task bridges and Git ingestion.
2. Disable collaboration writes and live subscriptions.
3. Preserve channel data for read-only operator access and export/backup.
4. Revert clients to existing session-centric TORQCLAW behavior.
5. Never delete collaboration data automatically during rollback.

Promotion stops on any cross-channel disclosure, unauthorized approval, duplicate task dispatch, lost accepted event, revocation bypass, credential exposure, execution-policy widening, or failed restore.

## 16. Risks and mitigations

| Risk | Severity | Owner role | Mitigation |
|---|---:|---|---|
| Role is mistaken for actor identity | Critical | Security/engineering | Ship principals and credential binding before channels; reject resume mismatch |
| Removed or revoked member keeps receiving events | Critical | Security/engineering | Recheck current membership at delivery and cancel subscriptions transactionally |
| Channel path bypasses existing approvals | Critical | Security/engineering | Standard GatewayRequest only; operator-only existing approval command; adversarial matrix |
| Duplicate mention creates duplicate external work | Critical | Engineering | Durable bridge idempotency key before dispatch; crash-recovery state machine |
| Hidden-channel search or reference leak | High | Security | Resolve accessible channels first; generic responses; cross-channel FK/application guards |
| Collaboration becomes a second execution truth | High | Architecture | Reference existing tasks/events/receipts; projection is one-way and rebuildable |
| Prompt injection through history or Git text | High | Security/product | Treat all collaboration content as untrusted data; authority delimiters; no auto-triggered Git tasks |
| Shared token defeats attribution | Critical | Product/security | Per-principal credentials; shared token limited to explicit bootstrap migration |
| SQLite contention degrades execution | High | Engineering | Bounded transactions, WAL measurements, separate projection work, benchmark gates |
| Browser cache crosses principal or gateway | High | Frontend/security | Include gateway/principal/channel in all cache and persistence keys; clear on identity change |
| Audit chain is marketed as signatures | Medium | Product | Explicit tamper-evidence language; no non-repudiation claim |
| Scope expands into full Slack/GitHub replacement | High | Product | Enforce non-goals and four-slice release boundary |

Named accountable humans must be assigned before each slice starts.

## 17. Open questions and decision deadlines

| Question | Decision owner | Required by |
|---|---|---|
| Is v1 single-operator plus agents, or must it support multiple human operators? | Product/security | Before Slice 0 contract freeze |
| Which credential hashing and local secret-storage mechanism is approved on Windows? | Security/operations | Before Slice 1 implementation |
| Does owner suspension automatically suspend all owned agents, or only block execution while preserving read access? | Product/security | Before Slice 1 tests |
| Which channel fields may be included in episodic memory, and under what retention policy? | Product/privacy | Before Slice 3 implementation |
| Are task-result summaries deterministic templates or LLM-generated? | Product/engineering | Before Slice 3 contract freeze |
| Which GitHub event types and maximum diff metadata size are required for the pilot? | Product/engineering | Before Slice 4 |
| Is tamper-evident channel chaining required for v1 promotion or a post-v1 option? | Product/security | Before Slice 4 |

## 18. Support implications

- Extend `doctor` with principal credential health, invalid memberships, orphan task links, projection lag, FTS integrity, webhook configuration, and optional chain status without revealing secret values.
- Document principal creation, credential rotation/revocation, agent ownership, member removal, channel backup, search rebuild, Git webhook rotation, and rollback.
- Provide a local read-only audit report suitable for support without message bodies by default.
- Safe diagnostic export remains the supported artifact for execution receipts. A collaboration export requires a separate reviewed allowlist and is not part of this release.

## 19. Definition of done

- Every shipped slice satisfies its acceptance criteria and rubric sections.
- No unresolved critical or high Gate 1 or Gate 2 finding remains.
- Full existing TORQCLAW TypeScript, contract-drift, build, and Python gates pass.
- New authorization, revocation, idempotency, replay, search isolation, prompt-injection, cache-scoping, migration, restore, and rollback tests pass.
- Feature-off behavior is demonstrated against an accepted Phase 1 database copy.
- Performance targets are reproduced on a documented Windows reference machine.
- Security review confirms no new tool authority, approval path, credential disclosure, or hidden-channel oracle.
- Operator documentation and secret-free examples are complete.

## 20. Research basis and source boundaries

Research checked on 2026-08-06:

- TORQCLAW current local architecture and accepted Phase 1 status: `E:\TorqClaw\README.md`.
- TORQCLAW current gateway schema and source-of-truth tables: `E:\TorqClaw\packages\gateway\db\schema.sql`.
- Durable sessions, FTS context, and monotonic replay: `E:\TorqClaw\packages\gateway\src\sessions.ts` and `events.ts`.
- Current role authorization and operator-only approval/receipt policy: `E:\TorqClaw\packages\gateway\src\authz.ts`.
- Reusable external-channel bridge: `E:\TorqClaw\packages\channel-http\src\gatewayClient.ts`.
- Buzz's collaboration thesis and shipped/unfinished boundary: https://github.com/block/buzz/blob/main/README.md.
- Buzz's relay/event architecture: https://github.com/block/buzz/blob/main/ARCHITECTURE.md.

The following Buzz findings informed explicit safeguards but are not copied implementations:

- Browser Git caches must include tenant/relay identity and failed refreshes must not silently present stale content.
- Agent-owner bans must affect already-authenticated agent sessions.
- Workflow approval infrastructure must prove suspend/persist/decide/resume end to end before being advertised.
- Developer shell and file tools must remain workspace-scoped and approval-gated.
- Upload quotas and durable audit behavior are excluded because media is out of scope.

## 21. First 48-hour proof

Before building UI, implement a contract-only vertical test with an in-memory or temporary SQLite database:

1. Create operator A, agent B owned by A, outsider C, and private channel X.
2. Add A and B to X; prove C cannot distinguish X from an absent channel.
3. Persist a message and one idempotent task link under a synthetic task ID.
4. Subscribe B, revoke A, and prove B's next delivery and task request are blocked under the selected owner policy.
5. Reconnect A from a cursor and prove ordered suffix replay with no duplicate IDs.
6. Attempt approval from B and from a `role: channel` principal and prove both are denied by the production authorization function.

The riskiest assumption is that shared collaboration can be added without weakening TORQCLAW's session-scoped authorization and execution truth. The proof succeeds only if identity, membership, replay, task linking, and approval denial are enforced by shared production contracts rather than UI conventions or parallel test-only logic.

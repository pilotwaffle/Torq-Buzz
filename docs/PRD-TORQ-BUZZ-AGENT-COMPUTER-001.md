# PRD-TORQ-BUZZ-AGENT-COMPUTER-001

Status: Draft for operator review
Version: 0.1
Date: 2026-09-04
Owner: TORQ-BUZZ operator (sole human principal)
Target: Windows-first, self-hosted, single-operator deployment on the existing Torq-Buzz installation (`E:\TORQ-BUZZ`); architecture must not preclude a future always-on remote "computer" host
Implementation repositories: `E:\TORQ-BUZZ\source\buzz` (desktop), new `buzz-terminald` + `buzz-routines` services

## 1. Executive decision

Build the three Grokbot-style capabilities the operator demonstrated a want for — **per-agent terminals with a live screen view, scheduled routines, and agent-to-agent handoff** — directly into the working Buzz desktop app and its permanent relay. We do not adopt CopilotKit/OpenBot (or any other platform) as a base; we use it strictly as a verified MIT-licensed design reference.

The work ships as one bounded release in five independently gated slices (§13). The first three slices deliver the local experience. Slice 5 hardens the interfaces so a later milestone can move the agent runtime to an always-on server ("the computer") without a redesign, allowing agents to keep working while the operator's PC is off.

Two recorded decisions govern every requirement below:

- **D1: Local first, remote-ready.** All components run on the operator's Windows PC now. Every interface (event schema, daemon protocol, workspace layout) is specified so the same stack can run on a Linux server later, swapping only the terminal backend (ConPTY → tmux/posix-PTY). A `computer_id` field exists in every terminal/screen event from day one.
- **D2: Buzz's existing substrate is preserved.** The permanent Nostr relay remains the single source of truth; buzz-acp agents (Claude Code, Codex, Kimi Code) remain the execution engines; the desktop build, identity, and relay topology from HANDOFF.md are unchanged.

## 2. Problem

Today the operator's agents are black boxes connected through Buzz:

- When an agent works, the operator cannot see what it is doing without leaving Buzz and finding the agent's console window (the 2026-09-01 Grokbot recording shows the opposite: every agent has a live "screen" tile and can post screenshots into chat).
- Nothing can be scheduled. The operator must be present and typing for any agent to act (in the recording, the operator creates a 24-hour Apple-review watch routine by saying so in chat).
- The operator is the router between agents. If Stan should ask Dick, the operator must copy context manually (in the recording, agents message each other and the human sees collapsed "N messages with Dick" summaries).
- Closing the PC stops everything; there is no path to an always-on computer.

## 3. Research basis

Checked 2026-09-04:

- **Grokbot screen recording** (`C:\Users\asdasd\Downloads\Recording 2026-09-01 173502.mp4`, 5:18, frame-analyzed): persona roster with presence; per-agent live screen-share tiles and in-chat screenshot cards; "Routines" panel (cron entries, active/paused, created conversationally); collapsed agent-to-agent conversation dividers; voice input; proactive pings with external links.
- **x.ai Grok Bot docs** ([overview](https://docs.x.ai/grok-bot/overview)): one persistent cloud "computer" per user (browser, filesystem, terminal) shared by all Bots; **each Bot gets its own screen** on that computer; routines learned from demonstration; durable named agents.
- **CopilotKit/OpenBot** ([repo](https://github.com/CopilotKit/OpenBot), MIT, alpha v0.0.5): reference designs adopted as design evidence only — routines with conversational creation, 15-minute floor, 20-per-person cap, 10-strike fatigue auto-off ([docs/routines.md](https://raw.githubusercontent.com/CopilotKit/OpenBot/main/docs/routines.md)); bot-to-bot handoff with depth/fan-out caps and relay-back into the asking bot's voice ([docs/architecture.md](https://raw.githubusercontent.com/CopilotKit/OpenBot/main/docs/architecture.md)); live screen watching with audited take-the-wheel handoff; CEL-style fail-closed action policy and audit trail.
- **Torq-BUZZ current state** (`HANDOFF.md`, verified): permanent relay PID-bound at ws://127.0.0.1:3300 (loopback-only), health 8380, metrics 9302; buzz-acp agents connected in #agent-lab; desktop is a Tauri production build; UI automation toolkit in `evidence\ui-auto\`.

Explicitly rejected: adopting OpenBot as a base (17-day-old alpha; requires a vendor license token to boot; web/Docker/Postgres stack; AG-UI-only agents, no ACP — see research summary in session artifacts).

## 4. Target user and jobs

Single user: the operator, already running the installation above.

Jobs to be done:

- Open an agent in Buzz and watch its terminal live, in a right-panel "screen" tile, without leaving the app.
- Take control of an agent's terminal when it is stuck (login wall, wrong turn), then hand control back.
- Tell an agent "every 24 hours, check X and ping me" and have that become a real, visible, pausable scheduled job.
- Ask one agent to delegate to another and see the result as a collapsed summary plus a relayed answer, not raw agent-to-agent chatter.
- (Future, Slice 5+) Run the same stack on a server so agents keep working while the PC is off.

## 5. Measurable outcomes

- Operator opens any connected agent and sees its live terminal within 2 s; scrollback of at least the last 10,000 lines is available.
- A routine created by chat message fires on schedule and posts its result into the originating channel with an unread mark; the operator can pause it from the UI in one action.
- An agent-to-agent handoff produces exactly one collapsed summary line in the originating thread and one attributed relayed answer; depth and fan-out caps are enforced and audited.
- Terminal/screen events replay correctly after desktop restart from the relay cursor (no loss beyond documented retention).
- With the PC awake, end-to-end "create routine in chat → fires → result posted" is demonstrable within one hour of a fresh install.
- Feature-off behavior: with all new flags off, Buzz behaves exactly as today (existing smoke evidence still passes).

## 6. Product principles and invariants

1. The relay is the single source of truth. Terminal output, routine state, and handoff records are relay events/tagged data; daemons are rebuildable projections.
2. buzz-acp and the harness CLIs are untouched. Terminald attaches to agent processes; it never replaces ACP as the control plane.
3. Every terminal/screen event carries `computer_id`, `agent_pubkey`, `session_id`, and a monotonic sequence. No absolute host paths in any payload (workspace-rooted relative paths only).
4. Agent workspaces are plain directories, each an initialized git repo (leveraging the existing `git-credential-nostr` helper), so state is movable/clonable to a future server.
5. Take-the-wheel input forwarding is operator-only, gated by the human identity key, audited per session, and visibly bannered in the UI while active (mirroring the recording's RECORDING banner).
6. Terminal events never contain secrets: redaction patterns (env values, credential-manager reads, nsec-shaped strings) are filtered before publish. Fail-closed: redaction failure suppresses the frame and logs.
7. Routines and handoffs can never widen agent authority: a routine runs with exactly the grants of the creating principal; a handoff can only reach agents the asking agent's human could see.
8. All new features are independently flag-gated and default off.

## 7. Scope

### 7.1 In scope

- `buzz-terminald`: Windows service owning one ConPTY per agent; socket protocol (allocate/stream/snapshot/input); scrollback ring buffer; redaction filter.
- Terminal event schema on the permanent relay (new event kinds or tagged kinds agreed in Slice 0).
- Desktop UI: per-agent "screen" tile (xterm.js in the webview), busy indicators on the roster, takeover banner and input path, routine list panel with pause/resume, collapsed handoff dividers.
- `buzz-routines` daemon: cron-fired runner that injects a routine prompt into the target agent's session (via its terminal or ACP mention, decided in Slice 0) and posts results to the originating channel.
- Handoff relay: one agent mentions/asks another; summary + relayed-answer events; depth cap (default 1) and fan-out cap (default 3) per originating user turn.
- Audit events for takeover, routine create/pause/fire/fail, handoff offer/refuse/deliver.
- Feature flags, metrics, and Slice-5 remote-computer interface hardening.

### 7.2 Non-goals

- Voice input/output (absent in OpenBot too; low value per effort now).
- Mobile clients, push notifications beyond in-app unread marks.
- Cloud/server deployment in this release (interfaces must be ready; deployment is a later milestone).
- Multi-operator/team support, per-agent containers, sandboxing, CEL policy engine, third-party MCP catalogue.
- Replacing, wrapping, or forking buzz-acp/ACP; embedding OpenBot code wholesale.
- Teaching-by-demonstration routine capture (manual/conversational routine creation only).

## 8. User flows

### 8.1 Watch an agent work

1. Operator opens an agent conversation in Buzz.
2. The right panel shows the "screen" tile rendering that agent's live terminal stream (or "no active session").
3. Scrollback loads from relay events (then local ring buffer for live tail).
4. A busy indicator on the roster row shows which agents are actively producing output.

### 8.2 Take the wheel

1. Operator clicks "Take control" on the tile; terminald opens an audited takeover session.
2. Operator keystrokes forward to the agent's ConPTY; a banner records "operator control active".
3. Operator releases; the agent process resumes; a `control_released` audit event is written.

### 8.3 Create a routine in chat

1. Operator messages an agent: "every 24 hours, check the Apple review status and ping me here."
2. The agent (via a granted routine tool) proposes a routine spec (schedule, prompt, target channel); the operator confirms in one click.
3. The routine appears in the agent's Routines panel (Active). On schedule, buzz-routines injects the prompt; the result posts to the channel with an unread mark.
4. Failures: one failure message, then auto-pause after 10 consecutive failures.

### 8.4 Agent hands off to agent

1. Agent A's turn determines it needs Agent B; it emits a structured handoff (typed fields: target, task, constraints — not free text) instead of chatting blindly.
2. B runs in its own session; the originating thread shows one collapsed line: "A asked B for this on your behalf: <task>".
3. B's answer relays into the originating thread in A's voice, attributed to B.
4. Depth/fan-out caps enforced; refusals and failures produce a plain-language notice in-thread.

### 8.5 (Future) Move to a server computer

1. Operator provisions an always-on Linux host (VPS or home server) with Docker.
2. The same compose/services run there with the tmux backend; Buzz desktop adds the host as a second `computer_id`.
3. Agents moved to the server keep their workspaces (git clone via existing credential helper). PC becomes a pure client; closing it stops nothing on the server.

## 9. Functional requirements

### FR-1: buzz-terminald

- One ConPTY per connected agent; process death is detected within 5 s and published as a status event.
- Socket protocol (Unix-style on loopback; exact transport frozen in Slice 0): allocate, attach, stream, snapshot(scrollback window), send-input, resize, release.
- Scrollback ring buffer ≥ 10,000 lines per terminal, also published to relay with bounded retention.
- Redaction filter applied to every frame before socket/relay publish (§6.6); fail-closed.
- Backend abstraction: `PtyBackend` interface with `ConptyBackend` (Windows) implemented; `TmuxBackend` (Linux) specified but may be stubbed in this release.

### FR-2: Terminal event schema

- New event kind(s) on the permanent relay carrying: `computer_id`, `agent_pubkey`, `session_id`, `seq`, `frame_type` (output/status/frame/snapshot), redacted payload, byte cap per event.
- Replay from cursor yields ordered, duplicate-free frames (reuse existing relay cursor semantics).

### FR-3: Desktop UI

- Screen tile per agent conversation (xterm.js), with live attach, scrollback load, and explicit stale/disconnected states (never presenting frozen frames as live).
- Roster busy indicator driven by terminald status events.
- Takeover banner + input path per §8.2, visible only to the operator identity.
- Routines panel per agent: list, schedule text, Active/Paused toggle, last-run status.
- Collapsed handoff dividers in-thread, expandable to the summary detail.

### FR-4: buzz-routines

- Cron scheduler (5-field + timezone), 15-minute minimum interval, max 20 enabled routines per agent, per-agent cap.
- Fire = inject routine prompt into the owning agent's session; result posted to the originating channel as that agent's message with unread marking.
- Persistence: routine state on relay (rebuildable); daemon crash recovers without duplicate firings (idempotency key = routine_id + fire instant).
- 10 consecutive failures → auto-pause + one explanatory message.

### FR-5: Handoff relay

- Structured handoff record (target agent, task, constraints, expecting), not free-text agent chatter.
- Caps: `HANDOFF_MAX_DEPTH` default 1, `HANDOFF_MAX_PER_RUN` default 3; refuse, never truncate.
- Relayed answer attributed to the answering agent, voiced by the asking agent; failure notice after max attempts.
- Only agents visible to the operator may be handoff targets (refuse identical wording for invisible/nonexistent to prevent roster enumeration).

### FR-6: Audit and metrics

- Audit events: takeover open/release, routine create/update/pause/fire/fail, handoff offer/refuse/deliver/fail.
- Metrics: frames published/sec per agent, takeover minutes, routine fire latency and failure counts, handoff counts by outcome. No message bodies, prompts, or payloads in metrics.

### FR-7: Feature flags

- `BUZZ_TERMINALS`, `BUZZ_ROUTINES`, `BUZZ_HANDOFFS`, each default off; off = no new events, no schema changes beyond additive kinds, desktop unchanged.

## 10. Data contracts (proposed; frozen in Slice 0)

```text
terminal_sessions      (daemon-local, rebuildable)
  agent_pubkey, session_id, computer_id, started_at, ended_at, backend, state

routines               (relay-persisted, projected)
  id, agent_pubkey, channel_id, created_by, cron, timezone, prompt,
  state(active|paused), consecutive_failures, last_run_at, idempotency window

handoffs               (relay-persisted, projected)
  id, origin_event_id, from_agent, to_agent, task_json, depth, run_id,
  state(offered|refused|delivered|failed), answer_event_id nullable
```

Event payloads validated with strict schemas before publish (same discipline as existing Buzz kinds).

## 11. Security and privacy

- Terminal frames are broadcast only to the operator identity (loopback relay already enforces locality; confirm no remote relay read path exposes frames).
- Takeover input requires the human key signature; every session audited; agent process never executes operator input as its own reasoning (banner + event trail).
- Redaction patterns: `nsec1…`, env var assignments, Windows Credential Manager read patterns, key-shaped hex. Fail-closed.
- Routine prompts are untrusted content by design; harness system prompts already treat channel content as untrusted (existing Buzz invariant preserved).
- No secrets in daemon logs; daemon listens on loopback only.
- Threat model additions: operator-input injection into agent PTY (mitigated by banner/audit, operator is trusted), malicious routine prompt (agent treats as untrusted), handoff roster enumeration (identical refusal wording), relay replay of stale frames (session_id + seq).

## 12. Non-functional requirements

- Screen tile time-to-live-frame ≤ 2 s from PTY output; 30 fps rendering not required (terminal semantics, ~5 fps sufficient).
- Relay publish overhead: terminald must not starve relay throughput for chat events; bounded queue with drop-oldest for frame events only (never for audit/routine/handoff events).
- Desktop: screen tile memory ≤ 150 MB with 10k-line scrollback loaded.
- Routines: fire-to-agent-inject ≤ 60 s p95 on the reference machine; scheduler survives daemon restart (recovers due and overdue windows per documented policy: skip missed, never double-fire).
- Accessibility: tile, routines panel, and handoff dividers keyboard-navigable; busy/idle not color-only.

## 13. Implementation slices and exit gates

- **Slice 0 — Contract freeze (½ day).** Freeze event schemas, socket protocol, flags, handoff record, routine spec. Malicious fixtures: forged takeover, cross-agent frame injection, oversize frame, replayed session_id, routine double-fire. Gate: schemas reject every fixture; additive-only migrations.
- **Slice 1 — terminald + screen tile (1–2 days).** ConPTY backend, socket protocol, relay publish, xterm.js tile, roster busy indicator. Gate: watch-a-live-agent end to end; replay after restart; redaction proven with seeded secrets.
- **Slice 2 — Takeover (1 day).** Input path, banner, audit. Gate: audited take/release cycle; non-operator identity refused.
- **Slice 3 — Routines (1–2 days).** buzz-routines daemon, conversational create/confirm, panel, fire/post, fatigue auto-pause. Gate: §5 outcomes demonstrated, including crash-recovery no-double-fire.
- **Slice 4 — Handoffs (1–2 days).** Structured handoff, caps, collapsed dividers, relay-back, failure notices. Gate: §8.4 flow end to end; caps refuse correctly; enumeration probe returns identical refusals.
- **Slice 5 — Remote-computer hardening (½ day, interfaces only).** `TmuxBackend` spec'd (may be stub), `computer_id` threaded everywhere, workspace-as-git verified, no absolute paths audit. Gate: codebase scan clean; a documented dry-run plan for a Linux host exists. No server is provisioned in this release.

## 14. Acceptance criteria

- Operator can watch any connected agent's live terminal from Buzz within 2 s of opening its conversation.
- Takeover works end to end and is audited; releasing restores normal agent operation.
- A routine created from a chat message fires on schedule, posts results, and can be paused in one action; 10-failure auto-pause demonstrated by injection.
- A handoff between two live agents produces exactly one collapsed line plus one attributed relayed answer; depth/fan-off caps demonstrably refuse.
- Seeded-secret redaction test: no secret pattern appears in any relay event, log, or frame.
- All flags off: existing Buzz behavior byte-identical on existing smoke checks.
- Restart resilience: desktop and daemons restart mid-session; replay from cursor is ordered and duplicate-free.

## 15. Rollout and rollback

- Flags per §FR-7; enable order: terminals → routines → handoffs.
- Rollback: disable flags in reverse order; all new data remains readable; daemons stop publishing; no data deletion.
- Promotion stops on: any secret leak in frames, takeover by non-operator, duplicate routine firing, handoff cap bypass, or relay instability attributable to terminald.

## 16. Risks and mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Secret leakage through terminal frames | Critical | Fail-closed redaction; seeded-secret test gate in Slice 1 |
| Terminald starves relay / desktop perf | High | Bounded queues, drop-oldest only for frames, measured in Slice 1 |
| Operator input corrupts agent session | Medium | Banner + audit; session is rebuildable; harness resume exists |
| Scope creep into OpenBot-style platform | High | §7.2 non-goals enforced; slices are independently shippable |
| ConPTY Windows quirks (resize, dead conhosts) | Medium | Detect-and-restart ConPTY; documented fallback: transcript view (Option C from brainstorm) |
| Remote-computer assumption baked wrong | Medium | D1 invariants; Slice 5 gate scan for absolute paths/computer_id |
| Routines hammer agents/agents loop | Medium | 15-min floor, 20 cap, fatigue auto-off, depth caps |

## 17. Open questions and decision deadlines

| Question | Owner | Required by |
|---|---|---|
| Terminal events: new relay kinds vs. parameterized existing kinds? | Operator + implementer | Slice 0 |
| Routine fire: inject via agent's PTY vs. ACP mention? | Operator | Slice 0 |
| Socket transport for terminald (named pipe vs. WS loopback vs. gRPC local)? | Implementer | Slice 0 |
| Frame retention window on relay (disk budget)? | Operator | Slice 1 |
| Which agents get terminals in pilot (all 3 connected, or Stan/Dick personas first)? | Operator | Slice 1 |
| xterm.js bundle in Tauri webview vs. native canvas? | Implementer | Slice 1 |

## 18. First 48-hour proof (before UI polish)

1. terminald attached to one live buzz-acp agent; frames visible on relay; seeded-secret redaction verified.
2. Minimal tile (web or desktop) renders the live stream.
3. One routine created by config fires once and posts to #agent-lab.
4. Flags off → nothing changes.

# TORQ BUZZ — OPERATOR HANDOFF (2026-08-04 ~11 PM local)

## System state (all verified)

| Component | State |
|---|---|
| Permanent relay | PID 27896, ws://127.0.0.1:3300, health 8380, metrics 9302, loopback-only, receipt `state\relay-process.json` |
| Pilot relay | PID 36020, port 3000 (do not stop unless separately authorized) |
| Docker | torq-buzz postgres/redis healthy, minio up; pilot buzz-* stack up (keycloak unhealthy = pre-existing) |
| Desktop | `E:\TORQ-BUZZ\app\buzz-desktop.exe` (production build, hash 2F18E8F1…78AE), PID 10912 |
| Human identity | Windows Credential Manager `secrets.buzz-desktop`; pubkey `2842f8e2b0f54a8de9e0b8b44da9127a6bc321f14897da5c0e3393c49c1bc1b8` (config\permanent-human.pubkey.txt) |
| Dev keyring residue | `secrets.buzz-desktop-dev` — operator-confirmed pilot residue, retained, never read |
| Git protection | `E:\TORQ-BUZZ\.gitignore` shields secrets/state/logs/evidence/data from the E:\ PulseX repo |

## Agents (all in #agent-lab, UUID 41ecf159-a5d4-479d-a100-2dd91dd29ffd)

| Agent | Pubkey | Harness / Model | buzz-acp PID | Status |
|---|---|---|---|---|
| torq-architect-claude | b973136845c8d2abe4dcdd7e556e5358861d242a6e2fdc54e46deaa5336f96cf | Claude Code / sonnet (Sonnet 5) | 44396 | PONG PASS 3:53 PM |
| torq-builder-codex | be1fb113e9416249f36ad735e1996311908c8a1b2b54e99916f0b04072118a7b | Codex / gpt-5.4 (GPT-5 Codex) | 53172 | PONG PASS 4:12 PM |
| torq-research-kimi | 707d8bd3c02ae0dc9887f9df89fb5a636d1691d5fcd0d9de04bcf9140bf2f27c | Kimi Code / kimi-code/k3 | 43668 | Answered "hello" 5:32 PM; formal PONG mention sent ~10:50 PM, reply confirmation pending |

Logs: `%APPDATA%\xyz.block.buzz.app\agents\logs\<pubkey>__….log`
Records: `%APPDATA%\xyz.block.buzz.app\agents\managed-agents.json` (template+instance record pairs are NORMAL — don't "clean" the empty-pubkey templates).

## Pending items

1. **Kimi PONG confirmation** — mention sent; verify reply in #agent-lab (UIA Text search "PONG", or check thread on the mention).
2. **Kimi avatar** — currently vendor default. To set `C:\Users\asdasd\Downloads\kimi code.png`: open agent → Edit → "Edit avatar" (opens persona dialog) → avatar picker → upload → Save. No CLI path exists (persona-level only).
3. **Remaining harnesses** (NOT started): Qwen (qwen3.8-max-preview), DeepSeek+GLM via separate qwen --acp configs, Gemini CLI, Grok (grok agent stdio), ZCode (outside Buzz until ACP bridge proven). Same isolation rules: own identity/process/config; never capture the post-create nsec screen.
4. **Agent hardening (recommended):** enable BUZZ_ACP_HEARTBEAT_INTERVAL=300-600 for self-healing; consider scheduled buzz-acp restarts.

## Critical operational knowledge

- **Stale key fix (done):** invalid global `ANTHROPIC_API_KEY` (401-verified) was REMOVED from `agents\global-agent-config.json`; Claude agents now use Claude Max OAuth. Redacted backup in evidence. Do NOT re-add global provider keys — keep credentials per-agent/per-CLI.
- **Agent deafness (~3h):** poisoned-turn retry cycle (10 × ~900s idle timeout) looks like total silence at info log level. Fix = restart agent (Actions menu → Start). Root-cause doc: subagent output in session; see `requeueing failed batch` warns.
- **Desktop build:** production build = `cd E:\TORQ-BUZZ\source\buzz\desktop && pnpm tauri build --no-bundle` (use pilot's pinned node/corepack pnpm 11.4.0). BARE `cargo build` produces a dev-cfg binary that needs a Vite server (localhost:1420) — the Aug 3 "won't open" bug.
- **UI automation toolkit:** `E:\TORQ-BUZZ\evidence\ui-auto\*.ps1` — uia-invoke/uia-select/uia-edits/uia-click-el (DPI-aware physical clicks), real-click.ps1 (MinimizeAll+calibrated click, ÷1.48), uia-send-message.ps1 (composer). Mentions need the autocomplete chip: type @name, {ENTER}, then text, then invoke "Send message". Replies land in THREADS — read via UIA text search, not the flat list.
- **DPI:** screen is 2400x1600 physical @150%. Set SetProcessDpiAwareness(2) before coordinates/captures.
- **Sidecars:** all 5 real binaries staged in `E:\TORQ-BUZZ\app\` (buzz-acp, buzz-agent, buzz-dev-mcp, git-credential-nostr, buzz) + `E:\TORQ-BUZZ\bin\`.
- **Buzz window quirks:** minimizes/off-screens often; restore with ShowWindow(9)+SetWindowPos 0,0,1600,1040 (restore-hard.ps1).

## Evidence roots

- `E:\TORQ-BUZZ\evidence\ui-auto\` — agent setup automation + screenshots
- `E:\TORQ-BUZZ\evidence\acp-smoke\` — adapter handshake proofs
- `E:\TORQ-BUZZ\evidence\c2\`, `c2-prereq-desktop\`, `c5\` — identity/relay phases
- Secret scans to date: CLEAN (counts-only). One nsec screenshot was created and immediately deleted during claude setup.

## Blocked phases (need explicit operator GO)

C3 signing, C4 publish, live COPY_SELECTED_MESSAGE migration, C6 pilot retirement, C7 Gate 1 claim, model-council work beyond the 3 connected agents.

## Submodule fork and backup (2026-09-05)

- `source/buzz` submodule URL is now `https://github.com/pilotwaffle/buzz.git` (fork of `block/buzz`), branch `torq/slice0-2026-09-05`, base `6e5c462a` (upstream `relay-v0.2.1`).
- Existing checkouts (e.g. Maginot) must run `git submodule sync -- source/buzz && git submodule update --init source/buzz` to pick this up.
- The previous shallow checkout is preserved, git-readable, at `source/buzz.pre-push-2026-09-05` — its git dir lives under `E:\TORQ-CONSOLE\tmp\buzz-pilot\20260731-004310\source\buzz\.git` (main worktree = that temp checkout).
- Rollback (restores the pre-push shallow checkout at its original path; run from `E:\torq-buzz`):
  1. `mv source/buzz tmp/buzz-fork-checkout.moved-aside` — moves the fork checkout out of the way (its git dir stays at `.git/modules/source/buzz`; do NOT run git inside the moved-aside directory: its `core.worktree` is relative and would resolve to whatever occupies `source/buzz`).
  2. `mv source/buzz.pre-push-2026-09-05 source/buzz` — the backup's `.git` gitfile and the TORQ-CONSOLE admin `gitdir` both use this absolute path, so git access is fully restored.
  3. To undo the rollback: reverse the two moves in the opposite order.
  Do not delete either directory without operator sign-off.
- The TORQ-CONSOLE git dir (`E:\TORQ-CONSOLE\tmp\buzz-pilot\20260731-004310\source\buzz\.git`) still lists `E:/TORQ-BUZZ/source/buzz` as a LIVE linked worktree at `6e5c462a`. That path is now occupied by the fork checkout, so two git dirs claim one path. Do not run `git worktree prune`, `repair`, `move`, or `remove` in that git dir: `repair` would rewrite the fork checkout's `.git` file, `remove --force` would delete the fork checkout directory, and `prune` is a no-op today but would sever the backup once the registration is deemed stale. Leave that registration alone until the backup is retired with operator sign-off.
- Outer text files stored LF materialize CRLF on Windows (system `core.autocrlf=true`).
- 18 `personas/` files were CRLF on disk and are stored LF — follow-up: consider `* text=auto` in outer `.gitattributes`.

# Attribution

This persona pack is adapted from:

- **Project:** chief-of-staff-kit
- **Source:** https://github.com/skyremote/chief-of-staff-kit
- **Version:** v0.4.1 (2026-08-18)
- **License:** MIT — Copyright (c) 2026 skyremote (see `LICENSE` in this
  directory, copied verbatim from the upstream repository)
- **Installed:** 2026-08-23, into `E:\TORQ-BUZZ\personas\chief-of-staff\`

## What was kept

- The full agent roster and operating doctrine: one chief-of-staff orchestrator,
  one division-lead template (instantiated once per division), 13 shared
  specialists, and 4 opt-in comms agents.
- Specialist persona bodies are byte-faithful to the upstream templates except for
  the token fills noted below.
- The approval-gated philosophy: drafts escalate to the human rather than acting.

## What was adapted for TORQ Buzz

- **Format:** Claude Code subagent frontmatter (`tools:`, `model:`, `color:`) was
  replaced with Buzz `.persona.md` frontmatter (`name`, `display_name`,
  `description`, `triggers`, `thread_replies`, `broadcast_replies`) per
  `crates/buzz-persona/PERSONA_PACK_SPEC.md`. No model is pinned — Buzz managed
  agents get their model from the harness chosen in the desktop UI.
- **Orchestrator mechanics:** Claude Code-specific delegation plumbing
  (subagent spawn depth, `SendMessage`/`ListAgents`, `/tmp` report files) was
  rewritten to Buzz idiom: delegation by channel @mention, replies in threads,
  chase-don't-wait, and `buzz mem` for durable memory. The doctrine (clean-brief
  delegation, inline-first gate, alone-vs-council, generator+reviewer pairing) is
  unchanged.
- **`{{WORKSPACE_CONTEXT}}`** (injected into every persona by the upstream
  installer) was filled with TORQ Buzz house rules: approval-gated actions, no
  secrets ever, loopback-only services, runtime dirs stay out of Git, plain
  decisive English, date-prefixed filing, `buzz mem` usage.
- **`{{DEFAULT_STACK}}`** (cto-architect) filled with the TORQ Buzz stack:
  Rust workspace, Tauri/pnpm desktop, PowerShell scripts, Docker Compose support
  stack, Nostr relays, ACP CLI harnesses.
- **`{{FILING_MAP}}`** (ops-steward) filled with the repo's conventions:
  `docs/`, `config/`, `state/`, `evidence/`, `logs/`.
- **`{{INTEGRATION_SETUP}}`** (4 comms personas) filled with an explicit
  "not yet wired" statement, per the upstream guardrail to say so plainly rather
  than fabricate capability.
- **Division leads:** upstream generates one lead per division from an operator
  interview. No interview was possible here, so one lead — `lead-torq-buzz`, the
  TORQ Buzz platform itself — was instantiated from facts in this repo's
  `README.md` and `HANDOFF.md`, and `templates/division-lead.persona.md.template`
  is included for the operator to add further divisions.
- **Upstream installer not run:** the kit's `install-crew` skill (an interactive
  Claude Code installer) was deliberately not executed; templates were rendered
  and placed manually.

The upstream kit also renders Codex custom agents + `AGENTS.md` and Claude Code
subagents; those renderings were not needed here — Buzz persona packs are the
native format for this workspace. See the upstream README for those targets.

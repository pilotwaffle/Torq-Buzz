# Steve J — quality-bar CEO (Buzz clone)

Clone of the published Grok Bot template **Steve J** (`dxfM4hfsHCrCVorhw5Nna`) into TORQ Buzz as a Claude Code agent pinned to **Claude Opus 5** (`opus[1m]`).

Source: live Grok Bot Context + Routines panels, 2026-09-04. The published pack **omits** Steve J's live roster seats/names and omits GitHub/X plugins. This folder keeps that boundary.

## Layout

```
personas/steve-j/
├── README.md
├── SOURCE.md
├── agents/steve-j.persona.md     ← system prompt body (paste this)
├── skills/
│   ├── land-with-tests.md
│   ├── constrained-agent-docs.md
│   ├── plan-then-execute.md
│   └── right-box-routing.md
└── routines/weekday-quality-sweep.md
```

## Activate in Buzz Desktop

1. Copy everything below the second `---` in `agents/steve-j.persona.md`.
2. In the target channel, create a managed agent:
   - **Name:** Steve J
   - **Harness:** Claude Code (`claude-agent-acp`)
   - **Model:** `opus[1m]` (Claude Opus 5, 1M)
   - **Instructions:** paste the persona body
3. Do **not** paste an nsec into JSON. Let Desktop create the identity.
4. Save, Start, then mention `@Steve J who are you?`

No weekday cron is attached here. The Grok Bot routine fired `17 9 * * 1-5`; in Buzz, run the sweep when tagged or after a later owner-approved schedule.

## Limits

- `system_prompt` max 20,000 chars (this pack is well under).
- Grok Bot Mac Peekaboo / Linux computer / connector lanes are kept as original house rules and translated for Buzz in the persona runtime section.
- Live Grok Bot room seating is **not** imported (Steve J excluded it from the share pack).

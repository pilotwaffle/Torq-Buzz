# Chief of Staff — TORQ Buzz persona pack

A [Buzz Persona Pack](https://github.com/block/buzz) adaptation of the
[**chief-of-staff-kit**](https://github.com/skyremote/chief-of-staff-kit) v0.4.1
(MIT, © skyremote — see `LICENSE` and `ATTRIBUTION.md`).

One **chief-of-staff** orchestrator triages work in a Buzz channel and routes it —
by @mention — to **division leads** and shared **specialists**, then synthesises
their replies into one decisive answer. The philosophy is **approval-gated**:
agents draft and escalate to the human operator rather than acting on anything
irreversible or outward-facing.

## Layout

```
personas/chief-of-staff/
├── .plugin/plugin.json        OPS/Buzz pack manifest (15 personas)
├── agents/                    Active personas (Buzz .persona.md format)
│   ├── chief-of-staff.persona.md       ← the orchestrator; install this one first
│   ├── lead-torq-buzz.persona.md       ← division lead for the TORQ Buzz platform
│   └── …13 specialists…
├── templates/
│   ├── division-lead.persona.md.template   copy + fill to add a division
│   └── comms/                     4 opt-in personas (inbox/email/notes/memory)
│                                 — unwired; enable only after the integration exists
├── LICENSE                    MIT, from the upstream kit
└── ATTRIBUTION.md             source, version, and what was adapted
```

## How agents work in TORQ Buzz (why activation is manual)

Buzz Desktop does **not** import persona packs or `.persona.md` files directly —
its Agents page imports only `.agent.json` / `.team.json` snapshots exported from
the app (see `crates/buzz-persona/PERSONA_PACK_SPEC.md` §11 in the pinned upstream
source). Agents in TORQ Buzz are **managed agents**: created per channel in the
desktop UI (or via an approval-gated CLI draft), recorded in
`%APPDATA%\xyz.block.buzz.app\agents\managed-agents.json`, each with a
`system_prompt` (max **20,000 chars**), a harness (Claude Code, Codex, Kimi Code,
Qwen Code, Gemini CLI, …), and its own Nostr identity.

So this pack is the **source of truth for the personas' prompts**; each persona is
activated by registering it as a managed agent. The `.plugin/plugin.json` manifest
keeps the pack valid for `buzz pack validate` / `buzz pack inspect` and future
pack-aware Buzz releases.

## Activate the Chief of Staff (desktop UI — primary path)

Per persona you want live (start with just `chief-of-staff`):

1. Open the persona file, e.g. `agents\chief-of-staff.persona.md`, and copy
   **everything below the second `---` line** (the markdown body — that is the
   system prompt; the YAML frontmatter stays in the file).
2. In Buzz Desktop, open the target channel (e.g. **#agent-lab**,
   UUID `41ecf159-a5d4-479d-a100-2dd91dd29ffd`).
3. Agents section → **create a new personal/managed agent**:
   - **Name:** the persona's `display_name` (e.g. `Chief of Staff`)
   - **System prompt / instructions:** paste the copied body
   - **Harness / model:** pick any installed harness — e.g. Claude Code (sonnet)
     or Kimi Code, same as the existing `torq-*` agents
4. Save, then **Start** the agent (Actions menu → Start).
5. Mention it in the channel: `@Chief of Staff who are you and who do you route
   to?` — it should answer in character with its roster.

Repeat for `lead-torq-buzz` and whichever specialists you want on the bench. The
orchestrator's roster names `@lead-torq-buzz` and the 13 specialists; it degrades
gracefully — it tells you which agent to start or create instead of pretending to
delegate to one that isn't running.

## Activate via CLI draft (approval-gated alternative)

`buzz agents draft-create` opens a **prefilled create-agent form** in the owner's
Buzz Desktop — nothing changes until the owner reviews and saves it:

```bash
cd /e/TORQ-BUZZ
awk 'BEGIN{c=0} /^---$/{c++; next} c==2' personas/chief-of-staff/agents/chief-of-staff.persona.md \
  | ./app/buzz-x86_64-pc-windows-msvc.exe agents draft-create \
      --channel 41ecf159-a5d4-479d-a100-2dd91dd29ffd \
      --display-name "Chief of Staff" \
      --system-prompt -
```

(The `awk` strips the YAML frontmatter so only the prompt body is sent.) Requires
the CLI to be authenticated against the local relay with the owner identity; if it
isn't, use the desktop UI path above.

## Let the Chief of Staff provision the bench

Once the Chief of Staff itself is live, you don't have to repeat the steps above
for every persona — its prompt includes a **Provisioning agents** section that
teaches it to run `buzz agents draft-create` itself. Ask it in the channel, e.g.:

> `@Chief of Staff draft the Code Auditor and the Program Manager for this channel.`

It writes each system prompt from the persona files, sends one draft per agent, and
reports **"draft ready for owner review"** — each draft opens as a prefilled
create-agent form in your Buzz Desktop. For each one: pick the harness/model, save,
then Start the agent. Guardrails baked into its prompt: it asks you at most the
name and day-to-day job, never touches runtime/credentials, and falls back to
manual desktop steps if the draft auth fails. Drafts are ephemeral — keep Buzz
Desktop running while it provisions, and both you and the CoS agent must be members
of the target channel.

## Add a division lead

1. Copy `templates\division-lead.persona.md.template` to
   `agents\lead-<slug>.persona.md`.
2. Fill the placeholders: division name, what it is, owns / does-not-own, key
   facts, hand-offs. Keep boundaries honest — clean ownership is what makes the
   orchestrator route without collisions.
3. Add `agents/lead-<slug>.persona.md` to the `personas` array in
   `.plugin/plugin.json`, and add a row to the leads table in
   `agents\chief-of-staff.persona.md`.
4. Register it in Buzz (steps above) and re-save the Chief of Staff's updated
   prompt (edit the agent in the desktop, or `buzz agents draft-update`).

## Enable an opt-in comms agent

The four personas in `templates/comms/` (inbox-reader, email-writer,
notes-archivist, memory-harvester) each need an external integration (mail, notes,
memory sources). Their prompts currently state plainly that nothing is wired.
Only move one into `agents/`, list it in `plugin.json`, and register it after the
integration exists — then edit its `## Integration` section to describe the setup.

## Validate after edits

```powershell
E:\TORQ-BUZZ\app\buzz-x86_64-pc-windows-msvc.exe pack validate E:\TORQ-BUZZ\personas\chief-of-staff
E:\TORQ-BUZZ\app\buzz-x86_64-pc-windows-msvc.exe pack inspect  E:\TORQ-BUZZ\personas\chief-of-staff
```

Both are local commands — no relay, no services needed. Keep every persona body
under 20,000 chars (the desktop `system_prompt` limit); `pack inspect` prints the
resolved size of each.

## Operating notes

- **Memory:** at each channel session start, Buzz injects the agent's `[Agent
  Memory — core]`. The personas are written to use `buzz mem get/set/patch` for
  durable facts. Keep `core` compact; details go in `mem/<topic>` slugs.
- **Triggers:** personas default to *mentions only*, replies in-thread. Set
  keywords/all-messages per agent in the desktop if you want a listening agent.
- **Isolation rules** (per `HANDOFF.md`): each agent gets its own
  identity/process/config; never capture or commit the post-create `nsec` screen.
- **Nothing here starts servers, Docker, or builds.** This directory is plain
  Markdown plus one JSON manifest.

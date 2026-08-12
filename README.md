# TORQ Buzz

TORQ Buzz is a Windows-ready operational distribution of [Buzz](https://github.com/block/buzz) for a local, multi-agent Nostr workspace. It packages the pinned upstream source, reviewed TORQ fixes, Docker support services, custom ACP harnesses, recovery tooling, and operator documentation in one repository.

The goal is simple: make a powerful agent collaboration workspace easier to install, recover, audit, and improve without exposing operator credentials or runtime state.

## What is included

- **Pinned Buzz source** at `source/buzz`, based on upstream `v0.5.2`
- **Reviewed TORQ patch** at `patches/torq-buzz-local.patch`
  - Loopback-only health and metrics binding support
  - Windows `CTRL_BREAK` relay shutdown handling
  - Gemini CLI ACP capability handshake fix
- **Permanent relay operations** for a loopback Buzz relay on `127.0.0.1:3300`
- **Docker support stack** with Postgres, Redis, and MinIO
- **Custom ACP harnesses** for Qwen Code, DeepSeek, GLM 5.2, and Gemini CLI
- **DeepSeek timeout correction** using a scoped 10-minute Qwen Code API timeout
- **Operator scripts** for initialization, status checks, migration, stop ownership, and dependency validation
- **Receipt schemas and runbooks** for auditable startup, shutdown, and recovery

## Repository layout

| Path | Purpose |
|---|---|
| `compose/` | Docker Compose support stack |
| `config/` | Non-secret templates, examples, ports, and installation metadata |
| `crates/` | TORQ-specific helper crates |
| `docs/` | Operator runbooks, PRDs, rollback plans, and review artifacts |
| `harnesses/` | Installable custom Buzz ACP harness definitions |
| `patches/` | Reviewed TORQ changes applied over the pinned upstream Buzz source |
| `schemas/` | Receipt and migration schemas |
| `scripts/` | Setup, validation, status, migration, and stop-safety tooling |
| `source/buzz/` | Upstream Buzz source submodule |

Runtime directories such as `data/`, `evidence/`, `logs/`, `state/`, `bin/`, and `releases/` are intentionally excluded from Git.

## Quick start

### 1. Clone with the Buzz source

```bash
git clone --recurse-submodules https://github.com/pilotwaffle/Torq-Buzz.git
cd Torq-Buzz
```

If you already cloned without submodules:

```bash
git submodule update --init --recursive
```

### 2. Apply the TORQ source patch

```bash
git -C source/buzz apply ../../patches/torq-buzz-local.patch
```

The patch is intentionally small and reviewable. It keeps upstream at the pinned release while adding the Windows and relay-hardening changes TORQ Buzz needs.

### 3. Initialize the local layout

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Initialize-TorqBuzz.ps1
```

Copy the templates in `config/` to their local runtime names and fill in machine-specific values there. Runtime `.env` files are ignored by Git and must never be committed.

### 4. Install optional agent harnesses

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Install-CustomHarnesses.ps1
```

This installs the reviewed harness JSON files into Buzz Desktop's current-user app-data directory. Existing harnesses are not overwritten unless `-Force` is supplied.

### 5. Start and verify the support stack

Start Docker Desktop, then use the Compose file in `compose/` with your local image and secret env files. After the support services are healthy and the relay is running, verify the deployment:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Buzz-Status.ps1
```

A healthy permanent deployment should show:

- Relay WebSocket: `127.0.0.1:3300`
- Health: `127.0.0.1:8380`
- Metrics: `127.0.0.1:9302`
- Postgres: `127.0.0.1:55432`
- Redis: `127.0.0.1:16379`
- MinIO: `127.0.0.1:19000`

## Custom harnesses

The `harnesses/` directory currently includes:

- Qwen Code
- Qwen Code with Qwen3.8 Max
- Qwen Code with DeepSeek v4 Pro
- Qwen Code with GLM 5.2
- Gemini CLI

The DeepSeek harness carries `QWEN_CODE_API_TIMEOUT_MS=600000`, which prevents long Buzz prompts from failing at Qwen Code's shorter default request timeout.

Harness definitions contain no API keys. Qwen and Gemini credentials remain in each CLI's user-level configuration.

## Managed-agent memory

Buzz ACP enables managed-agent memory by default. At the start of each channel session, Buzz fetches the agent's `core` memory and injects it as `[Agent Memory — core]`. If no core exists, the agent receives a short onboarding nudge to create one.

Custom harnesses such as Qwen Code and Gemini CLI do not need a memory MCP server. They can read and write memories through the Buzz CLI inherited from the managed-agent environment:

```bash
buzz mem get core
buzz mem set core "..."
buzz mem ls
buzz mem patch <slug>
```

Keep `core` compact. Put durable details in separate `mem/<topic>` slugs and read them on demand.

## Validation

Run the safe C1 validation set:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Test-TorqBuzz.ps1 -Case ALL_C1
```

Before publishing changes, also run:

```powershell
git diff --check
gitleaks detect --no-git --source .
```

## Security model

- Nostr private keys stay in the OS credential store or local ignored runtime files.
- API keys stay in the owning CLI's user-level configuration.
- Runtime env files, logs, receipts, evidence, databases, build outputs, and local tool settings are ignored.
- Public keys may be documented; private keys and `nsec` values must never be committed.
- Stop scripts verify process ownership before terminating relay processes.

## Upstream relationship

TORQ Buzz tracks `block/buzz` and keeps TORQ-specific changes in `patches/` until they are ready to upstream or promote into a maintained fork. The pinned upstream baseline is recorded in `config/installation.json`.

## License

See [LICENSE](LICENSE).

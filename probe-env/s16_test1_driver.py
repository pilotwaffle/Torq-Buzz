#!/usr/bin/env python
"""S16 spike — Test 1 standalone buzz-acp driver (throwaway, do not merge).

Drives live Activity emit->paint samples for the operator-attended Test 1 by
running a *standalone* buzz-acp (not the desktop-managed one) that publishes
encrypted observer frames (kind 24200) over the live relay, and capturing its
`observer emit clock` tracing lines to a file.

The agent identity is a FRESH coincurve key (Invariant 7: never the operator
nsec / daily identity). Frames are encrypted to --owner (the desktop identity
pubkey, 64-hex) so the running desktop can decrypt + paint them.

Modes:
  --gen-key              mint a throwaway key, save to KEY_FILE, print pubkey
  --run                  read KEY_FILE and run buzz-acp (claude-agent-acp or goose)

Loads ANTHROPIC_API_KEY from E:\\TORQ-CONSOLE\\.env into the child env only;
the value is never printed.
"""

import argparse
import json
import os
import subprocess
import sys
import time

ENV_FILE = r"E:\TORQ-CONSOLE\.env"
BUZZ_ACP = r"E:\TORQ-BUZZ\source\buzz\target\debug\buzz-acp.exe"
KEY_FILE = r"E:\TORQ-BUZZ\probe-env\s16-test1-agent-key.json"
# NIP-OA attestation (["auth","<owner>","","<sig>"]) minted by the OWNER for the
# agent pubkey in KEY_FILE. The probe never mints this (it would need the owner
# nsec, Invariant 7); the operator mints it once and drops the JSON here.
AUTH_TAG_FILE = r"E:\TORQ-BUZZ\probe-env\s16-test1-auth-tag.json"
RELAY = "ws://127.0.0.1:3300"

DEFAULT_PROMPT = (
    "Report your current status in one short paragraph: state the current "
    "date and time, and describe in one sentence what you are doing right "
    "now. Then end your turn."
)


def load_env_key(path, name):
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            if k.strip() == name:
                return v.strip().strip('"').strip("'")
    return None


def load_auth_tag(path):
    """Read a NIP-OA auth tag (raw `["auth",...]` JSON string) from a file.

    Accepts either the bare tag JSON on one line, or a JSON object with an
    `auth_tag` field. Returns the tag string, or None if absent/unreadable.
    """
    if not path or not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        raw = f.read().strip()
    if not raw:
        return None
    try:
        obj = json.loads(raw)
        if isinstance(obj, dict) and isinstance(obj.get("auth_tag"), str):
            return obj["auth_tag"]
        # A bare tag is itself a JSON array; return the original string.
        return raw
    except json.JSONDecodeError:
        return raw


def gen_key():
    import coincurve  # lazy import: only needed for --gen-key, not --run
    sk = coincurve.PrivateKey()
    secret_hex = sk.secret.hex()
    pubkey = sk.public_key.format(compressed=True)[1:33].hex()
    return secret_hex, pubkey


def cmd_gen():
    secret_hex, pubkey = gen_key()
    payload = {"secret_hex": secret_hex, "pubkey": pubkey,
               "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    with open(KEY_FILE, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
    print("AGENT_PUBKEY=" + pubkey)
    print("KEY_FILE=" + KEY_FILE)
    print("paste AGENT_PUBKEY into /s16-spike pubkey input before --run")
    return 0


def cmd_run(args):
    if not os.path.exists(KEY_FILE):
        print("FAIL: run --gen-key first")
        return 2
    with open(KEY_FILE, "r", encoding="utf-8") as f:
        key = json.load(f)
    secret_hex = key["secret_hex"]
    pubkey = key["pubkey"]

    anthropic = load_env_key(ENV_FILE, "ANTHROPIC_API_KEY")
    openai_key = load_env_key(ENV_FILE, "OPENAI_API_KEY")
    if args.harness == "claude-agent-acp" and not anthropic:
        print("FAIL: ANTHROPIC_API_KEY not found in " + ENV_FILE)
        return 2
    if args.harness == "goose" and not openai_key:
        print("FAIL: OPENAI_API_KEY not found in " + ENV_FILE)
        return 2

    argv = [
        BUZZ_ACP,
        "--private-key", secret_hex,
        "--relay-url", RELAY,
        "--agent-owner", args.owner,
        "--respond-to", "nobody",
        "--heartbeat-interval", str(args.heartbeat),
        "--heartbeat-prompt", args.prompt,
    ]

    auth_tag = load_auth_tag(args.auth_tag_file or AUTH_TAG_FILE)
    env = dict(os.environ)
    env.update({
        "BUZZ_PRIVATE_KEY": secret_hex,
        "BUZZ_RELAY_URL": RELAY,
        "BUZZ_ACP_AGENT_OWNER": args.owner,
        "BUZZ_ACP_RELAY_OBSERVER": "true",
        "RUST_LOG": "observer=debug,error",
    })
    if auth_tag:
        # NIP-OA owner attestation — the relay materializes agent->owner from it
        # on connect, which is what unblocks kind-24200 publish (is_agent_owner).
        env["BUZZ_AUTH_TAG"] = auth_tag
    if args.harness == "claude-agent-acp":
        # claude-agent-acp is an npm .cmd shim (no .exe); buzz-acp's
        # tokio::process::Command can't resolve .cmd on Windows, so wrap it in
        # cmd.exe /c. A3.5 already proved `cmd /c claude-agent-acp` speaks ACP
        # NDJSON over stdio. Note: this makes the observer harness field read
        # "cmd" (cosmetic) — the true harness is recorded by this driver.
        env["BUZZ_ACP_AGENT_COMMAND"] = "cmd.exe"
        env["BUZZ_ACP_AGENT_ARGS"] = "/c,claude-agent-acp"
    else:  # goose — real .exe, spawns directly
        env["BUZZ_ACP_AGENT_COMMAND"] = args.harness
        env["GOOSE_MODE"] = "auto"
        env["BUZZ_ACP_AGENT_ARGS"] = "acp"
        # goose 1.45.0 needs an explicit provider + model; GOOSE_MODE alone is
        # approval mode, not provider selection (verified: a bare OPENAI_API_KEY
        # is NOT auto-detected). gpt-4o-mini = cheap/fast spike path.
        env["GOOSE_PROVIDER"] = "openai"
        env["GOOSE_MODEL"] = "gpt-4o-mini"
    if anthropic:
        env["ANTHROPIC_API_KEY"] = anthropic
    if openai_key:
        env["OPENAI_API_KEY"] = openai_key

    print("AGENT_PUBKEY=" + pubkey)
    print("OWNER=" + args.owner)
    print("HARNESS=" + args.harness)
    print("LOGFILE=" + args.out)
    print("launching buzz-acp (relay-observer, heartbeat=%ds, respond-to=nobody) ..."
          % args.heartbeat)

    with open(args.out, "a", encoding="utf-8", errors="replace") as out:
        out.write("\n=== run %s harness=%s owner=%s agent=%s ===\n"
                  % (time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                     args.harness, args.owner, pubkey))
        out.flush()
        proc = subprocess.Popen(argv, stdout=out, stderr=subprocess.STDOUT, env=env)
        print("buzz-acp PID=%d" % proc.pid)
        try:
            proc.wait(timeout=args.seconds)
        except subprocess.TimeoutExpired:
            proc.terminate()
            try:
                proc.wait(5)
            except subprocess.TimeoutExpired:
                proc.kill()
            print("stopped after %ds" % args.seconds)
        else:
            print("buzz-acp exited code=%d" % proc.returncode)
    print("DONE — emit clock in " + args.out)
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="mode", required=True)
    sub.add_parser("gen-key")
    run = sub.add_parser("run")
    run.add_argument("--owner", required=True, help="desktop identity pubkey (64 hex)")
    run.add_argument("--harness", default="claude-agent-acp",
                     choices=["claude-agent-acp", "goose"])
    run.add_argument("--heartbeat", type=int, default=10)
    run.add_argument("--prompt", default=DEFAULT_PROMPT)
    run.add_argument("--seconds", type=int, default=180)
    run.add_argument("--out", default=r"E:\TORQ-BUZZ\probe-env\s16-test1-emit-clock.log")
    run.add_argument("--auth-tag-file", default=None,
                     help="NIP-OA auth tag file (defaults to s16-test1-auth-tag.json)")
    args = ap.parse_args()

    if args.mode == "gen-key":
        return cmd_gen()
    return cmd_run(args)


if __name__ == "__main__":
    sys.exit(main())

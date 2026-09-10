#!/usr/bin/env python
"""S16 spike - throwaway, do not merge.

Kind-24200 NEGATIVE case probe. Connects to the live relay and captures, verbatim,
what the relay sends for:
  (1) an UNAUTHENTICATED REQ of the kind-24200 stream;
  (2) an AUTH as a freshly generated NON-OWNER key, then REQ of kind-24200.

Uses coincurve (BIP340 Schnorr) only - an independent implementation from the
relay's own crypto - and signs NIP-42 kind-22242 AUTH events by hand. No operator
nsec / daily identity is ever loaded (Invariant 7).

Relay URL defaults to ws://127.0.0.1:3300.
"""

import hashlib
import json
import sys
import time

import coincurve
from websockets.sync.client import connect

RELAY = sys.argv[1] if len(sys.argv) > 1 else "ws://127.0.0.1:3300"
WATCH_SECS = 6.0
KIND_24200 = 24200
KIND_AUTH = 22242


def now():
    return int(time.time())


def serialize_for_id(pubkey, created_at, kind, tags, content):
    return json.dumps(
        [0, pubkey, created_at, kind, tags, content],
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")


def sign_event(private_key, created_at, kind, tags, content):
    pubkey = private_key.public_key.format(compressed=True)[1:33].hex()
    event_id = hashlib.sha256(
        serialize_for_id(pubkey, created_at, kind, tags, content)
    ).hexdigest()
    sig = private_key.sign_schnorr(bytes.fromhex(event_id)).hex()
    return {
        "id": event_id,
        "pubkey": pubkey,
        "created_at": created_at,
        "kind": kind,
        "tags": tags,
        "content": content,
        "sig": sig,
    }


def build_auth_event(private_key, challenge, relay_url):
    return sign_event(
        private_key,
        now(),
        KIND_AUTH,
        [["challenge", challenge], ["relay", relay_url]],
        "",
    )


def watch(ws, label, seconds):
    deadline = time.time() + seconds
    msgs = []
    while time.time() < deadline:
        remaining = deadline - time.time()
        if remaining <= 0:
            break
        try:
            raw = ws.recv(timeout=remaining)
        except TimeoutError:
            break
        except Exception as exc:  # noqa: BLE001 - capture any close reason
            print(f"[{label}] recv-exception: {type(exc).__name__}: {exc}")
            break
        msgs.append(raw)
        print(f"[{label}] <- {raw}")
    return msgs


def run_unauth():
    print(f"=== (1) UNAUTHENTICATED REQ kind={KIND_24200} -> {RELAY} ===")
    with connect(RELAY, open_timeout=5) as ws:
        req = json.dumps(["REQ", "s16-unauth", {"kinds": [KIND_24200]}])
        print(f"[unauth] -> {req}")
        ws.send(req)
        watch(ws, "unauth", WATCH_SECS)
    print()


def run_non_owner_auth():
    print(f"=== (2) AUTH as NON-OWNER key, then REQ kind={KIND_24200} -> {RELAY} ===")
    key = coincurve.PrivateKey()
    pubkey = key.public_key.format(compressed=True)[1:33].hex()
    print(f"[auth] generated non-owner key pubkey={pubkey}")
    with connect(RELAY, open_timeout=5) as ws:
        req = json.dumps(["REQ", "s16-nonowner", {"kinds": [KIND_24200]}])
        print(f"[auth] -> {req}")
        ws.send(req)
        # Collect the NIP-42 AUTH challenge.
        challenge = None
        deadline = time.time() + 5.0
        while time.time() < deadline and challenge is None:
            try:
                raw = ws.recv(timeout=deadline - time.time())
            except TimeoutError:
                break
            print(f"[auth] <- {raw}")
            msg = json.loads(raw)
            if isinstance(msg, list) and msg and msg[0] == "AUTH":
                challenge = msg[1]
        if challenge is None:
            print("[auth] no AUTH challenge received; cannot demonstrate AUTH")
            watch(ws, "auth", WATCH_SECS)
            return
        auth_event = build_auth_event(key, challenge, RELAY)
        auth_msg = json.dumps(["AUTH", auth_event], separators=(",", ":"))
        print(f"[auth] -> {auth_msg}")
        ws.send(auth_msg)
        # Re-issue the REQ after authenticating (relay may have dropped the first).
        print(f"[auth] -> {req}")
        ws.send(req)
        watch(ws, "auth", WATCH_SECS)
    print()


def main():
    run_unauth()
    run_non_owner_auth()
    print("=== probe complete ===")


if __name__ == "__main__":
    main()

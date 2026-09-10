#!/usr/bin/env python
"""S16 spike — live-stream verification (throwaway, do not merge).

Subscribes to the relay with the DESKTOP's exact observer filter (kinds=[24200],
#p=[owner], limit=1000, since=now-300) and, while connected, launches the Test 1
driver for a short burst. Confirms kind-24200 frames stream LIVE to a subscriber
matching #p=owner — the exact path the desktop takes. Prints frame count + tags.
"""

import asyncio
import json
import subprocess
import sys
import time

import websockets

RELAY = "ws://127.0.0.1:3300"
OWNER = sys.argv[1] if len(sys.argv) > 1 else "2eb05bc6f4d0c5bd082cdc801b57f5ff6acd4a08f2706de7c5ef727dc133efa8"
DRIVER = r"E:\TORQ-BUZZ\probe-env\s16_test1_driver.py"
OUT = r"E:\TORQ-BUZZ\probe-env\s16-test1-claude-emit-clock-2.log"
PY = r"E:\Python\python.exe"


async def main():
    seen = []

    async def collect(ws, deadline):
        while time.time() < deadline:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=1.0)
            except asyncio.TimeoutError:
                continue
            except Exception as exc:
                print("collect ended: %r" % exc, flush=True)
                break
            try:
                msg = json.loads(raw)
            except Exception:
                continue
            if msg[0] == "EVENT":
                ev = msg[2]
                tags = ev.get("tags", [])
                p = [t[1] for t in tags if t and t[0] == "p"]
                agent = [t[1] for t in tags if t and t[0] == "agent"]
                frame = [t[1] for t in tags if t and t[0] == "frame"]
                seen.append((ev.get("created_at"), p, agent, frame))
                print("  LIVE EVENT created_at=%s p=%s agent=%s frame=%s" % (
                    ev.get("created_at"), p, agent, frame), flush=True)

    async with websockets.connect(RELAY) as ws:
        since = int(time.time()) - 300
        await ws.send(json.dumps([
            "REQ", "s16-verify", {"kinds": [24200], "#p": [OWNER], "limit": 1000, "since": since},
        ]))
        print("subscribed #p=%s (live) — launching driver (heartbeat=3s) for ~25s..." % OWNER[:16], flush=True)

        proc = subprocess.Popen(
            [PY, DRIVER, "run", "--owner", OWNER, "--harness", "claude-agent-acp",
             "--heartbeat", "10", "--seconds", "30", "--out", OUT],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        await collect(ws, time.time() + 34)
        proc.terminate()

    print("LIVE-STREAM RESULT: received %d kind-24200 events matching #p=%s" % (len(seen), OWNER[:16]))
    for i, (created, p, agent, frame) in enumerate(seen[:5]):
        print("  #%d created_at=%s p=%s agent=%s frame=%s" % (
            i, created, p[:1] + ["…"], agent[:1] + ["…"], frame))
    if seen:
        print("  first_created_at=%s last_created_at=%s" % (seen[0][0], seen[-1][0]))


asyncio.run(main())

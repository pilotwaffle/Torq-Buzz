#!/usr/bin/env python3
"""S16 Test 2 - steer-during-active-turn send->ack latency, split by harness runtime.

Method (runbook S16 §3 + operator ruling 2026-09-08):
  send  = relay "Event ingested via pipeline" timestamp (microsecond RFC3339).
          This is the operator-send proxy; it excludes only the desktop->relay
          hop on loopback.
  ack   = sidecar "non-cancelling steer ack received" tracing timestamp.
  latency = ack - send.
  Join key = event_id (identical on relay ingest, sidecar steer_received, sidecar ack).

Runtime split: the sidecar log is append-only across runtime switches. The SAME
managed agent (pubkey d12449c1...) was switched from claude-agent-acp to goose in
place, so both runtimes' steers land in the SAME file. This script tracks the
active runtime via each "buzz-acp starting:" banner's agent_cmd= (goose vs
claude-agent-acp) and reports each harness separately.

Also reports the sidecar-local leg (steer_received -> ack) for attribution.

Usage:
  python s16-test2-steer-ack-latency.py [sidecar.log] [relay.log]

Percentiles: p50 = median (mean of two middles for even n); p95/p99 = nearest-rank,
element at 1-based index ceil(P*n) - matches the results-doc header convention.
"""

import sys
import re
import math
from datetime import datetime, timezone

SIDECAR = (
    r"C:\Users\asdasd\AppData\Roaming\xyz.block.buzz.app.dev\agents\logs"
    r"\d12449c1406b8dba65305676d05a9dbea78c1e0def0195c983bbc59932986a5a"
    r"__5fe629a5a31a031866abe522b6181704f22cc38d01e7cb2ff1c11e0c8a5086e6.log"
)
RELAY = r"E:\TORQ-BUZZ\logs\relay-recovery-20260903-023357.stdout.log"

ANSI = re.compile(r"\x1b\[[0-9;]*m")
TS = re.compile(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z)")
EVENT_ID = re.compile(r'event_id["=:]+([0-9a-f]{64})')
START = re.compile(r"buzz-acp starting:.*agent_cmd=(\S+)")
SESSION = re.compile(r'session_id: "([^"]+)"')


def parse_ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc)


def ms(a, b):
    return (b - a).total_seconds() * 1000.0


def runtime_of(agent_cmd):
    if "goose" in agent_cmd:
        return "goose"
    return "claude-agent-acp"


def median(vals):
    n = len(vals)
    if n == 0:
        return None
    if n % 2 == 1:
        return vals[n // 2]
    return (vals[n // 2 - 1] + vals[n // 2]) / 2.0


def nearest_rank(vals, p):
    n = len(vals)
    if n == 0:
        return None
    idx = max(0, min(n - 1, int(math.ceil(p * n)) - 1))
    return vals[idx]


def report(label, rows):
    """rows = list of (eid, ingest_ts, recv_ts, ack_ts)."""
    full_spans = []
    print(f"\n### {label}  (n={len(rows)} steer sample(s) with an ack line)")
    print(f"{'event_id':38s} {'ingest->ack ms':>14s} {'ingest->recv ms':>16s} {'recv->ack ms':>13s}")
    for eid, ing, recv, ac in rows:
        ing_recv = ms(ing, recv) if ing and recv else None
        recv_ack = ms(recv, ac) if recv else None
        full = ms(ing, ac) if ing else None
        if full is not None:
            full_spans.append(full)
        if full is not None:
            head = f"{eid[:16]}..{eid[-8:]:>10s} {full:14.3f}"
        else:
            head = f"{eid[:16]}..{eid[-8:]:>10s} {'(no relay ingest)':>14s}"
        print(
            head,
            f" {ing_recv:16.3f}" if ing_recv is not None else f" {'-':>16s}",
            f" {recv_ack:13.3f}" if recv_ack is not None else f" {'-':>13s}",
        )

    if not full_spans:
        print("NO full-span samples (no ack matched a relay ingest).")
        return
    full_spans.sort()
    print(f"full span (ingest -> ack) sorted: {['%.3f' % x for x in full_spans]}")
    print(f"p50 = {median(full_spans):.3f} ms")
    print(f"p90 = {nearest_rank(full_spans, 0.90):.3f} ms")
    print(f"p95 = {nearest_rank(full_spans, 0.95):.3f} ms")
    print(f"p99 = {nearest_rank(full_spans, 0.99):.3f} ms")
    print(f"max = {max(full_spans):.3f} ms")


def main():
    sidecar = sys.argv[1] if len(sys.argv) > 1 else SIDECAR
    relay = sys.argv[2] if len(sys.argv) > 2 else RELAY

    ingest = {}  # event_id -> relay ingest ts

    with open(relay, encoding="utf-8", errors="replace") as f:
        for line in f:
            if '"Event ingested via pipeline"' not in line:
                continue
            m_id = EVENT_ID.search(line)
            m_ts = TS.search(line)
            if not m_id or not m_ts:
                continue
            eid = m_id.group(1)
            if eid not in ingest:  # first ingest wins
                ingest[eid] = parse_ts(m_ts.group(1))

    # event_id -> (runtime, received_ts, ack_ts). Runtime set from the active
    # "buzz-acp starting:" banner at the moment the steer event was logged.
    steers = {}

    current_runtime = None
    with open(sidecar, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = ANSI.sub("", line)
            m = START.search(line)
            if m:
                current_runtime = runtime_of(m.group(1))
                continue
            m_id = EVENT_ID.search(line)
            m_ts = TS.search(line)
            if not m_id or not m_ts:
                continue
            eid = m_id.group(1)
            ts = parse_ts(m_ts.group(1))
            entry = steers.setdefault(eid, [current_runtime, None, None])
            if " steer received " in line:
                if entry[1] is None:
                    entry[1] = ts
            elif "non-cancelling steer ack received" in line:
                if entry[2] is None:
                    entry[2] = ts

    # group by runtime, ordered by ack time
    by_runtime = {}
    sessions = {}
    for eid, (runtime, recv, ac) in steers.items():
        if ac is None:
            continue
        by_runtime.setdefault(runtime, []).append((eid, ingest.get(eid), recv, ac))
        # record session_id seen in ack lines for the evidence note
    for runtime in by_runtime:
        by_runtime[runtime].sort(key=lambda r: r[3])

    print(f"total ack samples = {sum(len(v) for v in by_runtime.values())}")
    for runtime in sorted(by_runtime):
        report(runtime, by_runtime[runtime])


if __name__ == "__main__":
    main()

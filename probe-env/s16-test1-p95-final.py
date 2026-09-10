#!/usr/bin/env python
"""S16 spike Test 1 (B2) — FINAL emit->paint p50/p95 for both harnesses.

CORRECT method (supersedes s16-p95.py's `seq = n - P`):

The paint-log counter `n` is the desktop's `events.length` — the count of
COALESCED observer events. The chunk coalescer (`ObserverChunkCoalescer`) merges
`acp_read` chunks that share a key, so the desktop receives far fewer events than
the Rust side emits (run5: n=690 vs seq=1210; goose: n=219 vs seq=969). Mapping
`n` back to source `seq` by a linear offset is therefore invalid.

Instead, pair each paint with its batch by TIME. The publisher
(`run_relay_observer_publisher`) publishes at most one frame per
`OBSERVER_PUBLISH_TICK = 1s`; a batch's envelope carries the LAST inner event's
seq/timestamp. So for a paint at epoch P, the batch it commits was published at
the last 1s tick <= P, and its last event is the latest emit with
`emit_ms <= that tick`. latency = P - emit_ms[that event].

This is the "batch-boundary" method. The naive "latest emit <= paint" method
underestimates: events emitted after the batch was assembled but before the paint
(stray, still-queued events) get matched and produce false ~1ms latencies.
"""
import bisect
import re

ANSI = re.compile(r"\x1b\[[0-9;]*m")

GOOSE_EMIT = r"E:\TORQ-BUZZ\probe-env\s16-test1-goose-paint-run1.log"
CLAUDE_EMIT = r"E:\TORQ-BUZZ\probe-env\s16-test1-claude-paint-run5.log"
PAINT_LOG = r"E:\TORQ-BUZZ\probe-env\s16-test1-paintlog-full.txt"


def load_emit(path):
    ev = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = ANSI.sub("", line)
            m = re.search(r"seq=(\d+).*emit_epoch_millis=(\d+)", line)
            if m:
                ev.append((int(m.group(1)), int(m.group(2))))
    ev.sort(key=lambda x: x[1])
    return ev


def load_paint(path):
    paint = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.search(r"epoch=(\d+) n=(\d+)", line)
            if m:
                paint.append((int(m.group(1)), int(m.group(2))))
    paint.sort()
    return paint


def pct(a, p):
    a = sorted(a)
    if not a:
        return None
    return a[min(len(a) - 1, int(round(p * (len(a) - 1))))]


def measure(name, emit, paint):
    first = emit[0][1]
    last = emit[-1][1]
    ms = [m for _, m in emit]
    win = [(ep, n) for (ep, n) in paint if first <= ep <= last + 3000]

    bb, raw = [], []
    for ep, _n in win:
        # batch-boundary: last emit <= last 1s tick before the paint
        tick = first + ((ep - first) // 1000) * 1000
        j = bisect.bisect_right(ms, tick) - 1
        if j >= 0:
            lat = ep - ms[j]
            if 0 <= lat < 10000:
                bb.append(lat)
        # naive: last emit <= paint
        i = bisect.bisect_right(ms, ep) - 1
        if i >= 0:
            lat = ep - ms[i]
            if 0 <= lat < 10000:
                raw.append(lat)

    print("=== %s ===" % name)
    print("  emit events=%d span=%.1fs | paints in window=%d" %
          (len(emit), (last - first) / 1000.0, len(win)))
    print("  batch-boundary (correct): n=%d  p50=%s  p90=%s  p95=%s  p99=%s  max=%s" %
          (len(bb), pct(bb, .5), pct(bb, .9), pct(bb, .95), pct(bb, .99),
           max(bb) if bb else None))
    print("  naive latest<=paint:      n=%d  p50=%s  p90=%s  p95=%s  p99=%s  max=%s" %
          (len(raw), pct(raw, .5), pct(raw, .9), pct(raw, .95), pct(raw, .99),
           max(raw) if raw else None))
    return bb


if __name__ == "__main__":
    paint = load_paint(PAINT_LOG)
    measure("GOOSE (gpt-4o-mini)", load_emit(GOOSE_EMIT), paint)
    print()
    measure("CLAUDE run5 (claude-agent-acp)", load_emit(CLAUDE_EMIT), paint)

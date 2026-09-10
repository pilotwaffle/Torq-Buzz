#!/usr/bin/env python
"""S16 spike Test 1 (B2) — goose leg: emit->paint p50/p95, CORRECT method.

Matches the Claude leg's s16-p95.py approach: for each paint, latency =
paint.epoch - emit_ms[last APPENDED event], where "last appended event" is
recovered from the paint-log counter `n` (= desktop events.length), which
wraps at 3000 and trims to 2700.

Why not "latest emit <= paint"? The agent emits continuously (~5.6 ev/s) while
the publisher batches at 1/s, so between a batch's append and its paint, newer
events are emitted but NOT yet appended. "latest emit <= paint" matches those
stray events and yields false ~1ms latencies. The `n` counter tracks *appended*
events, so it pinpoints the batch's actual last event.
"""
import re

PAINT_LOG = r"E:\TORQ-BUZZ\probe-env\s16-test1-paintlog-full.txt"
EMIT_LOG = r"E:\TORQ-BUZZ\probe-env\s16-test1-goose-paint-run1.log"
ANSI = re.compile(r"\x1b\[[0-9;]*m")

# --- parse paint log: (epoch_ms, n) ---
paint = []
with open(PAINT_LOG, "r", encoding="utf-8", errors="replace") as f:
    for line in f:
        line = ANSI.sub("", line)
        m = re.search(r"epoch=(\d+) n=(\d+)", line)
        if m:
            paint.append((int(m.group(1)), int(m.group(2))))

# --- parse emit clock: seq -> emit_ms ---
emit = {}
emit_seq_list = []
with open(EMIT_LOG, "r", encoding="utf-8", errors="replace") as f:
    for line in f:
        line = ANSI.sub("", line)
        m = re.search(r"seq=(\d+).*emit_epoch_millis=(\d+)", line)
        if m:
            s = int(m.group(1)); ms = int(m.group(2))
            emit[s] = ms
            emit_seq_list.append((s, ms))

first_emit = min(ms for _, ms in emit_seq_list)
last_emit = max(ms for _, ms in emit_seq_list)

print("=== GOOSE LEG emit->paint (n->seq, trim-aware) ===")
print("emit events:", len(emit_seq_list), "| seq range:", min(s for s, _ in emit_seq_list), "-", max(s for s, _ in emit_seq_list))
print("emit span: %.1f s" % ((last_emit - first_emit) / 1000.0))

# N0 = events.length just before the goose run = n of last paint strictly before first_emit
n0 = None
for (ep, n) in paint:
    if ep < first_emit:
        n0 = n
    else:
        break
print("N0 (n before goose run):", n0)

# goose-window paints (include buffer after last emit for the final paint)
BUFFER = 5000
win = [(ep, n) for (ep, n) in paint if first_emit <= ep <= last_emit + BUFFER]
print("paint entries in goose window:", len(win))

# walk window paints, detect trim(s) as n dropping by ~300, then map n -> goose seq S
latencies = []
details = []
trim_count = 0
prev_n = None
for (ep, n) in win:
    if prev_n is not None and n < prev_n - 250:
        trim_count += 1
    S = n - n0 + 300 * trim_count  # last appended goose seq
    if S in emit:
        lat = ep - emit[S]
        if 0 <= lat < 10000:
            latencies.append(lat)
            details.append((ep, n, S, lat))
    prev_n = n

latencies.sort()

def pct(p):
    if not latencies:
        return None
    idx = min(len(latencies) - 1, int(round(p * (len(latencies) - 1))))
    return latencies[idx]

print("\ntrims detected:", trim_count)
print("latency samples:", len(latencies))
print("min:", latencies[0] if latencies else None)
print("p50:", pct(0.50))
print("p90:", pct(0.90))
print("p95:", pct(0.95))
print("p99:", pct(0.99))
print("max:", latencies[-1] if latencies else None)

print("\nfirst 8 (paint_epoch, n, S, lat_ms):")
for d in details[:8]:
    print("  epoch=%d n=%d S=%d lat=%d" % d)
print("last 8:")
for d in details[-8:]:
    print("  epoch=%d n=%d S=%d lat=%d" % d)

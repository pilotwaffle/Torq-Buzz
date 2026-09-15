# Slice 3 AC-21 fire-to-inject: pair routine_dispatches.dispatched_at (relay, Postgres) with the
# sidecar's `routine prompt received run_id=...` INFO line; nearest-rank p95 per harness.
# usage: python s3-latency.py <sidecar-log>... -- <relay-stdout-log>...  (start = relay "routine fired" line for the run_id; EXCLUDE env: comma-separated run_id prefixes to skip, e.g. deliberately held runs)
import subprocess, re, sys, math, datetime as dt
rows = subprocess.run(["docker","exec","torq-buzz-postgres-1","psql","-U","buzz","-d","buzz","-Atc",
    "select d.run_id, w.name, d.dispatched_at, d.outcome from routine_dispatches d join workflows w on w.id=d.workflow_id order by d.dispatched_at"],
    capture_output=True, text=True).stdout.strip().splitlines()
disp = {}
for r in rows:
    run_id, name, ts, outcome = r.split("|")
    disp[run_id] = (name, dt.datetime.fromisoformat(ts.replace("+00", "+00:00")), outcome)
recv = {}
fired = {}
import os, json
args = sys.argv[1:]
sidecars = args[:args.index("--")] if "--" in args else args
relays = args[args.index("--")+1:] if "--" in args else []
for path in relays:
    for line in open(path, encoding="utf-8", errors="replace"):
        if '"message":"routine fired"' in line:
            try: j = json.loads(line)
            except Exception: continue
            fired[j.get("run_id","")] = dt.datetime.fromisoformat(j["timestamp"].replace("Z","+00:00"))
exclude = tuple(x for x in os.environ.get("EXCLUDE","").split(",") if x)
ansi = re.compile(r"\x1b\[[0-9;]*m")
for path in sidecars:
    for line in open(path, encoding="utf-8", errors="replace"):
        line = ansi.sub("", line)
        m = re.search(r"^(\S+Z)\s+INFO\s+buzz_acp::pool: routine prompt received run_id=(\S+)", line)
        if m:
            recv[m[2]] = dt.datetime.fromisoformat(m[1].replace("Z", "+00:00"))
samples = []
print("run_id                               routine                  dispatched_at            received_at              ms   outcome")
for run_id, (name, d, outcome) in disp.items():
    d = fired.get(run_id, d)
    if run_id.startswith(exclude):
        print(f"{run_id} {name:24s} EXCLUDED (operator-held run)"); continue
    if run_id in recv:
        ms = (recv[run_id] - d).total_seconds() * 1000
        samples.append(ms)
        print(f"{run_id} {name:24s} {d.isoformat()[11:23]} {recv[run_id].isoformat()[11:23]} {ms:7.0f} {outcome}")
    else:
        print(f"{run_id} {name:24s} {d.isoformat()[11:23]} (no sidecar receipt)                {outcome}")
if samples:
    s = sorted(samples); n = len(s)
    print(f"\nn={n} p50={s[n//2]:.0f} ms p95={s[math.ceil(0.95*n)-1]:.0f} ms max={s[-1]:.0f} ms (fire-to-inject: relay `routine fired` -> sidecar `routine prompt received`)")

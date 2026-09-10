import sqlite3, os, time, datetime

def ts(sec):
    try:
        return datetime.datetime.utcfromtimestamp(int(sec)).strftime("%Y-%m-%d %H:%M:%S") + " UTC"
    except Exception:
        return str(sec)

nests = {
    ".buzz (release)": r"C:\Users\asdasd\.buzz\archive\archive.db",
    ".buzz-dev (daily)": r"C:\Users\asdasd\.buzz-dev\archive\archive.db",
    ".buzz-demo-s16test5 (Test5 demo)": r"C:\Users\asdasd\.buzz-demo-s16test5\archive\archive.db",
}

for label, p in nests.items():
    print(f"\n=== {label} ===")
    if not os.path.exists(p):
        print("  (missing)"); continue
    conn = sqlite3.connect(f"file:{p}?mode=ro", uri=True)
    cur = conn.cursor()
    # recent 24200 frames
    rows = cur.execute(
        "SELECT id, kind, created_at FROM archived_events WHERE kind=24200 ORDER BY created_at DESC LIMIT 8"
    ).fetchall()
    print(f"  recent kind=24200 (newest first):")
    for r in rows:
        eid = (r[0] or "")[:16]
        print(f"    {ts(r[2])}  id={eid}...  kind={r[1]}")
    # total + span for 24200
    tot = cur.execute("SELECT COUNT(*), MIN(created_at), MAX(created_at) FROM archived_events WHERE kind=24200").fetchone()
    print(f"  24200 total={tot[0]}  span {ts(tot[1])} .. {ts(tot[2])}")
    conn.close()

print("\n=== now ===")
print("  local:", time.strftime("%Y-%m-%d %H:%M:%S %Z"))
print("  utc  :", time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime()))

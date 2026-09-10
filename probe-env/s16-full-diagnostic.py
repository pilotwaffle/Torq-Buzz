import sqlite3, os, glob, time

nests = [
    r"C:\Users\asdasd\.buzz",
    r"C:\Users\asdasd\.buzz-dev",
    r"C:\Users\asdasd\.buzz-demo-s16test5",
]

print("=== save_subscriptions FULL rows ===")
for nest in nests:
    p = os.path.join(nest, "archive", "archive.db")
    print(f"\n--- {p} ---")
    if not os.path.exists(p):
        print("  (missing)")
        continue
    st = os.stat(p)
    print(f"  mtime: {time.ctime(st.st_mtime)}  size: {st.st_size}")
    for suffix in ("-wal", "-shm"):
        sp = p + suffix
        if os.path.exists(sp):
            print(f"  {suffix}: {os.stat(sp).st_size} bytes  mtime {time.ctime(os.stat(sp).st_mtime)}")
    try:
        conn = sqlite3.connect(f"file:{p}?mode=ro", uri=True)
        cur = conn.cursor()
        rows = cur.execute(
            "SELECT identity_pubkey, relay_url, scope_type, scope_value, kinds, created_at "
            "FROM save_subscriptions ORDER BY created_at"
        ).fetchall()
        if not rows:
            print("  save_subscriptions: (empty)")
        for r in rows:
            ipk = r[0][:12] + "..." if r[0] else "NULL"
            print(f"  ipk={ipk} relay={r[1]!r} scope={r[2]} scope_val={r[3][:12]}... kinds={r[4]} created={r[5]}")
        # archived_events kind counts
        counts = cur.execute(
            "SELECT kind, COUNT(*) FROM archived_events GROUP BY kind ORDER BY kind"
        ).fetchall()
        print(f"  archived_events kind counts: {counts}")
        conn.close()
    except Exception as e:
        print(f"  error: {e}")

print("\n=== all archive.db files under home (recent first) ===")
home = r"C:\Users\asdasd"
for p in glob.glob(os.path.join(home, ".buzz*", "archive", "archive.db")):
    try:
        m = os.stat(p).st_mtime
        print(f"  {time.ctime(m)}  {os.stat(p).st_size:>10}  {p}")
    except Exception as e:
        print(f"  error {p}: {e}")

print("\n=== BUZZ env vars (presence only, never values) ===")
for v in ("BUZZ_PRIVATE_KEY", "BUZZ_RELAY_URL", "BUZZ_RELAY_HTTP", "BUZZ_DESKTOP_BUILD_RELAY_URL"):
    val = os.environ.get(v)
    if val is None:
        print(f"  {v}: UNSET")
    else:
        print(f"  {v}: SET (len={len(val)})")

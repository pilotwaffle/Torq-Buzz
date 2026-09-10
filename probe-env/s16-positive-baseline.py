import sqlite3

paths = [
    r"C:\Users\asdasd\.buzz\archive\archive.db",
    r"C:\Users\asdasd\.buzz-dev\archive\archive.db",
]

for p in paths:
    print(f"=== {p} ===")
    try:
        conn = sqlite3.connect(f"file:{p}?mode=ro", uri=True)
        cur = conn.cursor()
        # consent rows (scope_type owner_p) with kinds
        for row in cur.execute("SELECT scope_type, scope_value, kinds, created_at FROM save_subscriptions ORDER BY created_at"):
            print(f"  consent: scope_type={row[0]} kinds={row[2]} created_at={row[3]}")
        # 24200 frames
        n24200 = cur.execute("SELECT COUNT(*) FROM archived_events WHERE kind = 24200").fetchone()[0]
        print(f"  archived_events kind=24200: {n24200}")
        # recent activity (any kind) to tell which nest is live
        recent = cur.execute("SELECT kind, COUNT(*), MAX(created_at) FROM archived_events GROUP BY kind ORDER BY MAX(created_at) DESC LIMIT 5").fetchall()
        print(f"  recent archived_events by kind (kind, count, max_created_at): {recent}")
        conn.close()
    except Exception as e:
        print(f"  error: {e}")

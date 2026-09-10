import sqlite3, sys

paths = [
    r"C:\Users\asdasd\.buzz\archive\archive.db",
    r"C:\Users\asdasd\.buzz-dev\archive\archive.db",
    r"C:\Users\asdasd\.buzz-demo-s16test5\archive\archive.db",
]

for p in paths:
    print(f"=== {p} ===")
    try:
        conn = sqlite3.connect(f"file:{p}?mode=ro", uri=True)
        cur = conn.cursor()
        # distinct identity_pubkey in save_subscriptions
        try:
            rows = cur.execute("SELECT DISTINCT identity_pubkey FROM save_subscriptions").fetchall()
            print(f"  save_subscriptions distinct identity_pubkey: {[r[0] for r in rows]}")
        except Exception as e:
            print(f"  save_subscriptions error: {e}")
        # distinct identity_pubkey in archived_events
        try:
            rows = cur.execute("SELECT DISTINCT identity_pubkey FROM archived_events").fetchall()
            print(f"  archived_events distinct identity_pubkey: {[r[0] for r in rows]}")
        except Exception as e:
            print(f"  archived_events error: {e}")
        conn.close()
    except Exception as e:
        print(f"  open error: {e}")

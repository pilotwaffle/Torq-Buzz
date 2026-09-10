#!/usr/bin/env python3
"""S16 Test 5 - fresh-identity archive posture (throwaway, outside repo).

Reads the local archive SQLite DB read-only and reports the two consent/frame
facts the runbook (OPERATOR-RUNBOOK.md §4) judges:

  consent = save_subscriptions rows where scope_type='owner_p'
            (expect EMPTY pre-opt-in, PRESENT post-opt-in)
  frames  = archived_events rows where kind=24200
            (expect EMPTY pre-opt-in, PRESENT post-opt-in)

Schema (desktop/src-tauri/src/archive/store.rs):
  save_subscriptions(identity_pubkey, relay_url, scope_type, scope_value,
                     kinds, created_at)  PK = (identity_pubkey, relay_url,
                     scope_type, scope_value)
  archived_events(identity_pubkey, relay_url, id, kind, created_at, raw_json)
                  PK = (identity_pubkey, relay_url, id)

Admission refusal (desktop/src-tauri/src/archive/mod.rs:216,283): a kind-24200
frame is refused when there is no matching owner_p save subscription
('no owner_p subscription for scope_value=...'). Pre-opt-in, this refusal means
frames are never written to archived_events - which the empty frames query
observes.

Usage:
  python s16-test5-archive-posture.py <archive.db> [phase-label]

Exit 0 always (report-only); PASS/FAIL is interpreted by the caller from the
printed state against the expected pre/post phase.
"""

import sys
import sqlite3

QUERIES = {
    # NOTE: scope_type='owner_p' is shared by BOTH archives' consent (24200 agent
    # activity history AND 44200 agent turn metrics) because they key on the same
    # (identity, relay, owner_p, owner_pubkey) row and MERGE kinds. So this coarse
    # query can show n=1 from the 44200 metric consent alone; the precise 24200
    # consent is the next query.
    "consent (save_subscriptions scope_type='owner_p')": (
        "SELECT identity_pubkey, relay_url, scope_type, scope_value, kinds, created_at "
        "FROM save_subscriptions WHERE scope_type = 'owner_p' ORDER BY created_at"
    ),
    "24200 consent (owner_p kinds containing 24200)": (
        "SELECT identity_pubkey, relay_url, scope_value, kinds, created_at "
        "FROM save_subscriptions WHERE scope_type = 'owner_p' AND kinds LIKE '%24200%' "
        "ORDER BY created_at"
    ),
    "frames (archived_events kind=24200)": (
        "SELECT identity_pubkey, relay_url, id, kind, created_at "
        "FROM archived_events WHERE kind = 24200 ORDER BY created_at"
    ),
}


def main():
    db = sys.argv[1]
    phase = sys.argv[2] if len(sys.argv) > 2 else "?"

    conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row

    tables = [r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    )]
    print(f"archive.db = {db}")
    print(f"phase = {phase}")
    print(f"tables = {tables}")
    print()

    for label, sql in QUERIES.items():
        rows = conn.execute(sql).fetchall()
        print(f"### {label}  ->  n = {len(rows)}")
        if rows:
            cols = rows[0].keys()
            print("  " + " | ".join(cols))
            for r in rows:
                print("  " + " | ".join(str(r[c]) for c in cols))
        else:
            print("  (empty)")
        print()

    conn.close()


if __name__ == "__main__":
    main()

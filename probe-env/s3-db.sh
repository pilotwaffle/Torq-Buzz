#!/usr/bin/env bash
# Slice 3 gate: dump routine-related rows from the live relay DB (read-only).
q() { docker exec torq-buzz-postgres-1 psql -U buzz -d buzz -Atc "$1"; }
echo "== now: $(date -u +%FT%TZ)"
echo "== workflows (s3-gate*)"; q "select id, name, enabled, definition->>'enabled' as json_enabled, status from workflows where name like 's3-gate%' order by created_at"
echo "== scheduled_workflow_fires (last 6)"; q "select workflow_id, scheduled_for, claimed_at from scheduled_workflow_fires order by scheduled_for desc limit 6"
echo "== routine_dispatches"; q "select run_id, workflow_id, encode(wake_event_id,'hex') as wake, dispatched_at, settled_at, outcome, idempotency_key from routine_dispatches order by dispatched_at desc limit 10"
echo "== routine_state"; q "select workflow_id, consecutive_failures, last_fired_at, last_outcome, paused_reason, daily_notice_day from routine_state"
echo "== workflow_runs (last 6)"; q "select id, workflow_id, status, error_code, started_at, completed_at from workflow_runs order by started_at desc limit 6"

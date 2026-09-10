"""S16 spike — Test 4 A3.5 live element.

Drive ONE delegated prompt through a real `claude-agent-acp` ACP session over
stdio (NDJSON JSON-RPC 2.0) and capture the target's ORDINARY approval-gate
artifact: the `session/request_permission` frame. Throwaway; do not merge.

The permission gate is forced on via `session/set_config_option`
`{configId:"mode", value:"default"}` (per-tool-call permission), and the
delegated prompt induces a permission-requiring file write.

Loads ANTHROPIC_API_KEY from E:\\TORQ-CONSOLE\\.env into the child env only;
the key value is never printed.
"""

import json
import os
import queue
import subprocess
import sys
import threading
import time

ENV_FILE = r"E:\TORQ-CONSOLE\.env"
OUT_FILE = r"E:\TORQ-BUZZ\probe-env\s16-a35-delegated-prompt-output.txt"
TIMEOUT_SECONDS = 120


def load_env_key(path, name):
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            if k.strip() == name:
                return v.strip().strip('"').strip("'")
    return None


def main():
    key = load_env_key(ENV_FILE, "ANTHROPIC_API_KEY")
    if not key:
        print("FAIL: ANTHROPIC_API_KEY not found in", ENV_FILE)
        return 2

    env = dict(os.environ)
    env["ANTHROPIC_API_KEY"] = key

    print("spawning claude-agent-acp ...")
    proc = subprocess.Popen(
        ["cmd", "/c", "claude-agent-acp"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )

    # Reader thread → queue, so read_line() can time out instead of blocking
    # forever on a live-but-idle agent.
    q = queue.Queue()

    def reader():
        for raw in proc.stdout:
            q.put(raw)
        q.put(None)

    threading.Thread(target=reader, daemon=True).start()

    def drain_err():
        errs = []
        for raw in proc.stderr:
            errs.append(raw.rstrip("\n"))
        return errs

    err_box = []
    threading.Thread(target=lambda: err_box.extend(drain_err()), daemon=True).start()

    def read_line(timeout):
        try:
            return q.get(timeout=timeout)
        except queue.Empty:
            return None

    with open(OUT_FILE, "w", encoding="utf-8") as out:
        out.write("S16 A3.5 — claude-agent-acp delegated-prompt drive (NDJSON)\n")
        out.write(
            "started_utc=%s\n\n"
            % time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        )

        def send(obj):
            line = json.dumps(obj, separators=(",", ":"))
            out.write(">>> " + line + "\n")
            out.flush()
            proc.stdin.write(line + "\n")
            proc.stdin.flush()

        def next_msg(timeout):
            raw = read_line(timeout)
            if raw is None:
                return None
            raw = raw.rstrip("\n")
            if not raw.strip():
                return None
            out.write("<<< " + raw + "\n")
            out.flush()
            try:
                return json.loads(raw)
            except json.JSONDecodeError:
                return None

        def wait_for_id(rid, timeout=60):
            deadline = time.time() + timeout
            while time.time() < deadline:
                msg = next_msg(int(deadline - time.time()))
                if msg is None:
                    if proc.poll() is not None:
                        return None
                    continue
                if msg.get("id") == rid:
                    return msg
            return None

        # initialize (id 0)
        send({
            "jsonrpc": "2.0", "id": 0, "method": "initialize",
            "params": {
                "protocolVersion": 2,
                "clientCapabilities": {
                    "fs": {"readTextFile": False, "writeTextFile": False},
                },
                "clientInfo": {"name": "s16-a35-probe", "version": "0.0.0"},
            },
        })
        wait_for_id(0)

        # session/new (id 1)
        send({
            "jsonrpc": "2.0", "id": 1, "method": "session/new",
            "params": {"cwd": r"E:\TORQ-BUZZ\probe-env", "mcpServers": []},
        })
        session_id = None
        resp = wait_for_id(1)
        if isinstance(resp, dict) and isinstance(resp.get("result"), dict):
            session_id = resp["result"].get("sessionId")

        if not session_id:
            out.write("\nFAIL: no sessionId from session/new\n")
            print("FAIL: no sessionId from session/new")
            proc.kill()
            return 1

        out.write("\nsessionId=%s\n\n" % session_id)

        # Force the ordinary permission gate ON (per-tool-call permission).
        send({
            "jsonrpc": "2.0", "id": 2, "method": "session/set_config_option",
            "params": {"sessionId": session_id, "configId": "mode",
                       "value": "default"},
        })
        wait_for_id(2)

        # session/prompt (id 3) — delegated prompt inducing a file write.
        delegated = (
            "Create a file named `s16-a35-probe.txt` in the current working "
            "directory containing the text `s16-a35-approval-gate-probe`, then "
            "tell me it succeeded."
        )
        send({
            "jsonrpc": "2.0", "id": 3, "method": "session/prompt",
            "params": {
                "sessionId": session_id,
                "prompt": [{"type": "text", "text": delegated}],
            },
        })

        artifact = None
        stop_reason = None
        answered = False
        deadline = time.time() + TIMEOUT_SECONDS
        while time.time() < deadline:
            remaining = int(deadline - time.time()) + 1
            msg = next_msg(remaining)
            if msg is None:
                break
            method = msg.get("method")
            if method == "session/request_permission":
                artifact = msg
                params = msg.get("params", {})
                req_id = msg.get("id")
                options = params.get("options", [])
                allow = next(
                    (o for o in options if o.get("kind") == "allow_once"),
                    options[0] if options else {},
                )
                option_id = allow.get("optionId")
                out.write("\n>>> [permission answer] allow_once optionId=" +
                          str(option_id) + "\n")
                if req_id is not None:
                    send({
                        "jsonrpc": "2.0", "id": req_id,
                        "result": {"outcome": {
                            "outcome": "selected", "optionId": option_id,
                        }},
                    })
                    answered = True
            if msg.get("id") == 3 and isinstance(msg.get("result"), dict):
                if "stopReason" in msg["result"]:
                    stop_reason = msg["result"]["stopReason"]
                    break  # turn finished; stop reading

        out.write("\n--- summary ---\n")
        out.write("permission_artifact_captured=%s\n" % (artifact is not None))
        out.write("permission_answered=%s\n" % answered)
        out.write("stop_reason=%s\n" % stop_reason)
        if err_box:
            out.write("--- stderr (first 20 lines) ---\n")
            for ln in err_box[:20]:
                out.write(ln + "\n")

        # Kill the whole process tree (cmd + node), not just the shim.
        subprocess.run(
            ["taskkill", "/F", "/T", "/PID", str(proc.pid)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    if artifact is not None:
        print("PASS: ordinary approval-gate artifact captured; stopReason=",
              stop_reason)
        return 0
    print("FAIL: no session/request_permission artifact captured; see", OUT_FILE)
    return 1


if __name__ == "__main__":
    sys.exit(main())

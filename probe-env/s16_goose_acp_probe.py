"""S16 spike — drive `goose acp` directly over stdio NDJSON to capture the
EXACT error that makes buzz-acp emit `turn_error`.

Throwaway; do not merge. Do NOT print API keys — redact any known secret value
before writing output.

Adapted from s16_a35_delegated_prompt.py (which drives claude-agent-acp), but
spawns goose.exe directly (a real .exe) and captures EVERY stdout line (not just
matching ids) so notifications, errors, and error codes are all visible.
"""

import json
import os
import queue
import subprocess
import sys
import threading
import time

GOOSE = r"C:\Users\asdasd\.local\bin\goose.exe"
OUT_FILE = r"E:\TORQ-BUZZ\probe-env\s16-goose-acp-probe-output.txt"
TIMEOUT_SECONDS = 60

# Known secret values to redact from captured output. Populated at runtime from
# the environment (never printed). We redact by exact value.
_SECRET_VALUES = []


def collect_secrets():
    for name in ("OPENAI_API_KEY", "DEEPSEEK_API_KEY", "ANTHROPIC_API_KEY",
                 "GOOGLE_API_KEY", "GROQ_API_KEY", "AZURE_OPENAI_API_KEY"):
        v = os.environ.get(name)
        if v and len(v) > 6:
            _SECRET_VALUES.append(v)


def redact(text):
    for s in _SECRET_VALUES:
        text = text.replace(s, "<REDACTED:%s>" % ("key"))
    return text


def main():
    collect_secrets()

    env = dict(os.environ)
    env.setdefault("GOOSE_MODE", "auto")

    proc = subprocess.Popen(
        [GOOSE, "acp"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )

    q = queue.Queue()

    def reader():
        for raw in proc.stdout:
            q.put(raw)
        q.put(None)

    threading.Thread(target=reader, daemon=True).start()

    err_box = []

    def drain_err():
        for raw in proc.stderr:
            err_box.append(raw.rstrip("\n"))

    threading.Thread(target=drain_err, daemon=True).start()

    def read_line(timeout):
        try:
            return q.get(timeout=timeout)
        except queue.Empty:
            return None

    with open(OUT_FILE, "w", encoding="utf-8") as out:
        out.write("S16 — goose acp direct stdio drive (NDJSON)\n")
        out.write("started_utc=%s\n\n"
                  % time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))

        def send(obj):
            line = json.dumps(obj, separators=(",", ":"))
            out.write(">>> " + redact(line) + "\n")
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
            out.write("<<< " + redact(raw) + "\n")
            out.flush()
            try:
                return json.loads(raw)
            except json.JSONDecodeError:
                out.write("    [non-JSON line above]\n")
                return {"__nonjson__": raw}

        # 1. initialize (id 0)
        send({
            "jsonrpc": "2.0", "id": 0, "method": "initialize",
            "params": {
                "protocolVersion": 2,
                "clientCapabilities": {
                    "fs": {"readTextFile": False, "writeTextFile": False},
                },
                "clientInfo": {"name": "s16-goose-probe", "version": "0.0.0"},
            },
        })
        out.write("\n--- waiting for initialize response (id 0) ---\n")
        init_resp = None
        deadline = time.time() + 30
        while time.time() < deadline:
            msg = next_msg(int(deadline - time.time()))
            if msg is None:
                if proc.poll() is not None:
                    out.write("    [process exited code=%s]\n" % proc.poll())
                    break
                continue
            if msg.get("id") == 0:
                init_resp = msg
                break
        out.write("\ninitialize_response=%s\n" % redact(json.dumps(init_resp)))

        # 2. session/new (id 1)
        send({
            "jsonrpc": "2.0", "id": 1, "method": "session/new",
            "params": {"cwd": r"E:\TORQ-BUZZ\probe-env", "mcpServers": []},
        })
        out.write("\n--- waiting for session/new response (id 1) ---\n")
        session_id = None
        new_resp = None
        deadline = time.time() + 30
        while time.time() < deadline:
            msg = next_msg(int(deadline - time.time()))
            if msg is None:
                if proc.poll() is not None:
                    out.write("    [process exited code=%s]\n" % proc.poll())
                    break
                continue
            if msg.get("id") == 1:
                new_resp = msg
                if isinstance(msg.get("result"), dict):
                    session_id = msg["result"].get("sessionId")
                break
        out.write("\nsession_new_response=%s\n" % redact(json.dumps(new_resp)))
        out.write("sessionId=%s\n" % session_id)

        if not session_id:
            out.write("\nFAIL: no sessionId from session/new\n")
            out.write("--- stderr so far ---\n")
            for ln in err_box:
                out.write(redact(ln) + "\n")
            proc.kill()
            return 1

        # 3. session/prompt (id 2)
        send({
            "jsonrpc": "2.0", "id": 2, "method": "session/prompt",
            "params": {
                "sessionId": session_id,
                "prompt": [{"type": "text", "text": "Say hello in one word."}],
            },
        })
        out.write("\n--- waiting for session/prompt response (id 2) ---\n")
        out.write("--- (capturing ALL frames until turn ends or timeout) ---\n")
        prompt_resp = None
        deadline = time.time() + TIMEOUT_SECONDS
        while time.time() < deadline:
            msg = next_msg(int(deadline - time.time()))
            if msg is None:
                if proc.poll() is not None:
                    out.write("    [process exited code=%s]\n" % proc.poll())
                    break
                continue
            if msg.get("id") == 2:
                prompt_resp = msg
                # A turn-completing session/prompt result carries stopReason.
                if isinstance(msg.get("result"), dict) and "stopReason" in msg["result"]:
                    out.write("    [turn finished: stopReason=%s]\n"
                              % msg["result"]["stopReason"])
                    break
                # An error result (no stopReason) — capture and break.
                if msg.get("error"):
                    out.write("    [error frame received]\n")
                    break
                # result without stopReason could be an interim ack; keep reading.
            if isinstance(msg, dict) and msg.get("error"):
                out.write("    [error frame received (id=%s)]\n" % msg.get("id"))
                break

        out.write("\nprompt_response=%s\n" % redact(json.dumps(prompt_resp)))

        # Drain any remaining frames for up to 3s so late notifications surface.
        out.write("\n--- draining remaining frames (3s) ---\n")
        drain_deadline = time.time() + 3
        while time.time() < drain_deadline:
            msg = next_msg(int(drain_deadline - time.time()))
            if msg is None:
                break
            if msg.get("id") == 2:
                prompt_resp = msg
                out.write("    [updated id=2 frame]\n")

        out.write("\n--- stderr ---\n")
        for ln in err_box:
            out.write(redact(ln) + "\n")
        out.write("\n--- process state ---\n")
        out.write("poll=%s\n" % proc.poll())

        subprocess.run(
            ["taskkill", "/F", "/T", "/PID", str(proc.pid)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())

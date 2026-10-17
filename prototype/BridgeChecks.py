"""Offline process checks for the new hook bridge. No GUI, Claude, or OpenAI."""
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

HERE = Path(__file__).resolve().parent
BINARY = HERE / ".build" / "maie-hook"
SWIFT_EPOCH = 978307200


def write(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value), encoding="utf-8")
    temporary.replace(path)


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def timestamp():
    return time.time() - SWIFT_EPOCH


def payload(session, tool):
    return {
        "hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion",
        "session_id": session, "tool_use_id": tool, "cwd": "/tmp/fictional-project",
        "tool_input": {"unknown": {"preserve": True}, "questions": [{
            "question": "Choose a harmless test phrase.", "multiSelect": False,
            "options": [{"label": "First", "description": "One"},
                        {"label": "Second", "description": "Two"}]}]},
    }


def start(root, session, tool, timeout=5):
    env = dict(os.environ, MAIE_DATA_DIR=str(root))
    process = subprocess.Popen([str(BINARY), "--timeout-seconds", str(timeout)],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, env=env)
    process.stdin.write(json.dumps(payload(session, tool)).encode())
    process.stdin.close()
    return process


def result(process):
    process.wait(timeout=8)
    output = process.stdout.read()
    assert process.returncode == 0 and not process.stderr.read()
    lines = output.splitlines()
    assert len(lines) == 1
    return json.loads(lines[0])


def packet(root, known=()):
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        for folder in (root / "bridge").iterdir():
            if folder.is_dir() and folder.name not in known and (folder / "heartbeat.json").exists():
                return folder, read(folder / "request.json")
        time.sleep(0.02)
    raise AssertionError("No hook packet")


def deny(value):
    assert value["continue"] is False
    specific = value["hookSpecificOutput"]
    assert specific["permissionDecision"] == "deny" and "updatedInput" not in specific


with tempfile.TemporaryDirectory(prefix="maie-bridge-checks-") as temporary:
    root = Path(temporary)
    bridge = root / "bridge"
    bridge.mkdir()
    run_id = str(uuid.uuid4()).upper()

    def lease(run=run_id):
        write(bridge / "service.json", {"runID": run, "pid": os.getpid(), "touched": timestamp()})

    lease()
    first = start(root, "session-first", "tool-first")
    second = start(root, "session-second", "tool-second")
    folder_a, envelope_a = packet(root)
    folder_b, envelope_b = packet(root, [folder_a.name])
    packets = {json.loads(base64.b64decode(e["payload"]))["session_id"]: (f, e)
               for f, e in [(folder_a, envelope_a), (folder_b, envelope_b)]}
    # Keep multilingual coverage as escapes in English source.
    exact = '  \u0394\u03b9\u03ba\u03ae \u03bc\u03bf\u03c5\n"quotes" $(literal) \U0001fae7\n'
    for session, answer in [("session-second", "SECOND-ONLY"), ("session-first", exact)]:
        folder, envelope = packets[session]
        tool = "tool-second" if session == "session-second" else "tool-first"
        write(folder / "decision.json", {"id": envelope["id"], "sessionID": session,
                                         "toolUseID": tool, "answer": answer})
    out_a, out_b = result(first), result(second)
    for output, answer in [(out_a, exact), (out_b, "SECOND-ONLY")]:
        specific = output["hookSpecificOutput"]
        assert specific["permissionDecision"] == "allow"
        assert specific["updatedInput"]["answers"] == {"Choose a harmless test phrase.": answer}
        assert specific["updatedInput"]["unknown"] == {"preserve": True}
    for folder, envelope in packets.values():
        assert read(folder / "receipt.json") == {"id": envelope["id"], "submitted": True}

    known = [f.name for f in bridge.iterdir() if f.is_dir()]
    lease()
    timed = start(root, "session-timeout", "tool-timeout", 0.3)
    timeout_folder, _ = packet(root, known)
    deny(result(timed))
    known.append(timeout_folder.name)

    lease()
    wrong = start(root, "session-wrong", "tool-wrong")
    folder, envelope = packet(root, known)
    write(folder / "decision.json", {"id": envelope["id"], "sessionID": "different-session",
                                     "toolUseID": "tool-wrong", "answer": "MUST-NOT-SEND"})
    deny(result(wrong))
    known.append(folder.name)

    lease()
    restarted = start(root, "session-restart", "tool-restart")
    folder, _ = packet(root, known)
    lease(str(uuid.uuid4()).upper())
    deny(result(restarted))
    known.append(folder.name)

    lease()
    cancelled = start(root, "session-cancel", "tool-cancel")
    folder, envelope = packet(root, known)
    write(folder / "decision.json", {"id": envelope["id"], "sessionID": "session-cancel", "toolUseID": "tool-cancel"})
    deny(result(cancelled))
    (bridge / "service.json").unlink()
    deny(result(start(root, "session-offline", "tool-offline")))

print("Bridge process checks passed: concurrent routing, exact text, original input, receipt, timeout, wrong-session rejection, service restart, cancellation, app offline.")

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


def payload(session, tool, question_count=1):
    value = {
        "hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion",
        "session_id": session, "tool_use_id": tool, "cwd": "/tmp/fictional-project",
        "tool_input": {"unknown": {"preserve": True}, "questions": [{
            "question": "Choose a harmless test phrase.", "multiSelect": False,
            "options": [{"label": "First", "description": "One"},
                        {"label": "Second", "description": "Two"}]}]},
    }
    if question_count > 1:
        base = value["tool_input"]["questions"][0]
        value["tool_input"]["questions"] = [dict(base, question=f"Question {index + 1}?", multiSelect=index == 1)
                                                for index in range(question_count)]
    return value


def start(root, session, tool, timeout=5, question_count=1):
    env = dict(os.environ, MAIE_DATA_DIR=str(root))
    process = subprocess.Popen([str(BINARY), "--timeout-seconds", str(timeout)],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, env=env)
    process.stdin.write(json.dumps(payload(session, tool, question_count)).encode())
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


def start_raw(root, body):
    """Send an arbitrary stdin body; used for payloads the helper must reject."""
    env = dict(os.environ, MAIE_DATA_DIR=str(root))
    process = subprocess.Popen([str(BINARY), "--timeout-seconds", "5"],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, env=env)
    process.stdin.write(body)
    process.stdin.close()
    return process


def keys(value):
    if isinstance(value, dict):
        for key, inner in value.items():
            yield key
            yield from keys(inner)
    elif isinstance(value, list):
        for inner in value:
            yield from keys(inner)


# Every deny must tell Claude that the human never answered, that no option
# (including a recommended one) is chosen, and that a later generic reply is not
# an answer. An earlier deny text left this unsaid and a "(Recommended)" option
# was executed after the human typed "continue".
FAIL_SAFE_PHRASES = (
    "did not see or answer this question",
    "no answer was sent",
    '"(Recommended)"',
    "do not proceed with any option",
    '"continue"',
    "is not an answer to this question and not an authorization",
    "Ask again with AskUserQuestion once Maie is open",
    "explicit answer that names the chosen option",
)


def deny(value):
    assert value["continue"] is False
    assert set(value) == {"continue", "stopReason", "hookSpecificOutput"}
    specific = value["hookSpecificOutput"]
    assert specific["permissionDecision"] == "deny"
    assert specific["hookEventName"] == "PreToolUse"
    assert "updatedInput" not in set(keys(value)) and "answers" not in set(keys(value))
    reason = specific["permissionDecisionReason"]
    assert reason == value["stopReason"]
    for phrase in FAIL_SAFE_PHRASES:
        assert phrase in reason, phrase


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
    # Two complete sets may wait at once, with the same question keys but isolated answers.
    known = [f.name for f in bridge.iterdir() if f.is_dir()]
    lease()
    batch_a = start(root, "batch-a", "tool-batch-a", question_count=4)
    batch_b = start(root, "batch-b", "tool-batch-b", question_count=4)
    folder_a, envelope_a = packet(root, known)
    folder_b, envelope_b = packet(root, known + [folder_a.name])
    packets = {json.loads(base64.b64decode(e["payload"]))["session_id"]: (f, e)
               for f, e in [(folder_a, envelope_a), (folder_b, envelope_b)]}
    expected_answers = {}
    for session, tool in [("batch-b", "tool-batch-b"), ("batch-a", "tool-batch-a")]:
        folder, envelope = packets[session]
        answers = {f"Question {index + 1}?": f"{session}: {index}" for index in range(4)}
        # The encoded packet exceeds the former 32 KiB read bound while each answer stays valid.
        if session == "batch-a":
            answers["Question 1?"] = exact
            answers["Question 2?"] = '"' * 8_192
            answers["Question 3?"] = '"' * 8_192
            answers["Question 4?"] = '"' * 8_192
        expected_answers[session] = answers
        write(folder / "decision.json", {"id": envelope["id"], "sessionID": session,
                                         "toolUseID": tool, "answers": answers})
    for session, tool, process in [("batch-a", "tool-batch-a", batch_a), ("batch-b", "tool-batch-b", batch_b)]:
        output = result(process)["hookSpecificOutput"]
        assert output["permissionDecision"] == "allow"
        assert output["updatedInput"]["answers"] == expected_answers[session]
        assert output["updatedInput"]["questions"] == payload(session, tool, 4)["tool_input"]["questions"]
        assert output["updatedInput"]["unknown"] == {"preserve": True}
        folder, envelope = packets[session]
        assert read(folder / "receipt.json") == {"id": envelope["id"], "submitted": True}

    known = [f.name for f in bridge.iterdir() if f.is_dir()]
    lease()
    partial = start(root, "partial-batch", "tool-partial-batch", question_count=4)
    folder, envelope = packet(root, known)
    write(folder / "decision.json", {"id": envelope["id"], "sessionID": "partial-batch", "toolUseID": "tool-partial-batch",
                                     "answers": {"Question 1?": "Partial"}})
    deny(result(partial))

    # Without a lease Maie is not running: the helper returns no decision (an empty
    # JSON object, exit code 0) so Claude Code shows its own prompt, and creates no packet.
    (bridge / "service.json").unlink()
    before = sorted(f.name for f in bridge.iterdir() if f.is_dir())
    assert result(start(root, "session-offline", "tool-offline")) == {}
    assert sorted(f.name for f in bridge.iterdir() if f.is_dir()) == before

    # Invalid payloads must produce the same fail-safe deny, with or without a lease.
    lease()
    before = sorted(f.name for f in bridge.iterdir() if f.is_dir())
    empty = payload("session-invalid", "tool-invalid")
    empty["tool_input"]["questions"] = []
    for body in [json.dumps(empty).encode(), b"not json {"]:
        deny(result(start_raw(root, body)))
    assert sorted(f.name for f in bridge.iterdir() if f.is_dir()) == before

print("Bridge process checks passed: concurrent routing, exact text, original input, receipt, timeout, wrong-session rejection, service restart, cancellation, app offline pass-through, simultaneous four-question sets, large complete packets, partial-set rejection, invalid payload and fail-safe deny wording.")

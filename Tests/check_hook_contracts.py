#!/usr/bin/env python3
"""Exercise the actual passive hook and explicit installers using disposable local files."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]).resolve()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


with tempfile.TemporaryDirectory(prefix="char hook's contracts ") as directory:
    root = Path(directory)
    events = root / "shared events.jsonl"
    for harness in ("claude", "codex"):
        settings = root / f"{harness}.json"
        original_handler = {"type": "command", "command": "existing-user-hook"}
        settings.write_text(json.dumps({"custom_setting": "preserve", "hooks": {
            "Stop": [{"hooks": [original_handler]}]}}))
        flag = "--settings" if harness == "claude" else "--hooks"
        install = [sys.executable, str(repo / f"integrations/{harness}/install.py"),
                   flag, str(settings), "--hook-binary", str(binary), "--events-file", str(events)]
        subprocess.run(install, check=True)
        first = settings.read_bytes()
        subprocess.run(install, check=True)
        require(settings.read_bytes() == first, f"{harness} installer duplicated handlers")
        configuration = json.loads(first)
        require(configuration["custom_setting"] == "preserve", "installer lost an unrelated preference")
        require(configuration["hooks"]["Stop"][0]["hooks"][0] == original_handler,
                "installer changed an existing hook")
        command = configuration["hooks"]["PermissionRequest"][-1]["hooks"][0]["command"]
        transcript = root / f"{harness}-session.jsonl"
        transcript.write_text(json.dumps({"type": "session_meta", "payload": {
            "id": harness, "originator": "Codex Desktop", "source": "vscode", "thread_source": "user"}}) + "\n")
        payload = {"session_id": harness, "transcript_path": str(transcript),
                   "hook_event_name": "PermissionRequest", "tool_name": "Bash",
                   "tool_input": {"command": "private-command-sentinel"},
                   "last_assistant_message": "private-response-sentinel"}
        result = subprocess.run(command, shell=True, input=json.dumps(payload), text=True,
                                capture_output=True, check=True)
        require(result.stdout == "" and result.stderr == "", "passive hook produced harness-facing output")
    content = events.read_text()
    records = [json.loads(line) for line in content.splitlines()]
    require(len(records) == 2, "shared hook stream did not receive both harnesses")
    require([item["key"]["workEnd"] for item in records] == ["claudeCode", "codexDesktop"],
            "hook stream lost work-end identity")
    require(all("stopped" in item["state"] for item in records), "permission request was not observed")
    require("private-command-sentinel" not in content and "private-response-sentinel" not in content,
            "hook persisted source content")
    require(events.stat().st_mode & 0o777 == 0o600, "normalized event file is not private")
    environment = dict(os.environ, CHAR_HOOK_EVENTS=str(events))
    subprocess.run([str(binary)], input=b'{"hook_event_name":"unknown"}', env=environment, check=True)
    require(events.read_text() == content, "unsupported input created an observation")
print("Hooks: both installers preserve settings and are idempotent; shared passive stream and privacy passed")

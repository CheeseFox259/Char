#!/usr/bin/env python3
"""Run real native adapters/installers against disposable metadata only."""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib

repo = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]).resolve()

with tempfile.TemporaryDirectory(prefix="char new agent's contracts ") as directory:
    root = Path(directory)
    settings = root / "config.toml"
    stream = root / "events.jsonl"
    original = '# Preserve comments\n[model_aliases]\ntest = "private-provider"\n\n[[hooks]]\nevent = "Stop"\ncommand = "existing-hook"\n'
    settings.write_text(original)
    command = [sys.executable, str(repo / "integrations/kimi/install.py"), "--settings", str(settings),
               "--hook-binary", str(binary), "--events-file", str(stream)]
    subprocess.run(command, check=True)
    first = settings.read_bytes()
    subprocess.run(command, check=True)
    assert settings.read_bytes() == first
    assert settings.read_text().startswith(original)
    config = tomllib.loads(settings.read_text())
    assert len(config["hooks"]) == 5
    assert config["hooks"][0]["command"] == "existing-hook"
    native_command = next(h["command"] for h in config["hooks"] if h["event"] == "SessionStart")
    result = subprocess.run(native_command, shell=True, input=json.dumps({
        "hook_event_name": "SessionStart", "session_id": "native-desktop", "client_type": "kimi_code_desktop",
        "session_title": "must not persist", "prompt": "private input", "cwd": "/private/path"}), text=True, check=True, capture_output=True)
    assert result.stdout == ""
    records = json.loads(stream.read_text())
    assert records["workEnd"] == "kimiDesktop" and records["schema"] == "char.kimi-hook.v1"
    assert not any(x in stream.read_text() for x in ["must not persist", "private input", "/private/path"])

    def invoke(index):
        env = dict(os.environ, CHAR_HOOK_EVENTS=str(stream))
        subprocess.run([str(binary), "--deepseek"], input=json.dumps({"client_type": "deepseek_desktop",
            "root_session": True, "session_id": f"root-{index}", "kind": "turnEnded", "time": 1800000000000,
            "prompt": "never retained"}), text=True, env=env, check=True, capture_output=True)

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(invoke, range(16)))
    lines = [json.loads(line) for line in stream.read_text().splitlines()]
    assert len(lines) == 17 and all(line.get("key", {}).get("workEnd") == "deepseekDesktop" for line in lines[1:])
    assert len({line["key"]["nativeID"] for line in lines[1:]}) == 16
    assert stream.stat().st_mode & 0o777 == 0o600
    assert "never retained" not in stream.read_text()
print("New Agent hooks: native adapter, Kimi installer idempotence/privacy, 16 concurrent locked writes passed")

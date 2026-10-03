#!/usr/bin/env python3
"""Explicitly merge char's command hooks into one Claude settings file."""
import argparse
import json
import os
import pathlib
import shlex
import tempfile

EVENTS = ("SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Elicitation", "ElicitationResult", "Notification", "Stop", "StopFailure", "SessionEnd")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--settings", type=pathlib.Path, required=True)
    parser.add_argument("--hook-binary", type=pathlib.Path, required=True)
    parser.add_argument("--events-file", type=pathlib.Path, required=True)
    args = parser.parse_args()
    if not args.hook_binary.is_file() or not os.access(args.hook_binary, os.X_OK):
        parser.error("--hook-binary must be an executable file")
    settings = json.loads(args.settings.read_text()) if args.settings.exists() else {}
    if not isinstance(settings, dict):
        parser.error("settings root must be a JSON object")
    hooks = settings.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        parser.error("hooks must be a JSON object")
    command = f"CHAR_HOOK_EVENTS={shlex.quote(str(args.events_file))} {shlex.quote(str(args.hook_binary))}"
    for event in EVENTS:
        entries = hooks.setdefault(event, [])
        if not isinstance(entries, list):
            parser.error(f"hooks.{event} must be an array")
        if any(isinstance(group, dict) and any(isinstance(handler, dict) and handler.get("command") == command
               for handler in group.get("hooks", [])) for group in entries):
            continue
        entries.append({"hooks": [{"type": "command", "command": command}]})
    args.settings.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".char-settings-", dir=args.settings.parent)
    try:
        with os.fdopen(descriptor, "w") as output:
            json.dump(settings, output, indent=2, ensure_ascii=False)
            output.write("\n")
        os.chmod(temporary, args.settings.stat().st_mode & 0o777 if args.settings.exists() else 0o600)
        os.replace(temporary, args.settings)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    main()

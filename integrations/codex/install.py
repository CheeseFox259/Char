#!/usr/bin/env python3
"""Explicitly merge char's passive hook handlers into one Codex hooks.json file."""
import argparse
import json
import os
import pathlib
import shlex
import tempfile

EVENTS = ("SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop", "Interrupt", "SessionEnd")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hooks", type=pathlib.Path, required=True)
    parser.add_argument("--hook-binary", type=pathlib.Path, required=True)
    parser.add_argument("--events-file", type=pathlib.Path, required=True)
    args = parser.parse_args()
    if not args.hook_binary.is_file() or not os.access(args.hook_binary, os.X_OK):
        parser.error("--hook-binary must be an executable file")
    settings = json.loads(args.hooks.read_text()) if args.hooks.exists() else {}
    if not isinstance(settings, dict):
        parser.error("hooks root must be a JSON object")
    hooks = settings.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        parser.error("hooks must be a JSON object")
    command = f"CHAR_HOOK_EVENTS={shlex.quote(str(args.events_file))} {shlex.quote(str(args.hook_binary))} --codex"
    for event in EVENTS:
        entries = hooks.setdefault(event, [])
        if not isinstance(entries, list):
            parser.error(f"hooks.{event} must be an array")
        if any(isinstance(group, dict) and any(isinstance(handler, dict) and handler.get("command") == command
               for handler in group.get("hooks", [])) for group in entries):
            continue
        entries.append({"hooks": [{"type": "command", "command": command}]})
    args.hooks.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".char-hooks-", dir=args.hooks.parent)
    try:
        with os.fdopen(descriptor, "w") as output:
            json.dump(settings, output, indent=2, ensure_ascii=False)
            output.write("\n")
        os.chmod(temporary, args.hooks.stat().st_mode & 0o777 if args.hooks.exists() else 0o600)
        os.replace(temporary, args.hooks)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    main()

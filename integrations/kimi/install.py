#!/usr/bin/env python3
"""Explicitly append Char's native Kimi hooks while preserving existing TOML."""
import argparse
import json
import os
import pathlib
import shlex
import tempfile
import tomllib

EVENTS = ("SessionStart", "PermissionRequest", "PermissionResult", "SessionEnd")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--settings", type=pathlib.Path, required=True)
    parser.add_argument("--hook-binary", type=pathlib.Path, required=True)
    parser.add_argument("--events-file", type=pathlib.Path, required=True)
    args = parser.parse_args()
    if not args.hook_binary.is_file() or not os.access(args.hook_binary, os.X_OK):
        parser.error("--hook-binary must be an executable file")
    text = args.settings.read_text() if args.settings.exists() else ""
    settings = tomllib.loads(text)
    hooks = settings.get("hooks", [])
    if not isinstance(hooks, list):
        parser.error("hooks must be an array of tables")
    command = f"CHAR_HOOK_EVENTS={shlex.quote(str(args.events_file))} {shlex.quote(str(args.hook_binary))} --kimi"
    for event in EVENTS:
        if any(isinstance(hook, dict) and hook.get("event") == event and hook.get("command") == command for hook in hooks):
            continue
        text += f"\n[[hooks]]\nevent = {json.dumps(event)}\ncommand = {json.dumps(command)}\ntimeout = 5\n"
    tomllib.loads(text)
    args.settings.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".char-kimi-", dir=args.settings.parent)
    try:
        with os.fdopen(descriptor, "w") as output:
            output.write(text)
        os.chmod(temporary, args.settings.stat().st_mode & 0o777 if args.settings.exists() else 0o600)
        os.replace(temporary, args.settings)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    main()

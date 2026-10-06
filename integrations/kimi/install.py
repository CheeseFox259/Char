#!/usr/bin/env python3
"""Explicitly append Char's native Kimi hooks while preserving existing TOML."""
import argparse
import json
import os
import pathlib
import re
import shlex
import tempfile
import tomllib

EVENTS = ("SessionStart", "PermissionRequest", "PermissionResult", "SessionEnd")


def is_char_command(command):
    """Recognize only the three-token command emitted by this installer."""
    if not isinstance(command, str):
        return False
    try:
        tokens = shlex.split(command)
    except ValueError:
        return False
    return (len(tokens) == 3 and tokens[0].startswith("CHAR_HOOK_EVENTS=")
            and pathlib.Path(tokens[1]).is_absolute()
            and pathlib.Path(tokens[1]).name == "char-hook" and tokens[2] == "--kimi")


def migrate_char_commands(text, command):
    # Keep every non-Char table and comment byte-for-byte. Historical installer
    # entries use JSON-quoted, single-line command values in [[hooks]] tables.
    headers = list(re.finditer(r"(?m)^[ \t]*(\[\[?[^\]\n]+\]\]?)[ \t]*(?:#.*)?$", text))
    for index in range(len(headers) - 1, -1, -1):
        header = headers[index]
        if header.group(1) != "[[hooks]]":
            continue
        end = headers[index + 1].start() if index + 1 < len(headers) else len(text)
        block = text[header.start():end]
        hook = tomllib.loads(block)["hooks"][0]
        old = hook.get("command")
        if hook.get("event") not in EVENTS or not is_char_command(old) or old == command:
            continue
        pattern = r"(?m)^([ \t]*command[ \t]*=[ \t]*)" + re.escape(json.dumps(old)) + r"([ \t]*(?:#.*)?)$"
        updated, count = re.subn(pattern, lambda m: m[1] + json.dumps(command) + m[2], block)
        if count != 1:
            raise ValueError("existing Char hook has a non-installer format; cannot migrate safely")
        text = text[:header.start()] + updated + text[end:]
    return text


def deduplicate_char_commands(text):
    headers = list(re.finditer(r"(?m)^[ \t]*(\[\[?[^\]\n]+\]\]?)[ \t]*(?:#.*)?$", text))
    seen = set()
    removed = []
    for index, header in enumerate(headers):
        if header.group(1) != "[[hooks]]":
            continue
        end = headers[index + 1].start() if index + 1 < len(headers) else len(text)
        hook = tomllib.loads(text[header.start():end])["hooks"][0]
        event = hook.get("event")
        if event in EVENTS and is_char_command(hook.get("command")):
            if event in seen:
                removed.append((header.start(), end))
            seen.add(event)
    for start, end in reversed(removed):
        text = text[:start] + text[end:]
    return text


def remove_char_commands(text):
    headers = list(re.finditer(r"(?m)^[ \t]*(\[\[?[^\]\n]+\]\]?)[ \t]*(?:#.*)?$", text))
    for index in range(len(headers) - 1, -1, -1):
        header = headers[index]
        if header.group(1) != "[[hooks]]":
            continue
        end = headers[index + 1].start() if index + 1 < len(headers) else len(text)
        hook = tomllib.loads(text[header.start():end])["hooks"][0]
        if hook.get("event") in EVENTS and is_char_command(hook.get("command")):
            text = text[:header.start()] + text[end:]
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--settings", type=pathlib.Path, required=True)
    parser.add_argument("--hook-binary", type=pathlib.Path, required=True)
    parser.add_argument("--events-file", type=pathlib.Path, required=True)
    parser.add_argument("--action", choices=("install", "inspect", "uninstall"), default="install")
    args = parser.parse_args()
    if not args.hook_binary.is_file() or not os.access(args.hook_binary, os.X_OK):
        parser.error("--hook-binary must be an executable file")
    text = args.settings.read_text() if args.settings.exists() else ""
    settings = tomllib.loads(text)
    hooks = settings.get("hooks", [])
    if not isinstance(hooks, list):
        parser.error("hooks must be an array of tables")
    command = f"CHAR_HOOK_EVENTS={shlex.quote(str(args.events_file))} {shlex.quote(str(args.hook_binary))} --kimi"
    if args.action == "inspect":
        ready = all(sum(h.get("event") == event and h.get("command") == command for h in hooks) == 1 for event in EVENTS)
        owned = [h for h in hooks if is_char_command(h.get("command"))]
        print(json.dumps({"status": "ready" if ready and len(owned) == len(EVENTS) else "notInstalled",
                          "detail": "Configuration matches; new/resumed client session is required." if ready else "Install or update the Char Kimi hooks."}))
        return
    if args.action == "uninstall":
        text = remove_char_commands(text)
    try:
        if args.action == "install":
            text = deduplicate_char_commands(migrate_char_commands(text, command))
    except ValueError as error:
        parser.error(str(error))
    hooks = tomllib.loads(text).get("hooks", [])
    for event in EVENTS if args.action == "install" else ():
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

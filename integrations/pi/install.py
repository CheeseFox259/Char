#!/usr/bin/env python3
"""Explicitly install Char's passive Pi extension in a selected directory."""
import argparse
import json
import os
from pathlib import Path
import shutil


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--extension-dir', type=Path, required=True)
    parser.add_argument('--hook-binary', type=Path, required=True)
    parser.add_argument('--events-file', type=Path, required=True)
    args = parser.parse_args()
    if not args.hook_binary.is_file() or not os.access(args.hook_binary, os.X_OK):
        parser.error('--hook-binary must be an executable file')
    marker = args.extension_dir / 'package.json'
    if args.extension_dir.exists() and any(args.extension_dir.iterdir()):
        try:
            owned = json.loads(marker.read_text()).get('name') == 'char-pi-observer'
        except (OSError, ValueError, AttributeError):
            owned = False
        if not owned:
            parser.error('--extension-dir must be empty or contain a Char Pi installation')
    args.extension_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    shutil.copyfile(Path(__file__).with_name('observer.mjs'), args.extension_dir / 'observer.mjs')
    # Source tree and installed app both keep the canonical writer in native/.
    shutil.copyfile(Path(__file__).parent.parent / 'native/event-writer.mjs', args.extension_dir / 'event-writer.mjs')
    (args.extension_dir / 'index.js').write_text(
        'import { createCharExtension } from "./observer.mjs";\nexport default createCharExtension(' +
        json.dumps({'hookBinary': str(args.hook_binary.resolve()),
                    'eventsFile': str(args.events_file.resolve())}, ensure_ascii=False) + ');\n')
    (args.extension_dir / 'package.json').write_text('{"name":"char-pi-observer","type":"module"}\n')
    for name in ('index.js', 'observer.mjs', 'event-writer.mjs', 'package.json'):
        (args.extension_dir / name).chmod(0o600)


if __name__ == '__main__':
    main()

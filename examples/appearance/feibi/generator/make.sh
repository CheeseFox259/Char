#!/bin/sh
# Works from any directory. SDK host must support synchronized tracking frames.
set -eu
WORK="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$WORK/../../.." && pwd)"
PYTHON="${PYTHON:-python3}"
"$PYTHON" "$WORK/generator/showcase.py"
"$PYTHON" "$WORK/generator/showcase_preview.py"
if [ -f "$ROOT/Package.swift" ]; then
    swift run --package-path "$ROOT" char-package-check skin "$WORK/packages/feibi.charpet"
fi

#!/bin/sh
# Rebuild the 菲比 charpet end to end: reference -> rig -> package -> previews -> audit.
#
# Works from any current directory: every path is resolved from this script, and the
# resolved package location is printed before anything is written.
#
#   ./generator/make.sh                      # uses the default package path
#   ./generator/make.sh /abs/other.charpet    # writes somewhere else
#
# Needs python3 with Pillow and numpy. Point PYTHON at an interpreter that has
# them; an isolated environment is fine:
#   python3 -m venv .venv && ./.venv/bin/pip install -r requirements.txt
#   PYTHON="$PWD/.venv/bin/python" ./generator/make.sh
#
# The production validator is only run when the Char SDK checkout is present.
set -eu

WORK="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$WORK/../../.." && pwd)"
PACKAGE="${1:-$WORK/packages/feibi.charpet}"
PYTHON="${PYTHON:-python3}"
case "$PACKAGE" in
    /*) ;;
    *) PACKAGE="$PWD/$PACKAGE" ;;
esac

echo "work     $WORK"
echo "package  $PACKAGE"
mkdir -p "$WORK/reports" "$WORK/preview"

"$PYTHON" "$WORK/generator/refprep.py" "$WORK" > /dev/null
"$PYTHON" "$WORK/generator/art.py" "$WORK" > /dev/null
"$PYTHON" "$WORK/generator/build.py" "$WORK" "$PACKAGE"
"$PYTHON" "$WORK/generator/preview.py" "$WORK" "$PACKAGE"
"$PYTHON" "$WORK/generator/inspect_package.py" "$PACKAGE" "$WORK/reports/package-audit.json" > /dev/null
echo "audit    PASS -> $WORK/reports/package-audit.json"

if [ -f "$ROOT/Package.swift" ]; then
    swift run --package-path "$ROOT" char-package-check skin "$PACKAGE"
else
    echo "validator skipped: no Char SDK at $ROOT"
fi

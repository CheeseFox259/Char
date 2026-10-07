#!/bin/sh
# Rebuild the 菲比 charpet from the reference image, end to end.
#
# Requirements: python3 with Pillow + numpy (PYTHON=... to point at an interpreter
# that has them), and the Char SDK checkout for the production validator only.
#
#   PYTHON=/path/to/python3 ./generator/make.sh
#
# Steps: key the reference -> build the art rig -> render clips, icon and
# manifest -> write offline previews -> audit format, transparency and budget.
set -eu

WORK="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$WORK/../../.." && pwd)"
PACKAGE="${1:-$WORK/packages/feibi.charpet}"
PYTHON="${PYTHON:-python3}"

mkdir -p "$WORK/reports" "$WORK/preview"
"$PYTHON" "$WORK/generator/refprep.py" "$WORK"
"$PYTHON" "$WORK/generator/art.py" "$WORK"
"$PYTHON" "$WORK/generator/build.py" "$WORK" "$PACKAGE"
"$PYTHON" "$WORK/generator/preview.py" "$WORK" "$PACKAGE"
"$PYTHON" "$WORK/generator/inspect_package.py" "$PACKAGE" "$WORK/reports/package-audit.json" > /dev/null

if [ -d "$ROOT/Sources" ]; then
    swift run --package-path "$ROOT" char-package-check skin "$PACKAGE"
fi
#!/bin/bash
# [DEBUG-char-wheel-deep] Opt-in isolated HITL capture. Run only when coordinating UI.
set -eu
app=${1:?Usage: capture-wheel-trace.sh /absolute/Char.app /tmp/trace.log}
trace=${2:?Provide output trace path}
printf '%s\n' 'In Settings choose Desktop and bubble distance 8 to enable folding.' 'Keep pointer on bubble ring: one down detent, wait one second, one up detent, wait; then rapid alternating detents.' 'Note each visible delayed or wrong-direction result before moving the pointer away. Quit this isolated Char to finish.'
CHAR_WHEEL_DIAGNOSTICS=1 "$app/Contents/MacOS/Char" --demo 2>"$trace"
python3 "$(dirname "$0")/analyze-wheel-trace.py" "$trace"

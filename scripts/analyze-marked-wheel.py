#!/usr/bin/env python3
"""Analyze saved diagnostic captures; live input instrumentation is no longer shipped."""
import json
import sys
from pathlib import Path

rows = []
for line in Path(sys.argv[1]).read_text().splitlines():
    if line.startswith("[DEBUG-char-wheel-deep] {"):
        rows.append(json.loads(line.split("] ", 1)[1]))
starts = [row["now"] for row in rows if row.get("kind") == "marker" and row.get("name") == "begin"]
ends = [row["now"] for row in rows if row.get("kind") == "marker" and row.get("name") == "heldEnd"]
if len(starts) != 1 or len(ends) != 1 or starts[0] >= ends[0]:
    print("INCOMPLETE: require one ordered begin/heldEnd pair")
    sys.exit(2)
held = [row for row in rows if starts[0] <= row.get("now", -1) <= ends[0]]
counts = {kind: sum(row.get("kind") == kind for row in held)
          for kind in ("rawHID", "rawSession", "ingressLocal", "input", "accepted")}
device_available = any(row.get("kind") == "deviceWheel" or
                       (row.get("kind") == "deviceObserver" and row.get("status") == 0) for row in rows)
counts["deviceWheel"] = sum(row.get("kind") == "deviceWheel" for row in held) if device_available else None
counts["deviceWheelNonzero"] = sum(row.get("kind") == "deviceWheel" and row.get("value", 0) != 0 for row in held) if device_available else None
verdict = "IN_WINDOW_STEP_RECEIVED" if counts["accepted"] == 1 else "FIRST_DETENT_MISSING" if counts["accepted"] == 0 else "EXTRA_STEPS"
print(json.dumps({"held_seconds": round(ends[0] - starts[0], 3), "counts": counts,
                  "verdict": verdict, "scope": "Marked physical input delivery only; does not certify screen animation."}, indent=2))
sys.exit(0 if counts["accepted"] == 1 else 1)

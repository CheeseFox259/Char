#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
swift run char-core-checks
swift run char-observation-checks
swift run char-platform-checks
if [[ -f "$repo_root/integrations/vscode/package.json" ]]; then
    npm --prefix "$repo_root/integrations/vscode" test
fi

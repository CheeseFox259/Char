#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
swift run char-plugin-checks
swift run char-core-checks
swift run char-observation-checks
swift run char-platform-checks
swift build --product char-hook
python3 Tests/check_hook_contracts.py "$(swift build --show-bin-path)/char-hook"
if [[ -f "$repo_root/integrations/vscode/package.json" ]]; then
    npm --prefix "$repo_root/integrations/vscode" test
fi
node "$repo_root/integrations/pi/observer.test.mjs"
python3 Tests/check_new_agent_hooks.py "$(swift build --show-bin-path)/char-hook"
node --test integrations/deepseek/index.test.js

node integrations/native/event-writer.test.mjs "$(swift build --show-bin-path)/char-hook"
node integrations/native/adapter.test.mjs "$(swift build --show-bin-path)/char-hook"

swift build --product char-appearance-script
python3 Tests/check_appearance_script.py "$(swift build --show-bin-path)/char-appearance-script"

# Shipped customization examples: mechanism once, identities/formats per package.
node --test integrations/minimax-code/tests/adapter.test.mjs
swift run char-package-check integration integrations/minimax-code/packages/minimax-code-cli.charintegration
swift run char-package-check integration integrations/minimax-code/packages/minimax-code-desktop.charintegration
swift run char-package-check skin examples/appearance/feibi/packages/feibi.charpet
python3 scripts/check-public-docs.py

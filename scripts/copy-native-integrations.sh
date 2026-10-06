#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
destination="$1"
mkdir -p "$destination/native" "$destination/pi" "$destination/kimi" "$destination/deepseek"
cp "$repo_root/integrations/native/adapter.mjs" "$destination/native/adapter.mjs"
cp "$repo_root/integrations/pi/install.py" "$repo_root/integrations/pi/observer.mjs" "$destination/pi/"
cp "$repo_root/integrations/kimi/install.py" "$destination/kimi/install.py"
cp "$repo_root/integrations/deepseek/index.js" "$destination/deepseek/index.js"
printf '{"type":"module"}\n' > "$destination/package.json"

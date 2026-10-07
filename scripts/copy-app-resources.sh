#!/bin/bash
# Copy only runtime resources and ready-to-import examples, never development workspaces.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
destination="$1"
mkdir -p "$destination"
for asset in Char.icns Icons Integrations Skins; do
    ditto "$repo_root/Resources/$asset" "$destination/$asset"
done
find "$destination" -name AGENTS.md -delete
mkdir -p "$destination/Examples"
ditto "$repo_root/integrations/minimax-code/packages/minimax-code-cli.charintegration" "$destination/Examples/minimax-code-cli.charintegration"
ditto "$repo_root/integrations/minimax-code/packages/minimax-code-desktop.charintegration" "$destination/Examples/minimax-code-desktop.charintegration"
ditto "$repo_root/examples/appearance/feibi/packages/feibi.charpet" "$destination/Examples/feibi.charpet"
bash "$repo_root/scripts/copy-native-integrations.sh" "$destination/NativeIntegrations"

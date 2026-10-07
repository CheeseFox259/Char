#!/bin/bash
# Copy only runtime resources and ready-to-import examples, never development workspaces.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
destination="$1"
mkdir -p "$destination"
for asset in Char.icns Icons Integrations; do
    ditto "$repo_root/Resources/$asset" "$destination/$asset"
done
mkdir -p "$destination/Skins"
for skin in "$repo_root"/Resources/Skins/*.charpet; do
    ditto "$skin" "$destination/Skins/$(basename "$skin")"
done
find "$destination" -name AGENTS.md -delete
mkdir -p "$destination/Examples"
ditto "$repo_root/integrations/minimax-code/packages/minimax-code-cli.charintegration" "$destination/Examples/minimax-code-cli.charintegration"
ditto "$repo_root/integrations/minimax-code/packages/minimax-code-desktop.charintegration" "$destination/Examples/minimax-code-desktop.charintegration"
ditto "$repo_root/examples/appearance/feibi/packages/feibi.charpet" "$destination/Examples/feibi.charpet"
cp "$repo_root/examples/appearance/feibi/ASSET-NOTICES.md" "$destination/Examples/FEIBI-ASSET-NOTICES.md"
cp "$repo_root/examples/appearance/feibi/audio/LICENSE-CC-BY-NC-SA-4.0.txt" "$destination/Examples/FEIBI-AUDIO-LICENSE.txt"
bash "$repo_root/scripts/copy-native-integrations.sh" "$destination/NativeIntegrations"

#!/bin/bash
# Copy only runtime resources and ready-to-import examples, never development workspaces.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
destination="$1"
mkdir -p "$destination"
copy_resource() {
    local source="$1" target="$2"
    if [[ -d "$source" ]]; then
        mkdir -p "$target"
        # Finder metadata is not runtime content, and some system-generated
        # .DS_Store files cannot be copied by a sandboxed release build.
        rsync -a --extended-attributes --exclude='.DS_Store' "$source/" "$target/"
    else
        cp "$source" "$target"
    fi
}
for asset in Char.icns Icons Integrations; do
    copy_resource "$repo_root/Resources/$asset" "$destination/$asset"
done
mkdir -p "$destination/Skins"
for skin in "$repo_root"/Resources/Skins/*.charpet; do
    copy_resource "$skin" "$destination/Skins/$(basename "$skin")"
done
find "$destination" -name AGENTS.md -delete
mkdir -p "$destination/Examples"
copy_resource "$repo_root/examples/integrations/minimax-code/packages/minimax-code-cli.charintegration" "$destination/Examples/minimax-code-cli.charintegration"
copy_resource "$repo_root/examples/integrations/minimax-code/packages/minimax-code-desktop.charintegration" "$destination/Examples/minimax-code-desktop.charintegration"
copy_resource "$repo_root/examples/appearance/feibi/packages/feibi.charpet" "$destination/Examples/feibi.charpet"
cp "$repo_root/examples/appearance/feibi/ASSET-NOTICES.md" "$destination/Examples/FEIBI-ASSET-NOTICES.md"
cp "$repo_root/examples/appearance/feibi/audio/LICENSE-CC-BY-NC-SA-4.0.txt" "$destination/Examples/FEIBI-AUDIO-LICENSE.txt"
bash "$repo_root/scripts/copy-native-integrations.sh" "$destination/NativeIntegrations"

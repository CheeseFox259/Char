#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
swift build -c release
bin_path="$(swift build -c release --show-bin-path)"
app_path="$repo_root/build/Char.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$repo_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
cp "$bin_path/Char" "$app_path/Contents/MacOS/Char"
cp "$bin_path/char-hook" "$app_path/Contents/MacOS/char-hook"
# Copy local assets while preserving Info.plist at the bundle root.
while IFS= read -r -d '' asset; do
    relative="${asset#"$repo_root/Resources/"}"
    mkdir -p "$app_path/Contents/Resources/$(dirname "$relative")"
    cp "$asset" "$app_path/Contents/Resources/$relative"
done < <(find "$repo_root/Resources" -type f ! -name Info.plist -print0)
codesign --force --sign - "$app_path"
printf '%s\n' "$app_path"

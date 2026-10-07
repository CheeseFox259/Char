#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
swift build -c release
bin_path="$(swift build -c release --show-bin-path)"
app_path="$repo_root/build/Char.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$repo_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
cp "$bin_path/Char" "$app_path/Contents/MacOS/Char"
cp "$bin_path/char-hook" "$app_path/Contents/MacOS/char-hook"
cp "$bin_path/char-appearance-script" "$app_path/Contents/MacOS/char-appearance-script"
codesign --force --sign - "$app_path/Contents/MacOS/char-appearance-script"
# Copy local assets while preserving Info.plist at the bundle root.
bash "$repo_root/scripts/copy-app-resources.sh" "$app_path/Contents/Resources"
codesign --force --sign - "$app_path"
printf '%s\n' "$app_path"

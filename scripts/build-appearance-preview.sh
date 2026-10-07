#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/module-cache"
swift build --disable-sandbox -c release --scratch-path build/swift-preview
bin="$PWD/build/swift-preview/release"
app="$PWD/build/feibi-preview/Char.app"
# Remove only generated resources; keep the adjacent isolated user-test Profile.
python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1],ignore_errors=True)' "$app/Contents/Resources"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CharAppearancePreview bool true" "$app/Contents/Info.plist"
cp "$bin/Char" "$bin/char-hook" "$bin/char-appearance-script" "$app/Contents/MacOS/"
codesign --force --sign - "$app/Contents/MacOS/char-appearance-script"
bash scripts/copy-app-resources.sh "$app/Contents/Resources"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"

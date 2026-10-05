#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
output="$repo_root/build/release/$version"
mkdir -p "$output"
stage="$(mktemp -d "$repo_root/build/release-stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Char.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
for architecture in arm64 x86_64; do
    swift build -c release --arch "$architecture" --product Char
    swift build -c release --arch "$architecture" --product char-hook
done
for executable in Char char-hook; do
    arm_bin="$(swift build -c release --arch arm64 --show-bin-path)/$executable"
    intel_bin="$(swift build -c release --arch x86_64 --show-bin-path)/$executable"
    lipo -create "$arm_bin" "$intel_bin" -output "$app/Contents/MacOS/$executable"
    chmod +x "$app/Contents/MacOS/$executable"
done
while IFS= read -r -d '' asset; do
    relative="${asset#"$repo_root/Resources/"}"
    mkdir -p "$app/Contents/Resources/$(dirname "$relative")"
    cp "$asset" "$app/Contents/Resources/$relative"
done < <(find "$repo_root/Resources" -type f ! -name Info.plist ! -name AGENTS.md -print0)
# Public builds are ad hoc signed; no Developer ID/notarization is claimed.
codesign --force --sign - "$app/Contents/MacOS/char-hook"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
ditto "$app" "$output/Char.app"
archive="Char-$version-macos-universal.zip"
disk="Char-$version-macos-universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/$archive"
mkdir "$stage/disk"
ditto "$app" "$stage/disk/Char.app"
ln -s /Applications "$stage/disk/Applications"
hdiutil create -quiet -ov -format UDZO -volname "Char $version" -srcfolder "$stage/disk" "$output/$disk"
(cd "$output" && shasum -a 256 "$archive" "$disk" > SHA256SUMS)
printf 'Release artifacts: %s\n' "$output"

#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
mkdir -p build/icon-artwork
swiftc Sources/CharPlatform/PetIconArtwork.swift scripts/generate-app-icon.swift -o build/icon-artwork/generate
build/icon-artwork/generate build/icon-artwork
cp build/icon-artwork/Char.png Resources/Icons/Char.png
iconutil -c icns build/icon-artwork/Char.iconset -o Resources/Char.icns
build/icon-artwork/generate build/example-icon --example
cp build/example-icon/Char.png Resources/Skins/example.charpet/icon.png

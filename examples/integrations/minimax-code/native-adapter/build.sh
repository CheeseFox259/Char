#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos13.0" main.swift -o "build/minimax-monitor-$arch"
done
lipo -create build/minimax-monitor-arm64 build/minimax-monitor-x86_64 -output build/minimax-monitor
codesign --force --sign - build/minimax-monitor
codesign --verify --strict build/minimax-monitor

#!/bin/bash
# Builds the debug app and renders the layout preview PNGs with --render-artwork-preview.
# The preview mode creates no AppModel, opens no HID device, reads or saves no preferences and runs no actions.
# Usage: render.sh [output folder, default .build/preview]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
out="${1:-.build/preview}"
swift build --disable-sandbox --scratch-path .build --product LogiMouseControl 2>&1 \
    | grep -v -e 'org.swift.swiftpm' -e 'failed storing manifest'
bin="$(swift build --disable-sandbox --scratch-path .build --product LogiMouseControl --show-bin-path 2>/dev/null)"
mkdir -p "$out"
# Remove only old PNGs so a missing file can't pass as fresh.
rm -f "$out"/*.png
"$bin/LogiMouseControl" --render-artwork-preview "$out"
for png in "$out"/*.png; do echo "$PWD/$png"; done

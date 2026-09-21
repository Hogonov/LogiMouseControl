#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
config="${1:-release}"
swift build --disable-sandbox --scratch-path .build -c "$config" --product LogiMouseControl -debug-info-format none
bin_dir="$(swift build --disable-sandbox --scratch-path .build -c "$config" --show-bin-path)"
app="$PWD/dist/Logi Mouse Control.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/LogiMouseControl" "$app/Contents/MacOS/LogiMouseControl"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
codesign --force --sign - --identifier local.alexandr.LogiMouseControl "$app"
codesign --verify --strict "$app"
printf '%s\n' "$app"

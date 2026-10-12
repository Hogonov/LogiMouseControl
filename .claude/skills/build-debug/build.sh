#!/bin/bash
# Debug build of LogiMouseControl into .build/. Leaves dist/ and signing alone; never runs the app.
# Prints the build output without SwiftPM user-cache noise, then the binary folder. Exit status is the build's.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build --disable-sandbox --scratch-path .build --product LogiMouseControl 2>&1 \
    | grep -v -e 'org.swift.swiftpm' -e 'failed storing manifest'
status=${PIPESTATUS[0]}
if [ "$status" -eq 0 ]; then
    echo "Binary folder: $(swift build --disable-sandbox --scratch-path .build --product LogiMouseControl --show-bin-path 2>/dev/null)"
fi
exit "$status"

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift run --disable-sandbox --scratch-path .build MouseCoreChecks
# Isolated Spotlight regression checks. Dependencies are fakes: no input events,
# application launches, or system-setting changes are performed by this target.
swiftc -module-cache-path "$PWD/.build/module-cache" Sources/LogiMouseControl/SpotlightShortcut.swift Tests/SpotlightShortcutChecks/main.swift -o .build/SpotlightShortcutChecks
.build/SpotlightShortcutChecks

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift run --disable-sandbox --scratch-path .build MouseCoreChecks
# Isolated symbolic-hotkey regression checks (Spotlight, Spaces). Dependencies are fakes: no input events,
# application launches, or system-setting changes are performed by this target.
swiftc -module-cache-path "$PWD/.build/module-cache" Sources/LogiMouseControl/SymbolicShortcut.swift Tests/SymbolicShortcutChecks/main.swift -o .build/SymbolicShortcutChecks
.build/SymbolicShortcutChecks
# Isolated controller and executor checks; all effects are injected fakes.
checks_dir="$PWD/.build/dock-gesture-checks"
mkdir -p "$checks_dir"
swiftc -module-cache-path "$PWD/.build/module-cache" -emit-library -emit-module -module-name MouseCore Sources/MouseCore/*.swift -emit-module-path "$checks_dir/MouseCore.swiftmodule" -o "$checks_dir/libMouseCore.dylib"
swiftc -module-cache-path "$PWD/.build/module-cache" -I "$checks_dir" -L "$checks_dir" -lMouseCore -Xlinker -rpath -Xlinker "$checks_dir" Sources/LogiMouseControl/DockGestureController.swift Sources/LogiMouseControl/DockSwipe.swift Sources/LogiMouseControl/ScrollEngine.swift Sources/LogiMouseControl/SymbolicShortcut.swift Sources/LogiMouseControl/ActionExecutor.swift Sources/LogiMouseControl/RingActionIcon.swift Tests/DockGestureChecks/main.swift -o "$checks_dir/DockGestureChecks"
"$checks_dir/DockGestureChecks"

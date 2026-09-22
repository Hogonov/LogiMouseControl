#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
config="${1:-release}"
signing_identity="${LOGI_MOUSE_CONTROL_SIGNING_IDENTITY:-Logi Mouse Control Local Signing}"

if [[ "$signing_identity" =~ ^[[:xdigit:]]{40}$ ]]; then
    signing_hash="$signing_identity"
else
    signing_hash="$({ security find-identity -v -p codesigning 2>/dev/null || true; } | awk -v name="\"$signing_identity\"" 'index($0, name) { print $2; exit }')"
fi

if [[ -z "${signing_hash:-}" ]]; then
    cat >&2 <<EOF
Не найдена постоянная подпись "$signing_identity".

Один раз выполните:
  ./scripts/setup-local-signing.sh

Без постоянной подписи macOS считает каждую пересборку новым приложением и
заново запрашивает Мониторинг ввода и Универсальный доступ.
EOF
    exit 1
fi

swift build --disable-sandbox --scratch-path .build -c "$config" --product LogiMouseControl -debug-info-format none
bin_dir="$(swift build --disable-sandbox --scratch-path .build -c "$config" --show-bin-path)"
app="$PWD/dist/Logi Mouse Control.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/LogiMouseControl" "$app/Contents/MacOS/LogiMouseControl"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
# SwiftPM's module bundle must travel with the standalone .app.
ditto "$bin_dir/LogiMouseControl_LogiMouseControl.bundle" "$app/Contents/Resources/LogiMouseControl_LogiMouseControl.bundle"
codesign --force --sign "$signing_hash" --identifier local.alexandr.LogiMouseControl --timestamp=none "$app"
codesign --verify --strict --verbose=2 "$app"

requirements="$(codesign --display --requirements - "$app" 2>&1)"
if [[ "$requirements" == *"cdhash H\""* ]]; then
    printf '%s\n' 'Ошибка: приложение снова получило нестабильную ad hoc-подпись.' >&2
    exit 1
fi

printf 'Подпись: %s\n' "$signing_identity"
printf '%s\n' "$app"

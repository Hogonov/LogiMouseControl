@AGENTS.md

## Проект

Нативное macOS-приложение (14+) для Logitech MX Master 4 по Bluetooth: SwiftUI + AppKit + IOKit, Swift Package без сторонних зависимостей, без сети и телеметрии. Подробная архитектура: `docs/specs/architecture.md`, словарь терминов: `docs/specs/ontology.md`. Читай их, когда задача затрагивает границы модулей.

## Структура

- `Sources/MouseCore/`: чистое ядро без AppKit/IOKit. Кадры HID++ (`HIDPacket.swift`), интегратор прокрутки (`ScrollIntegrator.swift`), настройки и действия (`Preferences.swift`), каталог изображений мыши (`MouseArtwork.swift`). Новую логику, которую можно проверить без устройства, клади сюда.
- `Sources/LogiMouseControl/`: исполняемое приложение.
  - Точка входа и CLI-флаги (`--diagnose`, `--render-artwork-preview`, `--recover-on-exit`): `AppEntry.swift`.
  - Координация состояния: `AppModel.swift`.
  - Сервисы: `DeviceService` (очередь HID-команд), `ScrollEngine`, `ActionExecutor`, `RingController`, `CaptureGuardian`, `SpotlightShortcut`.
  - Инфраструктура: `HIDTransport` (IOHIDManager).
  - UI: `LogiMouseControlApp`, `MainView`, `MouseIllustration`, `RingActionIcon`, `ArtworkPreview`.
  - Ресурсы: `DeviceImages/`.
- `Tests/MouseCoreTests/`: исполняемый target `MouseCoreChecks` с самописными проверками, не XCTest.
- `Tests/SpotlightShortcutChecks/`: изолированные проверки `SpotlightShortcut` на подставных зависимостях.
- `Resources/`: `Info.plist`, иконка, происхождение изображений.
- `dist/`: собранный `.app` и архив релиза (в `.gitignore`).
- `.agents/skills/`: скиллы других агентов (`skills-lock.json`); Claude Code их не загружает.

## Команды

- Тесты: `./scripts/test.sh`
- Сборка release `.app` с подписью: `./scripts/build.sh` (debug: `./scripts/build.sh debug`). Нужен сертификат из `./scripts/setup-local-signing.sh`; сам этот скрипт не запускай, он меняет связку ключей.
- Тесты хуков Claude Code (после правки `.claude/hooks/`): `.claude/hooks/test-hooks.sh`
- Проверка вёрстки без мыши: `"dist/Logi Mouse Control.app/Contents/MacOS/LogiMouseControl" --render-artwork-preview <папка>`

## Соглашения

- В SwiftUI-вью пиши `@ViewState`, а не `@State`: это alias из `LogiMouseControlApp.swift`, обходящий конфликт макроса в SDK macOS 27.
- Документация и пользовательские строки на русском.
- Не добавляй сетевой код, аналитику и сторонние зависимости.

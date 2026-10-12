---
paths:
  - "Sources/MouseCore/**/*.swift"
---

# MouseCore

- Только `Foundation`. Не импортируй SwiftUI, AppKit, IOKit, CoreGraphics и ApplicationServices: ядро проверяется без macOS UI и без мыши.
- Новую логику, которую можно проверить без устройства (разбор HID++, преобразование значений, математика прокрутки, настройки), клади сюда, а не в `Sources/LogiMouseControl/`.
- Всё, что вызывает приложение или проверки, объявляй `public`: `MouseCoreChecks` видит модуль только через `import MouseCore`.
- Каждое новое поведение покрывай проверкой в `Tests/MouseCoreTests/MouseCoreTests.swift`.
- Изменение `Codable`-типов в `Preferences.swift` не должно ломать чтение сохранённых настроек (`preferences.v1`). Старый формат декодируется, повреждённые значения ограничиваются, а не роняют приложение.

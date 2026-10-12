---
paths:
  - "Sources/LogiMouseControl/LogiMouseControlApp.swift"
  - "Sources/LogiMouseControl/MainView.swift"
  - "Sources/LogiMouseControl/MouseIllustration.swift"
  - "Sources/LogiMouseControl/RingActionIcon.swift"
  - "Sources/LogiMouseControl/RingController.swift"
  - "Sources/LogiMouseControl/ArtworkPreview.swift"
  - "Sources/LogiMouseControl/*View*.swift"
---

# Интерфейс

- Для состояния вью пиши `@ViewState`, а не `@State`. Это alias из `LogiMouseControlApp.swift`, он обходит конфликт макроса в SDK macOS 27.
- Пользовательские строки пиши на русском.
- Вью не трогают `HIDTransport`, `DeviceService` и `ActionExecutor` напрямую: всё идёт через `AppModel`.
- Не показывай нереализованную функцию как работающую: никаких переключателей-заглушек.
- Проверяй вёрстку командой `--render-artwork-preview <папка>` и смотри полученные PNG; приложение для проверки не запускай.

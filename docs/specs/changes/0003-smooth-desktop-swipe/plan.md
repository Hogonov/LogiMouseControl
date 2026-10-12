# План CH-0003: Плавное переключение рабочих столов жестом

Спецификация: [spec.md](spec.md)
Статус: выполнен

## Выбранный подход

1. **`MouseCore/SpaceSwipe.swift`.** `SwipePhase` (значения `IOHIDEventPhaseBits`: 1, 2, 4, 8), `SwipeStep(phase, progress, velocity)`. `SpaceSwipe(sign:countsPerSpace:)`: `move(dx:at:)` копит прогресс в рабочих столах (положительный — к столу справа), на границе ±1 выдаёт ended и began с остатком; скорость — экспоненциальное сглаживание `Δпрогресса/Δt` (Δt ограничено 4–100 мс). `release(at:)`: скорость обнуляется после 0,15 с без движения; cancelled, если скорость больше 0,5 стола/с против прогресса, иначе ended. `cancel()`: cancelled, если свайп начат. `countsPerSpace(dpi:)` = 800 × DPI / 1000 (DPI неизвестен — 1000).
2. **`GestureSession`.** Оборачивает `GestureAccumulator` (у него становится публичным чтение `x`, `y`). Свайп начинается, когда `direction` впервые становится `left`/`right`, есть знак свайпа и `allowSwipe`; первый сегмент получает весь накопленный горизонтальный сдвиг. Если первым стало `up`/`down`, свайп в этой сессии не начинается. `release(at:)` возвращает `.action(direction)` или `.swipe(steps, direction)`.
3. **`GestureActions.desktopSwipeSign`.** +1 для (`previousDesktop`, `nextDesktop`), −1 для зеркальной пары, иначе `nil`.
4. **`DockSwipe` (приложение).** Загружает функции IOKit и SkyLight через `dlopen`/`dlsym`; `isAvailable` — macOS ≥ 27 и все символы найдены. `post(_:)` проверяет `AXIsProcessTrusted()`, на began читает `com.apple.swipescrolldirection` (нет ключа — естественная) и фиксирует знак HID на сегмент: прогресс и скорость × (−1 при естественной прокрутке). Создаёт `IOHIDEvent` DockSwipe с опциями `phase << 24`, полями движения (1), варианта (3) и прогресса; на ended/cancelled добавляет событие скорости (тип 9, X и Y). Вкладывает в `CGEvent` типа 30, ставит `eventSourceUserData` = маркер, отправляет в `.cgSessionEventTap`.
5. **`AppModel`.** `gestureState: [UInt16: GestureSession]`. При нажатии — знак свайпа, только если `DockSwipe.isAvailable`. Raw XY → шаги → `DockSwipe.post`; на ended — `pulse()`. Только одна сессия может вести свайп (`allowSwipe`). Отпускание: `.action` — прежний путь; `.swipe` — шаги и `lastGesture`. `cancelGestures()` отправляет cancelled всем начатым свайпам; вызывается при сбросе ввода в `configure()`, в `onDisconnected` и `shutdown`. Ранний выход `configure()` (захват не меняется) больше не сбрасывает `held`/`gestureState`.
6. **UI.** `AppModel.smoothDesktopSwipe` → текст подсказки на странице «Кнопки и жесты».

## Альтернативы

См. [ADR-0002](../../adr/0002-dock-swipe-synthesis.md).

## Влияние на архитектуру

| Вопрос | Ответ |
|---|---|
| Меняются границы модулей или зависимости? | Новый компонент `DockSwipe` в приложении; новые типы в `MouseCore`. Зависимостей нет; приватные IOKit/SkyLight загружаются динамически |
| Меняются потоки данных, очереди или владение состоянием? | Поток 4.2: Raw XY во время удержания даёт шаги свайпа. `DockSwipe` и сессии — main. Ранний выход `configure()` сохраняет `held`/`gestureState` |
| Меняется формат настроек, CLI или идентичность приложения? | Нет |
| Затрагиваются инварианты INV-…? | INV-16 дополняется завершением свайпа; INV-8 соблюдается (проверка версии во время выполнения) |
| Нужен ADR? | ADR-0002 |

## Задачи

| ID | Задача | Требования | Файлы и символы | Проверки |
|---|---|---|---|---|
| T-01 | `SpaceSwipe`, `SwipeStep`, `GestureSession`, `desktopSwipeSign`, чтение `x`/`y` | R-01…R-05, R-08 | `Sources/MouseCore/SpaceSwipe.swift`, `Preferences.swift` | V-01…V-04 |
| T-02 | Проверки ядра | R-01…R-05, R-07, R-08 | `Tests/MouseCoreTests/MouseCoreTests.swift` | V-01…V-04 |
| T-03 | `DockSwipe` | R-01, R-04, R-06, R-11 | `Sources/LogiMouseControl/DockSwipe.swift` | V-05 |
| T-04 | `AppModel`: сессии, отправка, импульсы, отмена, ранний выход `configure()` | R-01…R-09 | `AppModel.swift` | V-05, M-01…M-05 |
| T-05 | Подсказка в UI | R-10 | `MainView.swift` | V-05, V-06 |
| T-06 | Документы | — | см. ниже | проверка ссылок, JSON, `git diff --check` |

## Риски и откат

- Dock не реагирует на синтезированные изменения или «залипает» посередине → M-01/M-05 → назначить «влево/вправо» другие действия; исправление отдельным изменением.
- Dock не принимает новый сегмент сразу после конца предыдущего → M-02 → убрать сегменты, оставив один свайп на удержание.
- Смена активного приложения во время свайпа с профилем, у которого другие кнопки, перенастраивает захват и отменяет свайп → описано в `architecture.md`.
- Авария процесса во время свайпа оставляет Dock без конечного события → U-13.

## Документация к обновлению

- [x] `docs/specs/architecture.md`: компоненты, поток 4.2, 5.1, 5.2, INV-16, U-13, U-14
- [x] `docs/specs/ontology.md`: Space swipe, DockSwipe, Gesture session
- [x] `docs/specs/knowledge-graph.json`: компонент `DockSwipe`, типы `MouseCore`, ADR-0002, CH-0003
- [x] `docs/HARDWARE_VALIDATION.md`: раздел CH-0003
- [x] `README.md`: описание жестов
- [x] `THIRD_PARTY_NOTICES.md`: Mac Mouse Fix как справочник формата
- [x] `docs/specs/README.md`: реестр изменений и ADR

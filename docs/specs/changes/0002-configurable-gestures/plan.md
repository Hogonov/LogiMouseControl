# План CH-0002: Настраиваемые жесты и переключение рабочих столов

Спецификация: [spec.md](spec.md)
Статус: выполнен

## Выбранный подход

1. **Модель (`MouseCore`).** `GestureDirection` (`up`, `down`, `left`, `right`, `click`) заменяет строку в `GestureAccumulator.direction`; результат без порога — `.click`. `GestureActions` хранит действие для каждого направления, имеет значения по умолчанию и ручной `init(from:)` через `decodeIfPresent`. `Preferences.gestures: [String: GestureActions]` — ключ как у `buttons` (десятичный CID). `Preferences.gestureActions(for:)` возвращает сохранённое или значения по умолчанию. У `Preferences` ручной `init(from:)` через `decodeIfPresent` для всех полей; кодирование остаётся синтезированным. Новые `MouseAction.previousDesktop`, `nextDesktop`; `MouseAction.gestureChoices` — все действия, кроме `.system` и `.gestures`.
2. **Системные сочетания.** `SpotlightShortcut` обобщается до `SymbolicShortcut(hotKey:name:fallback:)`: тот же CGS через `dlopen`/`dlsym`, тот же механизм временного включения и возврата, плюс необязательное запасное сочетание, если CGS не вернул значение. Файл компилируется отдельно, как и прежде; проверки переезжают в `Tests/SymbolicShortcutChecks`.
3. **`ActionExecutor`.** Экземпляры `SymbolicShortcut` для 64 (Spotlight), 33 (окна приложения, запасное ⌃↓ `0x840000`), 36 (рабочий стол, F11 `0x800000`), 79/81 (рабочие столы, ⌃←/⌃→ `0x840000`). Метод `symbolic(_:fallback:)` и чтение файла `com.apple.symbolichotkeys` удаляются. `gesture(_:)` удаляется: выбор действия переходит в `AppModel`. `cancelPendingActions()` возвращает все сочетания.
4. **`AppModel.handle(_:)`.** При отпускании контрола с накопителем: `preferences.gestureActions(for: id)[direction]` → `executor.execute`; `pulse()` кроме `.none`; `lastGesture` для UI.
5. **UI.** В `ButtonAssignmentsView` для «Жесты» — блок «Направления жеста» с пятью `Picker`; «Проверить действие» скрыт для «Жесты». `MainView.buttons` — новый текст подсказки и строка последнего жеста. `ArtworkPreview` дополнительно рендерит `gestures.png` с выбранной кнопкой жестов.

## Альтернативы

| Вариант | Почему не выбран |
|---|---|
| Синтез DockSwipe (OpenLogi `inject/macos/spaces.rs`) | Приватные поля событий и класс `HIDEvent` различаются между версиями macOS; в OpenLogi отдельная ветка для macOS 27 и исправления направления. Оставлено на случай неудачи M-01. |
| Исправить только запасные модификаторы в `symbolic(_:fallback:)` | Чтение файла не отражает действующие сочетания (записей может не быть или они устарели), отключённое сочетание даёт только звуковой сигнал. CGS уже применяется для Spotlight. |
| Добавить `gestures` как `Optional` без ручного декодера | Неудобный API; ручной `init(from:)` заодно закрывает сброс настроек при новых полях (P-01) для `Preferences`. |

## Влияние на архитектуру

| Вопрос | Ответ |
|---|---|
| Меняются границы модулей или зависимости? | Нет. Компонент `SpotlightShortcut` переименован в `SymbolicShortcut` и обслуживает несколько symbolic hotkeys; приватный CGS уже использовался. |
| Меняются потоки данных, очереди или владение состоянием? | Поток 4.2: действие после отпускания берётся из `Preferences.gestures`. Новое состояние `AppModel.lastGesture` на main. Состояние возврата сочетаний — у каждого экземпляра `SymbolicShortcut` на main. |
| Меняется формат настроек, CLI или идентичность приложения? | `preferences.v1`: необязательный ключ `gestures`, два новых значения `MouseAction`. CLI и идентичность — нет. |
| Затрагиваются инварианты INV-…? | INV-14 соблюдается ручным декодером; INV-3 — `lastGesture` только в памяти; INV-1/2 — проверки на подставных зависимостях. Остальные не затронуты. |
| Нужен ADR? | Нет: формат расширяется совместимо по INV-14, граница модулей и зависимости не меняются. |

## Задачи

| ID | Задача | Требования | Файлы и символы | Проверки |
|---|---|---|---|---|
| T-01 | `GestureDirection`, `GestureActions`, `Preferences.gestures`, ручной декодер, новые действия, `gestureChoices`, `GestureAccumulator` → `GestureDirection` | R-01, R-02, R-03, R-06 | `Sources/MouseCore/Preferences.swift` | V-01…V-05 |
| T-02 | Проверки ядра | R-02, R-03, R-06 | `Tests/MouseCoreTests/MouseCoreTests.swift` | V-01…V-05 |
| T-03 | `SymbolicShortcut` с идентификатором, именем и запасным сочетанием; перенос и расширение проверок; `scripts/test.sh` | R-04, R-05 | `Sources/LogiMouseControl/SymbolicShortcut.swift`, `Tests/SymbolicShortcutChecks/main.swift`, `scripts/test.sh` | V-06 |
| T-04 | `ActionExecutor`: сочетания через `SymbolicShortcut`, новые действия, удаление `gesture(_:)` и `symbolic` | R-03, R-04, R-05 | `ActionExecutor.swift` | V-06, V-07 |
| T-05 | `AppModel.handle(_:)`: действие по направлению, `lastGesture` | R-06, R-07 | `AppModel.swift` | V-07, V-09 |
| T-06 | UI направлений, подсказка, последний жест, предпросмотр | R-01, R-07 | `MouseIllustration.swift`, `MainView.swift`, `ArtworkPreview.swift` | V-07 |
| T-07 | Документация | все | см. ниже | `git diff --check`, JSON |

## Риски и откат

- macOS 27 не реагирует на синтезированное сочетание → M-01 не пройдёт; строка «Последний жест» покажет, что направление распознано → следующий шаг: DockSwipe отдельным изменением.
- Raw XY не доходят → «Последний жест» всегда «нажатие» → разбирать захват отдельно (M-03).
- Откат: revert коммита; настройки с новыми действиями прежняя версия сбросит (spec, «Совместимость»).

## Документация к обновлению

- [x] `docs/specs/architecture.md`: разделы 1, 2, 3, 4.2, 4.5, 5.1, 5.2, 6, 8, 9, «Проверки качества», D-11, U-11, U-12
- [x] `docs/specs/ontology.md`: Gesture, Gesture direction, Gesture actions, Symbolic shortcut, Desktop switch
- [x] `docs/specs/knowledge-graph.json`: targets, services, entities, threading, testingPattern
- [x] `docs/HARDWARE_VALIDATION.md`: запись «Настраиваемые жесты — 12.10.2026»
- [x] `docs/specs/README.md`: реестр, таблица проверок
- [x] `CLAUDE.md`: имя сервиса и проверок
- [x] `.claude/rules/checks.md`: путь `Tests/SymbolicShortcutChecks`
- [ ] `.claude/hooks/test-hooks.sh`: ожидает строку `22 checks passed` и путь `Tests/SpotlightShortcutChecks`; папка защищена от записи агентом — обновляет пользователь

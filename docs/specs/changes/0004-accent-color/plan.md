# План CH-0004: Акцентный цвет в настройках и обновлённая палитра

Спецификация: [spec.md](spec.md)
Статус: выполнен

## Выбранный подход

1. `MouseCore/Preferences.swift`: `enum AccentColor: String, Codable, CaseIterable, Identifiable` (`mint`, `teal`, `blue`, `violet`, `pink`, `graphite`) с `title` и `rgb` (компоненты sRGB 0…1, только `Foundation`) и `relativeLuminance` для проверки контраста. `Preferences.accent: AccentColor = .mint`; в `init(from:)` значение читается через `try?` + `decodeIfPresent`, чтобы неизвестная строка не ломала декодирование всего `Preferences` (как в `GestureActions`).
2. Новый `Sources/LogiMouseControl/Theme.swift`: `enum Palette` с нейтральными токенами (`canvas`, `sidebar`, `surface`, `hairline`, `stroke`, `selection`, `inactive`), `AccentColor.color`, ключ окружения `\.accent` (классический `EnvironmentKey`, без макроса `@Entry`: в CLT macOS 27 нет плагина SwiftUIMacros) и модификатор `.appTheme(_:)` = окружение + `tint` + `preferredColorScheme(.dark)`.
3. `MainView`: приватные константы удаляются; `MainView` читает `model.preferences.accent` и вызывает `.appTheme`; `Card`, `Notice`, `ScrollSettingsView` берут акцент из окружения. Градиент карточки обзора: `surface` + наложение акцента с малой непрозрачностью. Новая карточка «Оформление» в `settings` с `AccentPicker`.
4. `AccentPicker` (в `Theme.swift`): ряд круглых образцов, отметка у выбранного, `.help`, метки доступности; привязка `Binding<AccentColor>` и замыкание `changed`. В `MainView` изменение вызывает `model.save()` (без `configure()`).
5. `MouseIllustration`: `blue` заменяется акцентом из окружения; белые полупрозрачные цвета — токенами палитры.
6. `RingController.show(actions:accent:execute:pulse:)` применяет `.appTheme(accent)` к `ActionRingView`; подсветка пункта — акцент из окружения. `AppModel.showRing()` передаёт `preferences.accent`.
7. `ArtworkPreview`: фон из палитры, `.appTheme`; дополнительно `appearance.png` (карточка выбора цвета) и `buttons-violet.png`.

## Альтернативы

| Вариант | Почему не выбран |
|---|---|
| Отдельный ключ `UserDefaults` для оформления | Второй источник настроек; `preferences.v1` уже расширяется совместимо (CH-0002) и проверяется в `MouseCoreChecks` |
| `ShapeStyle.tint` вместо собственного ключа окружения | Не сочетается с тернарными выражениями `Color` и `.opacity` на `Color`; нужен конкретный `Color` для `NSPanel` кольца |
| `ColorPicker` с произвольным цветом | Вне объёма (spec), не гарантирует контраст R-05 |

## Влияние на архитектуру

| Вопрос | Ответ |
|---|---|
| Меняются границы модулей или зависимости? | Нет. Новый файл views `Theme.swift`; `MouseCore` по-прежнему только `Foundation` |
| Меняются потоки данных, очереди или владение состоянием? | Нет: main thread, `AppModel.preferences`. Поток 4.5: изменение акцента вызывает только `save()` |
| Меняется формат настроек, CLI или идентичность приложения? | `preferences.v1`: новый необязательный ключ `accent`. `--render-artwork-preview`: два новых PNG. Идентичность не меняется |
| Затрагиваются инварианты INV-…? | INV-14 (соблюдается ручным декодером), INV-8, INV-9; аппаратные — нет |
| Нужен ADR? | Нет: совместимое расширение формата в существующих границах, как в CH-0002 |

## Задачи

| ID | Задача | Требования | Файлы и символы | Проверки |
|---|---|---|---|---|
| T-01 | `AccentColor`, `Preferences.accent`, декодер; проверки | R-02, R-05 | `Preferences.swift`, `MouseCoreTests.swift` | V-01, V-02, V-03 |
| T-02 | Палитра, ключ окружения, `appTheme`, `AccentPicker` | R-01, R-04 | `Theme.swift` | V-04, V-05 |
| T-03 | `MainView` на палитре, карточка «Оформление» | R-01, R-03, R-04 | `MainView.swift` | V-04, V-05 |
| T-04 | Карта кнопок и кольцо на акценте; передача акцента в кольцо | R-03, R-06 | `MouseIllustration.swift`, `RingController.swift`, `AppModel.showRing()` | V-04, V-06 |
| T-05 | Предпросмотр: палитра, `appearance.png`, `buttons-violet.png` | R-01, R-03 | `ArtworkPreview.swift` | V-05 |
| T-06 | Документация | — | см. ниже | `json.tool`, `git diff --check` |

## Риски и откат

- Неверный цвет текста на заливке → V-03 и просмотр PNG → поправить RGB в `AccentColor`.
- Акцент не доходит до вложенного вида (другая иерархия, например `NSPanel`) → V-04 и M-01 → передать окружение явно.
- Откат: вернуть файлы; ключ `accent` игнорируется прежней версией.

## Документация к обновлению

- [x] `docs/specs/architecture.md`: компоненты (Views + `Theme.swift`), поток 4.5, раздел 8, проверки (число проверок, предпросмотр), шапка
- [x] `docs/specs/ontology.md`: Accent color, Palette
- [x] `docs/specs/knowledge-graph.json`: сущность `AccentColor`, изменение
- [x] `docs/HARDWARE_VALIDATION.md`: «Акцентный цвет — 12.10.2026»
- [x] `docs/specs/README.md`: реестр
- [x] `README.md`: при наличии описания настроек

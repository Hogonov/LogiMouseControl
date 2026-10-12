---
paths:
  - "Tests/**/*.swift"
---

# Правила для проверок

- `Tests/MouseCoreTests/MouseCoreTests.swift` не использует XCTest: `XCTAssertEqual`, `XCTFail`, `XCTUnwrap` и другие здесь самописные `private`-функции на `precondition` внизу файла. Нужен новый вид проверки — добавь такую же функцию рядом.
- Новый метод `test…` сам не запускается. Добавь вызов в `Checks.main()` в том же стиле, `suite.testX(); print("PASS testX")` (с `try`, если метод `throws`), и увеличь число в строке `print("N checks passed")`.
- `Tests/SymbolicShortcutChecks/main.swift` работает только с подставными зависимостями из `Harness`. Не вызывай в нём настоящие системные API; при новой проверке обнови число в итоговом `print`.
- Запускай все проверки через `./scripts/test.sh`.

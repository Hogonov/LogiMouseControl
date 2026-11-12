# План CH-0007: вертикальный жест Mission Control

Спецификация: [spec.md](spec.md) · Решение: [ADR-0003](../../adr/0003-mission-control-dock-gesture.md)
Статус: реализовано — ждёт проверки пользователем
Дата: 2026-11-12

## Инструкция следующему исполнителю

Реализуй CH-0007 по этому плану и `spec.md`. Пользователь выбрал вертикальный DockSwipe, чтобы первое нажатие Mission Control принималось во время перехода между столами. Ожидание окончания анимации, увеличение cooldown и повторные вызовы `Mission Control.app` не являются решением.

1. Прочитай `AGENTS.md`, [процесс](../../README.md), архитектуру 3/4.2/5.1/5.2/INV, словарь, журнал аппаратной проверки, spec и ADR-0003. Проверь текущий diff: не перезаписывай чужую работу.
2. Выполняй T-01…T-09 по порядку. Перед изменением кода переведи spec в «в работе». Изменение выбранного поведения сначала отражай в spec/ADR.
3. Не запускай приложение, `--diagnose`, действия, нажатия, прокрутку, виброотклик или сторонний генератор событий. Тесты работают с фальшивыми эффектами. Не запускай `setup-local-signing.sh` и release-сборку.
4. По завершении автоматических проверок передай M-01…M-08 пользователю. Не называй функцию подтверждённой до M-01/M-02. При неудаче этих сценариев сохрани факт неудачи; не подменяй требование ожиданием анимации.

## Выбранный подход

Один экземпляр `DockSwipe` остаётся платформенным отправителем. `AppModel` владеет им и новым `DockGestureController`. Контроллер ведёт только короткую вертикальную последовательность, а горизонтальные удержания остаются в состоянии ввода. Оба направления проходят через контроллер, поэтому старая вертикальная задача не может отправить кадр посреди нового горизонтального свайпа.

В `ActionExecutor` все `.missionControl` направляются в один callback. Не создавать отдельный backend внутри кнопки, кольца или `testAction`. Legacy-вызов приложения остаётся явно доступным контроллеру как fallback до начала отправки.

### 1. Чистые типы и вертикальная последовательность

Новый файл `Sources/MouseCore/MissionControlGesture.swift`; только Foundation. Планируемые имена публичных типов:

- `DockGestureAxis`: `.horizontal = 1`, `.vertical = 2`.
- `DockGestureFrame`: `axis` и существующий `SwipeStep`. Не менять смысл `SwipeStep.progress` для `SpaceSwipe`; вертикальный прогресс нормирован отдельно.
- `MissionControlGesture`: чистое состояние ограниченного импульса, методы `start(at:)`, `advance(at:)`, `cancel()` или эквивалент с явным временем. Каждый метод возвращает описания кадров, никогда не отправляет их.
- `MissionControlGesture.Configuration`: именованные параметры ниже, удобные для тестов, без сохранения в Preferences и без UI.

Первый вариант параметров (проектное допущение, не результат измерения):

| Параметр | Значение | Назначение |
|---|---|---|
| `duration` | 0,120 с | Время генерации вертикального импульса, не ожидание чужой анимации |
| `frameInterval` | 0,008 с | Частота примерно как у жеста; 15 интервалов |
| `targetProgress` | 1,0 | Нормированная амплитуда открытия; не использовать горизонтальное разбиение на столы |
| `staleAfter` | 0,250 с от start | Если main долго не исполнялся, отменить просроченный импульс вместо позднего открытия |
| `openingHIDSign` | natural on: +1; off: −1 | Начальная гипотеза знака вертикального открытия, изолировать от горизонтального `hidSign` |

Алгоритм:

1. `start(t0)` даёт vertical `began(progress: 0, velocity: 0)` сразу и запоминает t0. Не ждать первого timer tick.
2. Для очередного кадра вычислить индекс `i = min(15, floor((now - t0) / frameInterval))`, прогресс `targetProgress * i / 15`. Это дискретная линейная кривая; прогресс не уменьшается. Повторный индекс не даёт дубликат. Граничное время `now - t0 >= duration` проверять явно, чтобы погрешность Double не оставляла индекс 14 на последнем кадре.
3. Пока `0 < i < 15`, вернуть один changed. При задержке пропустить пропущенные промежуточные кадры: запрещён цикл «догоняющей» отправки всех кадров.
4. При возрасте >= duration и < staleAfter выдать последний changed с targetProgress (если ещё не был отправлен), затем ровно один ended с тем же progress. Начальная скорость ended = targetProgress / duration; её единицы и эффект требуют M-03. После terminal любые `advance` пусты.
5. При возрасте >= staleAfter выдать cancelled с последним отправленным progress и velocity=0. Проверить этот предел до обычной ветки завершения.
6. `cancel()` после began даёт один cancelled с последним progress и velocity=0; повтор cancel пуст. При отказе разрешений контроллер может использовать этот кадр только для локального завершения, без реальной отправки.

Проверять Configuration до подготовки: значения конечны, duration/frameInterval/targetProgress положительны, staleAfter > duration. Число интервалов вычислять как `ceil(duration / frameInterval)` (15 для начальных значений), а не дублировать литерал 15 в коде. При неверной конфигурации — ошибка подготовки до began, а не trap/бесконечный таймер. Обратное время игнорируется; нечисловое время во время активного импульса отменяет его. Эти варианты входят в V-01/V-02.

Смена знака — только на границе с платформой. Logical progress всегда положительный для открытия. Natural scrolling читается один раз до began и не меняется в середине. Положительный знак при natural on — гипотеза, а не установленный контракт macOS: если M-03 показывает App Exposé/обратное движение, сначала исправить таблицу параметров и тесты, затем адаптер. Не менять одновременно знак и длительность.

Если амплитуды 1,0 недостаточно и MC только приоткрывается, после отчёта пользователя изменить только targetProgress (следующий кандидат 1,5), записать результат M-03. Не увеличивать продолжительность и не вводить задержку старта для маскировки проблемы. Не подбирать параметры автоматическим запуском действий.

### 2. Подготовка событий и `DockSwipe`

В `Sources/LogiMouseControl/DockSwipe.swift` разделить построение и отправку:

- Сохранить existing horizontal формат: motion=1, flavor=3, progress, phase << 24, velocity-child на ended/cancelled, CGEvent type=30, marker, `.cgSessionEventTap`.
- Вертикаль отличается motion=2 и отдельно нормализованным знаком/прогрессом. Не добавлять CGEvent типа 29, приватные поля старого формата или новые символы.
- Заменить единственный неявный `hidSign` на контекст текущей последовательности: ось и знак, фиксированные при began. Не разрешать vertical изменять знак незаконченного horizontal.
- Подготовить вертикальные кадры/терминальные варианты **до отправки первого began и до прерывания горизонтального удержания**. Ошибка выделения/создания событий тогда позволяет безопасный legacy fallback. Допустима таблица кадров для 15 интервалов с заранее подготовленными cancelled для каждого progress; при пропуске времени брать текущий индекс, не проигрывать все предыдущие.
- При дискретной таблице вычислять индекс `min(15, floor(elapsed / 0.008))`; progress=i/15. В 0,120 с последний changed и ended. Это согласованная дискретизация модели из раздела 1, тестировать её вместо произвольного второго алгоритма.
- Подготовленная последовательность удерживает свои объекты до завершения; не хранить глобальные или разделяемые между запросами изменяемые CGEvent. Функции фреймворков загружаются лениво в production factory, не в fake-конструкторе теста.
- Результат адаптера различает `unavailable`, `preparationFailed`, `prepared`. `post` не подтверждает принятие события Dock: успешный возврат означает только отправку. Не использовать имя `missionControlOpened` для такого результата.
- Не менять существующую горизонтальную математику и её API ради вертикали. Обёртка горизонтальных `SwipeStep` в `DockGestureFrame` выполняется в одном месте.

Рекомендуемый тестовый шов: `prepare(frames, sign) -> PreparedSequence?`, у которой `send(frameIndex)`/`cancel(atLastIndex)` представлены замыканиями. Production замыкания содержат единственные реальные `CGEvent.post`; fake записывает компактные enum-эффекты в память теста. Контроллер не должен импортировать/знать CGEvent.

### 3. `DockGestureController`: владение, время, ошибки

Новый файл `Sources/LogiMouseControl/DockGestureController.swift`, Foundation + MouseCore. Единственный экземпляр у AppModel, все вызовы на main. Зависимости передаются конструктору, без реальных default effects:

- `now: () -> Double` — production `systemUptime`;
- `schedule(delay, callback) -> cancellation` — production `DispatchQueue.main.asyncAfter`/DispatchWorkItem; fake хранит callbacks;
- `isAllowed: () -> Bool` — разрешение и актуальное lifecycle-состояние;
- подготовка/отправка backend; legacy fallback; `onError`;
- `finishHorizontalForMissionControl()` — callback AppModel, завершает собственные активные горизонтальные сессии до began;
- никаких ожиданий HID, NSWorkspace completion или уведомления Space.

Достаточно состояний `idle` и `running(sessionID, start, lastIndex, preparedSequence, scheduledTask)`. Идентификатор поколения монотонно увеличивается при новом запуске и отмене. `scheduledTask.cancel()` недостаточно: каждый callback также сравнивает sessionID и состояние.

| Событие | Было | Действие | Стало |
|---|---|---|---|
| MC, разрешено, подготовка успешна | idle | Завершить horizontal; повторно проверить разрешение; began немедленно; назначить следующий tick | running |
| MC | running, не просрочено | Принять как повтор того же открытия; не менять таймер, deadline, поколение, не звать fallback | running |
| MC после staleAfter, до исполнения старого tick | running | Отменить старую сессию; обработать новое нажатие как новый запрос | running новой сессии или idle при отказе |
| Tick действующего поколения | running | Проверить разрешение и возраст; выдать текущий changed/terminal; назначить только один следующий callback | running/idle |
| Tick старого поколения | любое | Ничего | без изменений |
| Независимое действие | любое | Немедленно передать в ActionExecutor, не ждать/не отменять вертикаль | без изменений |
| Новый horizontal began либо конфликтующее Dock-действие | running | Инвалидировать timer; cancelled вертикали; затем новый запрос | idle для вертикали |
| Lifecycle-stop | любое | Инвалидировать callbacks; cancelled при started и наличии разрешения; очистить ссылки | idle |
| Недоступность/ошибка подготовки | idle | Завершить собственный horizontal обычным правилом; повторно проверить разрешение; один legacy-вызов | idle |
| Отказ разрешения до began | любое | Локальный сброс; сообщение через существующий error; ни жеста, ни legacy | idle |
| Ошибка после began | running | Инвалидировать callbacks; cancelled по возможности; одно сообщение; без legacy/retry | idle |

Перед callback следующего кадра проверять permissions заново. После отмены не возобновлять жест при возвращении разрешения/пробуждении: нужен новый пользовательский ввод.

Следующий deadline рассчитывать от start и следующего индекса, с учётом duration; не накапливать задержку от времени предыдущего callback. Замыкания AppModel → controller → AppModel и scheduler не должны создавать retain cycle: обратные ссылки на владельцев weak. Terminal/cancel освобождают task и подготовленные события; callback со старым поколением не обращается к освобождённой последовательности.

`isAllowed` для этого маршрута: Accessibility и отсутствие paused/sleeping/shuttingDown/известного конфликта. Физический ввод дополнительно проходит существующий `active && canControl`. Не требовать подключённую мышь для уже существующей ручной кнопки `testAction`; её вызов агентом запрещён. При disconnect текущая последовательность отменяется отдельно.

### 4. Порядок HID-снимка и прерванное удержание

Новый `Sources/MouseCore/ButtonTransitions.swift`:

- `ButtonTransitions(previous: Set<UInt16>, next: Set<UInt16>)` даёт `released` и `pressed`, оба `.sorted()`.
- Извлечь маленький `GestureInputState`, владеющий только `held`, `[UInt16: GestureSession]` и `suppressedUntilRelease`. AppModel использует именно этот тип; тестировать его production-методы, а не копию алгоритма в Harness. Настройки, HIDPacket, `lastGesture` и платформенные эффекты остаются у AppModel.
- Методы: получить переходы; извлечь результаты отпусканий; начать сессию; применить Raw XY; завершить активные горизонтальные сессии для MC; очистить состояние. Имена можно уточнить, но сохранять разделение фаз ниже.
- `finishHorizontalForMissionControl(at:)` посещает только `isSwiping`, в порядке CID, вызывает существующий `release(at:)`, удаляет сессии, добавляет ещё удерживаемые CID в `suppressedUntilRelease`, возвращает outcomes без эффектов.
- `held` не очищается при этом прерывании. Suppressed CID игнорируется до фактического отпускания: ни Raw XY, ни синтетического click. Удаляется suppression при release; новое последующее нажатие работает. Другие вертикальные/ещё не распознанные сессии не удаляются без причины.

`AppModel.handle` для fn0 должен иметь пять явных фаз:

```text
transitions = difference(oldHeld, next), CID sorted
1. Извлечь и удалить все released-сессии, вычислить outcomes.
2. Отправить все horizontal terminal из этих outcomes.
3. Выполнить released-действия (.action), обновляя lastGesture и прежний pulse.
4. Обработать pressed: начать GestureSession или выполнить действие.
5. Записать held = next; убрать suppression для released.
```

Это предотвращает зависимость порядка от Dictionary, когда одна отпущенная кнопка вызывает MC, а другая завершает horizontal. Если MC прерывает удержание во время фазы 3/4, не восстановить затем удалённые сессии из локальной копии. `next` использовать как фактическое множество удержания для suppression; уже отпущенный CID не должен в нём оставаться.

Сохранить: первый Raw XY тактильной панели отбрасывается; обычная кнопка действует на press; направление жеста действует на release; `lastGesture` обновляется один раз; pulse на прежних terminal/gesture-action остаётся, но на каждом вертикальном кадре pulse не добавляется. Отмена вертикали pulse не создаёт.

### 5. Все маршруты `ActionExecutor`

- В ветке `.missionControl` вызвать `requestMissionControl`. AppModel устанавливает callback в init до начала работы transport. Отсутствующий callback должен давать явную ошибку wiring, а не молча ничего не делать.
- Legacy `openSystemApplication` вынести в явно названный `openMissionControlLegacy()` для использования только fallback-контроллером. Не вызывать `execute(.missionControl)` из fallback: это рекурсия.
- Перед `.appExpose`, `.desktop`, `.previousDesktop`, `.nextDesktop`, `.launchpad` вызвать `willExecuteDockAction`, который отменяет вертикальный импульс. `.missionControl` идёт своим путём; иначе повторы ошибочно отменяли бы себя.
- `.copy`, `.paste`, `.undo`, `.redo`, `.back`, `.forward`, `.screenshot`, media/volume, `.spotlight`, `.ring`, запуск приложения из кольца остаются независимыми: ни очереди, ни ожидания вертикального таймера. Системные эффекты сами могут менять фокус; это не основание отменять импульс при неизменном capture.
- Все текущие пути (`execute(RingAction)`, release жеста, press кнопки, `testAction`) используют эту единственную ветку. `testAction` остаётся пользовательским инструментом, автоматом не запускается.
- Для V-04 добавить injected effects у ActionExecutor: trusted, key, media, symbolic, openSystemApplication, openApplication. Production factory создаёт реальные замыкания; тесты явно передают все fakes. Не менять поведение прочих действий. Ни инициализатор теста, ни static-поле не должны выполнять загрузку/вызов production API.

### 6. Lifecycle и взаимодействие с configure

Создать один idempotent helper AppModel для остановки vertical + собственных horizontal-сессий и сброса input state. Вызывать до асинхронного HID release и до возможного early return `captureBusy`:

| Точка | Действие |
|---|---|
| `pause()` | Сначала отмена ввода/vertical, затем существующее configure |
| `togglePause()` | При переходе в paused использовать тот же путь; при resume не возобновлять старую сессию |
| willSleep / sessionDidResignActive | Сначала инвалидировать vertical и закрыть жесты, затем существующий configure |
| `onDisconnected` | Отмена до очистки состояния устройства |
| `shutdown` | Отмена до `executor.cancelPendingActions()` и асинхронного release |
| `switchHost` | Отмена до `service.switchHost`, даже если смена хоста потом не удалась |
| watchdog: потеря Accessibility/Input Monitoring/появление конфликта | Сразу локальная отмена, даже при captureBusy; без прав не отправлять cancelled |
| `configure`, canControl=false | Отмена до проверки captureBusy; оставить captureDirty для существующего аппаратного алгоритма |
| `configure`, назначения/scrollEnabled изменились | Отмена до записи capture; при captureBusy тоже отменить, отложить только сам configure |
| `configure`, canControl=true, active=true, applied-конфигурация совпадает | Сохранить жест, включая обычную смену приложения |

Не отправлять cancelled дважды, если lifecycle helper затем вызывает configure. State-machine должна делать вторую отмену пустой. Возврат AppModel в active и callback аппаратной перенастройки не меняют sessionID старой вертикали обратно.

Для нового горизонтального `began` в `AppModel.post` вызвать `DockGestureController.postHorizontal`: сначала отмена активной вертикали, затем отправка горизонтального кадра. Если MC сам завершает horizontal, это terminal; он не запускает лишнюю отмену уже нового вертикального жеста, поскольку vertical began ещё не отправлен.

### 7. Ошибки и сообщения

Использовать существующий `AppModel.error`. До первой отправки fallback не требует нового предупреждения пользователю, если legacy успешно принял запрос. После started ошибка сообщает «Не удалось завершить жест Mission Control. Повторите действие.»; разрешения используют существующее сообщение Accessibility. Не сообщать «Mission Control открыт» по факту post.

Не писать timestamps, CID, движения или активные приложения в файл/Unified Logging. Порядок и число эффектов проверять в памяти fake-тестов. Дополнительная диагностика реального ввода, если окажется нужна, требует отдельного согласования с INV-3.

## Автоматические тесты: конкретные сценарии

`Tests/MouseCoreTests/MouseCoreTests.swift`: добавить и зарегистрировать методы в `Checks.main()`, обновить итоговое число.

| Предлагаемое имя | Существенная проверка |
|---|---|
| `testMissionControlGestureStartsImmediately` | В t0 единственный vertical began, без advance |
| `testMissionControlGestureFinishesOnce` | t=0, 0.008, 0.064, 0.120, 0.200: монотонный progress, один ended, после конца пусто |
| `testMissionControlGestureSkipsMissedFrames` | После t0 сразу t=0.080: один текущий changed, не десять старых |
| `testMissionControlGestureCancelsWhenStale` | t=0.251: cancelled вместо late ended; cancel снова пуст |
| `testMissionControlGestureRejectsInvalidTime` | NaN/infinity/обратное время не дают NaN, бесконечного таймера или регресса progress; обратный timestamp игнорируется, нечисловой отменяет |
| `testButtonTransitionsReleaseBeforePress` | held={A}, next={B}; отсортированные release/press; одинаковые snapshots ничего не запускают |
| `testMissionControlInterruptSuppressesHeldGesture` | active horizontal A → interrupt → XY → release A: один terminal, ноль action; новое press A начинает новую сессию |
| `testReleasedGesturesAreCollectedBeforeActions` | Два released CID, один MC и один horizontal: все результаты собраны прежде выполнения действий; порядок перестановки входного словаря не влияет |

Новый `Tests/DockGestureChecks/main.swift`: самописный Harness по образцу SymbolicShortcutChecks. Фейковые часы вручную двигаются; scheduler позволяет вызвать отменённый callback намеренно. Отправитель пишет enum-кадры в массив; legacy/key/media/symbolic/application effects пишут только названия вызовов. Permission и preparation results управляемы.

Проверить V-02/V-04 минимум следующими независимыми сценариями:

1. Обычный запрос: prepare → finishHorizontal → began до возврата → changed → ended. Ни fallback, ни sleep.
2. Второй MC во время running не добавляет began, не меняет start/deadline, не отменяет первый. Новый запрос после окончания запускается сразу.
3. Новый MC после staleAfter, но до старого callback: отмена старого, новый began, старый callback пуст.
4. Для каждого lifecycle-reason cancel дважды, затем все сохранённые callbacks: не появляется post. Повторить с потерей permission.
5. Сменить natural setting посередине — все подготовленные кадры сохраняют исходный знак; новая сессия получает новый знак. Горизонтальные эталонные frames неизменны.
6. Недоступная ОС/символы, failure prepare, permission=false, failure после began: точные количества legacy/post/error по таблице состояний.
7. `volumeUp` и `copy` посреди running дают эффект сразу до следующего fake tick. `.nextDesktop`/`.appExpose` дают cancelled перед symbolic effect. `.missionControl` повтор не проходит через общую отмену.
8. `execute(.mouse(.missionControl))` использует тот же callback, что прямой MouseAction; application RingAction использует свой fake open и не вызывается как MC.
9. Новый horizontal began во время running: cancelled vertical → horizontal began; принудительно исполненный старый callback ничего не добавляет.
10. Permission отозван между prepare и began (в fake finishHorizontal): ни vertical began, ни fallback. Подготовленные объекты освобождаются.

V-03 проверяет production-логику GestureInputState. V-04 дополняется статическим аудитом wiring AppModel: настоящий AppModel не создавать в тестах, потому что его init запускает transport/наблюдателей. Не выдавать тест чистого reducer за интеграционный тест macOS.

### Подключение изолированных проверок к scripts/test.sh

Не импортировать executable target приложения и не создавать отдельную копию production-логики в Tests. Пример безопасной схемы сборки в конце текущего скрипта (пути подтвердить по окончательному набору исходников):

```sh
checks_dir="$PWD/.build/dock-gesture-checks"
mkdir -p "$checks_dir"
swiftc -module-cache-path "$PWD/.build/module-cache" \
  -emit-library -emit-module -module-name MouseCore \
  Sources/MouseCore/*.swift \
  -emit-module-path "$checks_dir/MouseCore.swiftmodule" \
  -o "$checks_dir/libMouseCore.dylib"
swiftc -module-cache-path "$PWD/.build/module-cache" \
  -I "$checks_dir" -L "$checks_dir" -lMouseCore \
  -Xlinker -rpath -Xlinker "$checks_dir" \
  Sources/LogiMouseControl/DockGestureController.swift \
  Sources/LogiMouseControl/DockSwipe.swift \
  Sources/LogiMouseControl/ScrollEngine.swift \
  Sources/LogiMouseControl/SymbolicShortcut.swift \
  Sources/LogiMouseControl/ActionExecutor.swift \
  Sources/LogiMouseControl/RingActionIcon.swift \
  Tests/DockGestureChecks/main.swift \
  -o "$checks_dir/DockGestureChecks"
"$checks_dir/DockGestureChecks"
```

`ScrollEngine.swift` нужен при сохранении ссылки на marker; `RingActionIcon.swift` содержит `RingApplication.resolvedURL`. Эти файлы компилируются, но их реальные объекты/effects тестами не создаются. Изменять их ради тестов необязательно. Production-конструкторы sender/executor выделить в явно вызываемую фабрику; tests вызывают только injected init. `Package.swift` менять для этой схемы не нужно.

## Альтернативы

| Вариант | Почему не выбран |
|---|---|
| Очередь MC до конца Space | Противоречит главному критерию пользователя |
| Только исправить release-before-press | Не меняет путь вызова после уже отпущенного свайпа |
| SymbolicShortcut вместо вертикали | Пользователь выбрал другой вариант |
| Все кадры подряд в одном синхронном цикле | Не задаёт длительность жеста, может не дать Dock обработать переход |
| Thread.sleep/usleep между кадрами | Блокирует обработку ввода |
| Встроить всё в ActionExecutor | Он не владеет горизонтальными сессиями; появляется второй независимый владелец Dock |
| Автоповтор MC или terminal после 0,2/0,5 с | Может вмешаться в следующий жест; на текущей macOS польза не подтверждена |

## Влияние на архитектуру

| Вопрос | Ответ |
|---|---|
| Меняются границы модулей или зависимости? | Новые чистые типы в MouseCore и DockGestureController в приложении; внешних зависимостей нет. ActionExecutor делегирует MC |
| Меняются потоки данных, очереди или владение состоянием? | Дополнительное состояние вертикальной последовательности на main, единая отправка Dock; held/sessions инкапсулируются в чистом GestureInputState. Аппаратная очередь прежняя |
| Меняется формат настроек, CLI или идентичность приложения? | Нет |
| Затрагиваются инварианты INV-…? | INV-16 расширяется; INV-1…4, INV-7/8 и INV-10…15 сохраняются |
| Нужен ADR? | ADR-0003 принят; реализация ещё не выполнена |

## Задачи

| ID | Задача | Требования | Файлы и символы | Проверки |
|---|---|---|---|---|
| T-01 | Зафиксировать baseline, статус spec; реализовать чистую модель вертикального импульса и тесты | R-02, R-05, R-08 | Новый MissionControlGesture.swift, MouseCoreTests | V-01 |
| T-02 | Добавить ось и prepare/send в DockSwipe, сохранив горизонтальный формат | R-01, R-07, R-08, R-11 | DockSwipe.swift, frame-типы | V-02, V-05 |
| T-03 | Реализовать DockGestureController, fake clock/scheduler/backend и таблицу состояний | R-02, R-04…R-09 | Новый DockGestureController.swift, DockGestureChecks | V-02 |
| T-04 | Извлечь GestureInputState, разделить отпускания и нажатия, подавлять прерванное удержание | R-03, R-04, R-10 | Новый ButtonTransitions.swift, AppModel.handle/post | V-03 |
| T-05 | Связать все источники MC, fallback и конфликтующие действия; подставные effects executor | R-01, R-06, R-07 | ActionExecutor.swift, AppModel.init/testAction/showRing | V-04 |
| T-06 | Подключить все lifecycle-stop, включая captureBusy и switchHost; сохранить unchanged configure | R-09, R-10 | AppModel.configure/watchdog/pause/togglePause/shutdown/observers | V-02, V-04 |
| T-07 | Подключить новый изолированный runner, выполнить все тесты, debug build, read-only hid-review | R-01…R-11 | scripts/test.sh, Tests, production diff | V-01…V-07 |
| T-08 | Обновить фактическую архитектуру/словарь/граф/журнал/отчёт и статусы; передать ручные сценарии | R-12 | docs, THIRD_PARTY_NOTICES.md при добавлении источников | V-08, M-01…M-08 |
| T-09 | По результатам пользователя скорректировать параметры или зафиксировать неуспех, повторить затронутые проверки | R-01, R-02, R-08, R-12 | spec/plan до кода; параметры и тесты | M-01…M-08, затронутые V |

T-09 не блокирует передачу реализации пользователю, но без ручных результатов нельзя ставить «подтверждено». Если M-01/M-02 не проходят, главный критерий остаётся «не выполнено».

## Команды проверки реализации

```sh
./scripts/test.sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift build --disable-sandbox --scratch-path .build --product LogiMouseControl
git diff --check
python3 -m json.tool docs/specs/knowledge-graph.json > /dev/null
```

Затем обязательное read-only ревью по `.claude/agents/hid-reviewer.md` (через `/hid-review` в среде, где он доступен, либо агент с этими правилами). Оно не должно запускать код или события. Нет изменений Views — preview не нужен. Если изменился только набор документов, как сейчас, выполнять только V-08.

## Риски и откат

- Приватный формат/параметры не совпадают с текущей macOS → M-01/M-03 → корректировать только по наблюдению пользователя, предварительно обновив spec; при невозможности вернуть legacy кодовым откатом.
- Устаревший callback вмешивается в следующий жест → тест с принудительным вызовом отменённой задачи → generation guard и один владелец.
- Профиль меняет capture в момент нажатия → M-08 → не приписывать проблему вертикальному backend и не переписывать HID без нового согласованного scope.
- Потеря Accessibility не даёт отправить cancelled → локальная отмена обязательна, доставка в Dock остаётся неподтверждённой; явно отразить в отчёте.
- Короткий импульс нельзя уверенно прервать вручную во всех lifecycle-сценариях → детерминированные fake-тесты плюс честная пометка непроверенного, без искусственного запуска событий агентом.
- При уже открытом MC семантика может отличаться от legacy → M-06 и запись результата, без эвристического bool и неожиданного обратного жеста.

## Документация к обновлению при реализации

- [x] `architecture.md`: компоненты, поток 4.2, состояние 5.1, остановки 5.2, INV-16, тестовые runners; убрать пометку planned у реализованного P-08, сохранить непроверенное U-15.
- [x] `ontology.md`: перевести планируемые термины в фактические с окончательными символами.
- [x] `knowledge-graph.json`: перенести реализованные компоненты из plannedChanges в фактические services/entities/threading; добавить runner и путь тестов, актуализировать counts по выводу.
- [x] `HARDWARE_VALIDATION.md`: отдельная запись о реализации и передаче M-01…M-08; не отмечать ручные пункты без пользователя.
- [x] `README.md`: способ вызова MC/совместимость, если там есть затронутое описание; не обещать подтверждённую отзывчивость до M-01/M-02.
- [x] `THIRD_PARTY_NOTICES.md`: добавить источники протокола из spec при использовании новых фактов; не копировать чужой код.
- [x] `report.md`: результат каждого AC, R/T/V/M, ошибки команд, ограничения; `spec.md` и реестр — «реализовано» после автопроверок, «подтверждено» только после ручной приёмки.

## Условие завершения исходного запроса на планирование

Документы содержат ожидаемое поведение, API-границы, алгоритмы, порядок действий, таблицу состояний, ошибки, compatibility/fallback, lifecycle, тестовые сценарии и ручные критерии. V-08 проходит. Код приложения, tests и build scripts не изменены и не запускались.

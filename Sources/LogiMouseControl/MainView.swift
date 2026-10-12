import SwiftUI
import MouseCore

private let accent = Color(red: 0.62, green: 0.91, blue: 0.74)
private let canvas = Color(red: 0.065, green: 0.075, blue: 0.08)
private let surface = Color(red: 0.105, green: 0.12, blue: 0.125)

enum Page: String, CaseIterable, Identifiable {
    case overview = "Обзор", scroll = "Прокрутка", pointer = "Указатель и колесо", buttons = "Кнопки и жесты", ring = "Кольцо действий", profiles = "Профили приложений", settings = "Приложение"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"; case .scroll: return "arrow.up.and.down"
        case .pointer: return "cursorarrow.motionlines"; case .buttons: return "computermouse"
        case .ring: return "circle.hexagongrid"; case .profiles: return "app.badge"; case .settings: return "slider.horizontal.3"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return "Ваш MX Master 4. Всё важное — в одном месте."
        case .scroll: return "Точная прокрутка, которая следует за движением руки."
        case .pointer: return "Чувствительность сенсора и характер MagSpeed."
        case .buttons: return "Привычные действия, на своих местах."
        case .ring: return "Шесть быстрых действий рядом с курсором."
        case .profiles: return "Свои настройки для каждого приложения."
        case .settings: return "Работает на вашем Mac. Данные остаются здесь."
        }
    }
}
struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @ViewState<Page> private var page: Page = .overview
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(.white.opacity(0.04))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if !model.conflicts.isEmpty {
                        Notice(icon: "exclamationmark.triangle", title: "Работает другой обработчик мыши", text: "Закройте \(model.conflicts.joined(separator: ", ")), чтобы включить управление здесь. Приложение обнаружит это автоматически.", warning: true)
                    }
                    if !model.accessibility || !model.inputMonitoring { permissions }
                    if let error = model.error, model.inputMonitoring {
                        HStack(alignment: .top) {
                            Notice(icon: "exclamationmark.circle", title: "Нужна проверка", text: error, warning: true)
                            Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).padding(.top, 18)
                        }
                    }
                    switch page {
                    case .overview: overview
                    case .scroll: ScrollSettingsView(preferences: $model.preferences.scroll, changed: model.preferencesChanged)
                    case .pointer: HardwareView()
                    case .buttons: buttons
                    case .ring: ring
                    case .profiles: profiles
                    case .settings: settings
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                        Text("Локально. Без аккаунта, телеметрии и сетевых запросов.")
                    }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 6)
                }.padding(32).frame(maxWidth: 900)
            }.background(canvas)
        }.frame(minWidth: 960, minHeight: 700).background(canvas).preferredColorScheme(.dark).tint(accent)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "computermouse.fill").font(.system(size: 23)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) { Text("LOGI").font(.system(size: 18, weight: .bold, design: .rounded)).tracking(3); Text("MOUSE CONTROL").font(.system(size: 9, weight: .medium)).tracking(1.6).foregroundStyle(.secondary) }
            }.padding(.bottom, 40).padding(.top, 46)
            Text("ВАША МЫШЬ").font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(.secondary).padding(.bottom, 12).padding(.leading, 12)
            ForEach(Page.allCases) { item in
                Button { page = item } label: {
                    HStack(spacing: 11) { Image(systemName: item.symbol).frame(width: 19); Text(item.rawValue).font(.system(size: 12, weight: page == item ? .semibold : .regular)); Spacer() }
                        .foregroundStyle(page == item ? accent : Color.white.opacity(0.62)).padding(.horizontal, 12).padding(.vertical, 13)
                        .background(page == item ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).padding(.bottom, 3)
            }
            Spacer(minLength: 30)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) { Circle().fill(model.active ? accent : .orange).frame(width: 6, height: 6); Text(model.active ? "Управление активно" : "Управление неактивно").font(.system(size: 11, weight: .medium)) }
                Text(model.activeProfileName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Button(model.paused ? "Продолжить" : "Приостановить") { model.togglePause() }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(accent)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            Text("ВЕРСИЯ 0.1 · BLUETOOTH").font(.system(size: 8, weight: .medium)).tracking(1.5).foregroundStyle(.tertiary).padding(.top, 18).padding(.bottom, 20)
        }.padding(.horizontal, 16).frame(width: 210).background(Color(red: 0.08, green: 0.09, blue: 0.095))
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(page.rawValue).font(.system(size: 28, weight: .semibold))
                Text(page.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise").frame(width: 30, height: 30) }.buttonStyle(.plain).help("Перечитать настройки мыши")
        }.padding(.top, 12)
    }
    private var permissions: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "hand.raised").font(.title2).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Один раз разрешите управление").font(.system(size: 14, weight: .semibold))
                    Text("Мониторинг ввода нужен для связи с мышью. Универсальный доступ — для прокрутки и действий кнопок. Ввод с клавиатуры не записывается.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        if !model.inputMonitoring { Button("Мониторинг ввода") { model.grantInputMonitoring() }.buttonStyle(.bordered) }
                        if !model.accessibility { Button("Универсальный доступ") { model.grantAccessibility() }.buttonStyle(.borderedProminent).foregroundStyle(.black) }
                    }.padding(.top, 4)
                }
            }
        }
    }
    private var overview: some View {
        VStack(spacing: 18) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 6) { Circle().fill(model.device.connected ? accent : .orange).frame(width: 6, height: 6); Text(model.device.connected ? "ПОДКЛЮЧЕНА ПО BLUETOOTH" : "ОЖИДАЕМ ПОДКЛЮЧЕНИЯ").font(.system(size: 9, weight: .semibold)).tracking(1.2) }.foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 4) { Text("MX Master 4").font(.system(size: 32, weight: .semibold)); Text(model.active ? "Настроена под вас." : "Настройте под себя.").font(.system(size: 16)).foregroundStyle(.secondary) }
                    HStack(spacing: 18) {
                        Label(model.device.battery.map { "\($0)%" } ?? "Заряд —", systemImage: model.device.charging ? "battery.100percent.bolt" : "battery.75percent")
                        Text(model.device.dpi.map { "\($0) DPI" } ?? "DPI —")
                    }.font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(model.status).font(.system(size: 11)).foregroundStyle(accent.opacity(0.85))
                }.padding(.leading, 26).padding(.vertical, 26)
                Spacer(minLength: 0)
                MouseIllustration(extendedModelID: model.device.extendedModelID).padding(.vertical, 15).frame(width: 220, height: 250).padding(.trailing, 12).accessibilityLabel("Иллюстрация MX Master 4")
            }.frame(maxWidth: .infinity).background(LinearGradient(colors: [surface, Color(red: 0.11, green: 0.16, blue: 0.14)], startPoint: .leading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.07)))
            HStack(spacing: 14) {
                overviewTile("Плавная прокрутка", value: model.preferences.scroll.smooth ? "Включена в настройках" : "Без сглаживания", symbol: "water.waves", target: .scroll)
                overviewTile("Колесо MagSpeed", value: model.device.wheelMode?.title ?? "Ожидаем данные", symbol: "circle.dotted.circle", target: .pointer)
            }
            HStack(spacing: 14) {
                overviewTile("Кнопки и жесты", value: "\(model.device.controls.count) доступных кнопок", symbol: "computermouse", target: .buttons)
                overviewTile("Виброотклик", value: model.device.haptics.map { $0 ? "Интенсивность \(model.device.intensity)%" : "Выключен" } ?? "Ожидаем данные", symbol: "waveform", target: .pointer)
            }
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "leaf").font(.title2).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 5) { Text("Только мышь. Ничего лишнего.").font(.system(size: 14, weight: .medium)); Text("Трекпад работает как обычно. Настройки хранятся на этом Mac.").font(.system(size: 12)).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func overviewTile(_ title: String, value: String, symbol: String, target: Page) -> some View {
        Button { page = target } label: {
            Card {
                VStack(alignment: .leading, spacing: 17) {
                    HStack { Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(accent); Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary) }
                    VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 14, weight: .medium)); Text(value).font(.system(size: 11)).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
    }
    private var buttons: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.device.controls.isEmpty { Notice(icon: "computermouse", title: "Кнопки появятся после подключения", text: "Список считывается с MX Master 4, включая отдельную тактильную панель.") }
            if !model.device.controls.isEmpty {
                Card {
                    ButtonAssignmentsView(controls: model.device.controls, extendedModelID: model.device.extendedModelID,
                                          assignments: $model.preferences.buttons, gestures: $model.preferences.gestures,
                                          changed: model.preferencesChanged, testAction: model.testAction)
                }
            }
            Notice(icon: "hand.draw", title: "Жесты: удерживайте кнопку и двигайте мышь", text: "Назначьте кнопке действие «Жесты» и выберите действие для каждого направления. Жест выполняется, когда вы отпускаете кнопку. Рабочие столы, окна приложения и Spotlight вызываются системными сочетаниями macOS; отключённое сочетание включается только на время действия.")
            if let gesture = model.lastGesture {
                HStack(spacing: 8) {
                    Image(systemName: gesture.direction.symbol).foregroundStyle(accent)
                    Text("Последний жест: \(gesture.direction.title.lowercased()) → \(gesture.action.title)").font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.horizontal, 4)
            }
        }
    }
    private var ring: some View {
        VStack(spacing: 18) {
            Card {
                HStack {
                    ActionRingView(actions: model.preferences.ring, select: { _ in }, cancel: {}, hover: {}).scaleEffect(0.78).frame(width: 265, height: 265).allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Действия под большим пальцем").font(.system(size: 19, weight: .medium))
                        Text("Назначьте «Кольцо действий» тактильной панели или другой кнопке. Наведите курсор и нажмите на действие.").font(.system(size: 12)).foregroundStyle(.secondary)
                        Button("Открыть кольцо") { model.showRing() }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Настройка позиций").font(.system(size: 15, weight: .medium))
                        Text("Выберите обычное действие или назначьте отдельное приложение для каждой позиции.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(.bottom, 2)
                    ForEach(0..<6) { index in
                        HStack {
                            Text("Позиция \(index + 1)").foregroundStyle(.secondary)
                            Spacer()
                            Menu {
                                ForEach(MouseAction.ringChoices) { action in
                                    Button { model.preferences.ring[index] = .mouse(action); model.save() } label: { Label(action.title, systemImage: action.symbol) }
                                }
                            } label: {
                                Label {
                                    Text(model.preferences.ring[index].title).lineLimit(1)
                                } icon: {
                                    RingActionIcon(action: model.preferences.ring[index], size: 18)
                                }
                            }.frame(width: 190, alignment: .trailing)
                            Button("Приложение…", systemImage: "app.badge.plus") { model.chooseRingApplication(at: index) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }
    private var profiles: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Автоматическое переключение при смене приложения.").font(.system(size: 12)).foregroundStyle(.secondary); Spacer(); Button("Добавить приложение", systemImage: "plus") { model.addProfile() }.buttonStyle(.bordered) }
            if model.preferences.profiles.isEmpty { Notice(icon: "app.dashed", title: "Пока один профиль для всего", text: "Добавьте приложение, чтобы настроить скорость и направление прокрутки отдельно. Например, отключить сглаживание в игре.") }
            ForEach($model.preferences.profiles) { $profile in
                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack { Text(profile.name).font(.system(size: 16, weight: .medium)); Spacer(); Button("Удалить", role: .destructive) { model.preferences.profiles.removeAll { $0.id == profile.id }; model.preferencesChanged() } }
                        ScrollSettingsView(preferences: $profile.scroll, changed: model.preferencesChanged, compact: true)
                        DisclosureGroup("Кнопки этого профиля") {
                            ForEach(model.device.controls) { control in
                                HStack { Text(control.name); Spacer(); Picker(control.name, selection: Binding(get: { profile.buttons[String(control.id)] ?? .system }, set: { profile.buttons[String(control.id)] = $0; model.preferencesChanged() })) { ForEach(MouseAction.allCases.filter { $0 != .gestures || control.rawXY }) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 200) }.padding(.vertical, 5)
                            }
                        }
                    }
                }
            }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                VStack(spacing: 20) {
                    SettingRow("Запускать при входе", detail: "Настройки мыши будут доступны сразу после входа в macOS.") { Toggle("Запускать при входе", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin)).labelsHidden().toggleStyle(.switch) }
                    Divider()
                    SettingRow("Проверка подключения", detail: "Перечитать состояние и возможности устройства.") { Button("Проверить") { model.refresh() } }
                    Divider()
                    SettingRow("Работа в строке меню", detail: "Закройте окно — приложение продолжит работать. Для выхода используйте меню мыши.") { Image(systemName: "menubar.rectangle").foregroundStyle(accent).font(.title2) }
                }
            }
            if model.device.hostCount > 1 {
                Card {
                    SettingRow("Easy-Switch", detail: "Мышь отключится от этого Mac и перейдёт на выбранный канал.") {
                        ForEach(0..<model.device.hostCount, id: \.self) { host in Button("\(host + 1)") { model.switchHost(host) }.disabled(host == model.device.currentHost || !model.conflicts.isEmpty) }
                    }
                }
            }
            Notice(icon: "lock.shield", title: "Приватность заложена в приложение", text: "Нет аналитики, аккаунтов, рекламы, автоматических обновлений и сетевого клиента. Сохраняются только настройки. Название активного приложения используется в памяти для выбора профиля; история не записывается.")
            Notice(icon: "info.circle", title: "Границы версии 0.1", text: "Поддерживается MX Master 4 по Bluetooth. Flow, магазин плагинов, Smart Actions и обновление прошивки пока не реализованы. Это самостоятельное приложение, не продукт Logitech. Аппаратные функции требуют проверки на вашей мыши.")
            if !model.device.warnings.isEmpty { Text(model.device.warnings.joined(separator: "\n")).font(.caption).foregroundStyle(.orange) }
            Text("Протокол: OpenLogi / openlogi-hidpp. Благодарности и лицензии включены в приложение.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct ScrollSettingsView: View {
    @Binding var preferences: ScrollPreferences
    let changed: () -> Void
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                VStack(spacing: 20) {
                    SettingRow("Обрабатывать прокрутку", detail: "Отдельно от трекпада и других мышей.") { Toggle("Обрабатывать прокрутку", isOn: $preferences.enabled).labelsHidden().toggleStyle(.switch) }
                    Divider()
                    SettingRow("Плавный скролл", detail: "Мягкое движение без потери коротких шагов.") { Toggle("Плавный скролл", isOn: $preferences.smooth).labelsHidden().toggleStyle(.switch) }
                    Divider()
                    SettingRow("Естественное направление", detail: "Колесо перемещает содержимое страницы.") { Toggle("Естественное направление", isOn: $preferences.natural).labelsHidden().toggleStyle(.switch) }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("Скорость прокрутки"); Spacer(); Text(String(format: "%.1f×", preferences.speed)).monospacedDigit().foregroundStyle(.secondary) }
                        Slider(value: $preferences.speed, in: 0.2...4, step: 0.1)
                    }
                    if preferences.smooth {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text("Характер движения"); Spacer(); Text(preferences.smoothness < 0.07 ? "Точнее" : "Мягче").foregroundStyle(.secondary) }
                            Slider(value: $preferences.smoothness, in: 0.015...0.18)
                            HStack { Text("Быстрый отклик"); Spacer(); Text("Мягкое затухание") }.font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }.font(.system(size: 13))
            }
            Card {
                VStack(spacing: 20) {
                    SettingRow("Боковое колесо", detail: "Горизонтальная прокрутка с независимым направлением.") { Toggle("Естественное направление бокового колеса", isOn: $preferences.horizontalNatural).labelsHidden().toggleStyle(.switch) }
                    HStack { Text("Скорость"); Slider(value: $preferences.horizontalSpeed, in: 0.2...4, step: 0.1); Text(String(format: "%.1f×", preferences.horizontalSpeed)).monospacedDigit().frame(width: 38) }.font(.system(size: 13))
                }
            }
            if !compact {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Попробуйте здесь", systemImage: "arrow.down").font(.system(size: 14, weight: .medium))
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                ForEach(1...20, id: \.self) { index in HStack(alignment: .top, spacing: 16) { Text(String(format: "%02d", index)).font(.system(.title3, design: .monospaced)).foregroundStyle(accent.opacity(0.5)); VStack(alignment: .leading, spacing: 5) { Text(index % 2 == 0 ? "Медленно. Точно. Плавно." : "Прокрутка в вашем ритме.").font(.system(size: 14, weight: .medium)); Text("Прокрутите колесо, смените направление и попробуйте свободное вращение.").font(.system(size: 12)).foregroundStyle(.secondary) } } }
                            }.padding(16)
                        }.frame(height: 175).background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }.onChange(of: preferences) { _, _ in changed() }
    }
}
struct HardwareView: View {
    @EnvironmentObject private var model: AppModel
    @ViewState<Double> private var dpi = 1000.0
    @ViewState<WheelMode> private var mode: WheelMode = .smartShift
    @ViewState<Double> private var threshold = 30.0
    @ViewState<Double> private var torque = 50.0
    @ViewState<Bool> private var haptics = true
    @ViewState<Double> private var intensity = 50.0
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.device.connected { Notice(icon: "antenna.radiowaves.left.and.right", title: "Подключите MX Master 4", text: "Аппаратные настройки станут доступны после чтения возможностей мыши.") }
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    SettingRow("Чувствительность сенсора", detail: "Текущее значение: \(model.device.dpi.map { "\($0) DPI" } ?? "не прочитано").") { Text("\(Int(dpi))").font(.system(size: 25, weight: .light, design: .rounded)).monospacedDigit(); Text("DPI").font(.caption).foregroundStyle(.secondary) }
                    Slider(value: $dpi, in: Double(model.device.dpiValues.first ?? 200)...Double(max(201, model.device.dpiValues.last ?? 8000)), step: 50)
                    HStack { Text("Точнее"); Spacer(); Text("Быстрее") }.font(.caption).foregroundStyle(.secondary)
                    Button("Применить DPI") { model.setDPI(Int(dpi)) }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(!model.device.dpiValues.contains(Int(dpi)))
                }
            }.disabled(model.device.dpi == nil || model.busy || !model.conflicts.isEmpty)
            Card {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Колесо MagSpeed").font(.system(size: 16, weight: .medium))
                    Picker("Режим колеса", selection: $mode) { ForEach(WheelMode.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    if mode == .smartShift {
                        Text("Само переходит в свободное вращение при быстром движении.").font(.caption).foregroundStyle(.secondary)
                        HStack { Text("Порог переключения"); Spacer(); Text("\(Int(threshold))").monospacedDigit().foregroundStyle(.secondary) }.font(.system(size: 13))
                        Slider(value: $threshold, in: 1...254, step: 1)
                    }
                    if model.device.torque != nil {
                        HStack { Text("Сила отсечек"); Spacer(); Text("\(Int(torque))%").monospacedDigit().foregroundStyle(.secondary) }.font(.system(size: 13))
                        Slider(value: $torque, in: 1...100, step: 1)
                    }
                    Button("Применить режим") { model.setWheel(mode, threshold: Int(threshold), torque: model.device.torque == nil ? nil : Int(torque)) }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                }
            }.disabled(model.device.wheelMode == nil || model.busy || !model.conflicts.isEmpty)
            Card {
                VStack(alignment: .leading, spacing: 20) {
                    SettingRow("Тактильный отклик", detail: "Для кольца действий и жестов.") { Toggle("Тактильный отклик", isOn: $haptics).labelsHidden().toggleStyle(.switch) }
                    HStack { Text("Интенсивность"); Slider(value: $intensity, in: 0...100, step: 25); Text("\(Int(intensity))%").monospacedDigit().frame(width: 40) }.font(.system(size: 13))
                    HStack { Button("Применить") { model.setHaptics(haptics, intensity: Int(intensity)) }.buttonStyle(.borderedProminent).foregroundStyle(.black); Button("Почувствовать") { model.testHaptics() }.disabled(model.device.haptics != true) }
                }
            }.disabled(model.device.haptics == nil || model.busy || !model.conflicts.isEmpty)
            Text("Изменения сохраняются только после подтверждения от мыши.").font(.caption).foregroundStyle(.secondary)
        }.onAppear(perform: synchronize).onChange(of: model.busy) { _, busy in if !busy { synchronize() } }.onChange(of: model.device.connected) { _, _ in synchronize() }
    }
    private func synchronize() { dpi = Double(model.device.dpi ?? 1000); mode = model.device.wheelMode ?? .smartShift; threshold = Double(model.device.threshold); torque = Double(model.device.torque ?? 50); haptics = model.device.haptics ?? true; intensity = Double(model.device.intensity) }
}
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(surface, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.055), lineWidth: 1)) }
}
struct SettingRow<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var content: Content
    init(_ title: String, detail: String, @ViewBuilder content: () -> Content) { self.title = title; self.detail = detail; self.content = content() }
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 13, weight: .medium)); Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 10); content
        }
    }
}
struct Notice: View {
    let icon: String
    let title: String
    let text: String
    var warning = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 19)).foregroundStyle(warning ? .orange : accent).padding(.top, 2)
            VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 13, weight: .medium)); Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 0)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background((warning ? Color.orange : accent).opacity(0.055), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke((warning ? Color.orange : accent).opacity(0.13)))
    }
}

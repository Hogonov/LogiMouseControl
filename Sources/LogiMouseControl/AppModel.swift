import AppKit
import SwiftUI
import ServiceManagement
import MouseCore

final class AppModel: ObservableObject {
    @Published var device = DeviceSnapshot()
    @Published var preferences: Preferences
    @Published var accessibility = AXIsProcessTrusted()
    @Published var inputMonitoring = CGPreflightListenEventAccess()
    @Published var status = "Ищем MX Master 4…"
    @Published var error: String?
    @Published var active = false
    @Published var paused = false
    @Published var busy = false
    @Published var conflicts: [String] = []
    @Published var activeProfileName = "Общий профиль"
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var connectedSince: Date?
    private let service = DeviceService()
    private let scroll = ScrollEngine()
    private let executor = ActionExecutor()
    private let ring = RingController()
    private var monitor: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var frontmostID = ""
    private var captureBusy = false
    private var captureDirty = false
    private var shuttingDown = false
    private var sleeping = false
    private var held: Set<UInt16> = []
    private var gestureState: [UInt16: GestureAccumulator] = [:]
    private var startup = true
    private var watchdogTick = 0
    private var eventButtons: [String: MouseAction] = [:]
    private var appliedScroll: Bool?
    private var appliedButtons: [String: MouseAction] = [:]

    init() {
        let data = UserDefaults.standard.data(forKey: "preferences.v1")
        var saved = data.flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        saved.sanitize(); preferences = saved
        service.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            self.device = snapshot
            if snapshot.connected { self.status = self.active ? "Настройки применены" : "MX Master 4 подключена" }
        }
        service.onError = { [weak self] message in self?.error = message }
        service.onDisconnected = { [weak self] in
            guard let self else { return }
            self.active = false; self.scroll.stop(); self.ring.close(); self.held = []; self.gestureState = [:]
            self.appliedScroll = nil; self.appliedButtons = [:]
            self.connectedSince = nil; self.status = "Ожидаем подключения MX Master 4"
        }
        service.onConnected = { [weak self] in self?.didConnect() }
        service.onEvent = { [weak self] in self?.handle($0) }
        scroll.onFailure = { [weak self] in self?.pause() }
        executor.onError = { [weak self] in self?.error = $0 }
        executor.showRing = { [weak self] in self?.showRing() }
        frontmostID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self.frontmostID = app.bundleIdentifier ?? ""; self.scroll.stop(); self.ring.close(); self.configure()
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }; self.sleeping = true; self.active = false; self.scroll.stop(); self.ring.close(); self.configure()
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }; self.sleeping = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh(); self.configure() }
            })
        }
        updatePermissions()
        service.transport.start()
        monitor = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.watchdog() }
    }
    var effectiveScroll: ScrollPreferences { preferences.profiles.first { $0.id == frontmostID }?.scroll ?? preferences.scroll }
    var effectiveButtons: [String: MouseAction] { preferences.profiles.first { $0.id == frontmostID }?.buttons ?? preferences.buttons }
    var canControl: Bool { device.connected && accessibility && inputMonitoring && conflicts.isEmpty && !paused && !sleeping && !shuttingDown }
    private func didConnect() {
        connectedSince = Date(); error = nil
        // Default useful MX actions, only for controls actually advertised by this device.
        if startup && preferences.buttons.isEmpty {
            for control in device.controls {
                switch control.id {
                case 0xc3: preferences.buttons[String(control.id)] = .gestures
                case 0x1a0: preferences.buttons[String(control.id)] = .ring
                case 0x53, 0xbd, 0xce, 0xdb: preferences.buttons[String(control.id)] = .back
                case 0x56, 0xcf: preferences.buttons[String(control.id)] = .forward
                default: break
                }
            }
            save()
        }
        startup = false
        // Reapply only hardware preferences explicitly saved after a successful user write.
        if conflicts.isEmpty {
            if let dpi = preferences.desiredDPI { setDPI(dpi) }
            if let mode = preferences.desiredWheel { setWheel(mode, threshold: preferences.desiredThreshold, torque: preferences.desiredTorque) }
            if let enabled = preferences.desiredHaptics { setHaptics(enabled, intensity: preferences.desiredIntensity) }
        }
        configure()
    }
    func save() {
        preferences.sanitize()
        do { UserDefaults.standard.set(try JSONEncoder().encode(preferences), forKey: "preferences.v1") }
        catch { self.error = "Не удалось сохранить настройки локально." }
    }
    func preferencesChanged() { save(); configure() }
    func refresh() {
        updatePermissions()
        if device.connected { service.refresh() } else { service.transport.retry(); service.refresh(discover: true) }
    }
    private func updatePermissions() {
        accessibility = AXIsProcessTrusted(); inputMonitoring = CGPreflightListenEventAccess()
        conflicts = NSWorkspace.shared.runningApplications.compactMap { app -> String? in
            let id = (app.bundleIdentifier ?? "").lowercased()
            let name = (app.localizedName ?? "").lowercased()
            guard id != Bundle.main.bundleIdentifier?.lowercased() else { return nil }
            let helperIDs: Set<String> = ["com.nuebling.mac-mouse-fix.helper", "org.openlogi.agent", "org.openlogi.overlay"]
            if helperIDs.contains(id) || id.hasPrefix("com.logi.optionsplus") || id.hasPrefix("com.logitech.logioptions") || name == "logi options+" { return app.localizedName ?? "Другой драйвер мыши" }
            return nil
        }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }
    private func watchdog() {
        guard !shuttingDown else { return }
        let previous = (accessibility, inputMonitoring, conflicts)
        updatePermissions()
        if previous.0 != accessibility || previous.1 != inputMonitoring || previous.2 != conflicts { configure() }
        if !device.connected { service.transport.retry() }
        if active && !captureBusy {
            service.checkCaptureSafety { [weak self] safe in if !safe { self?.pause() } }
        }
        watchdogTick += 1
        if watchdogTick % 30 == 0 && device.connected && !busy && !captureBusy { service.refresh() }
    }
    func grantAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Privacy_Accessibility")
    }
    func grantInputMonitoring() { _ = CGRequestListenEventAccess(); openPrivacy("Privacy_ListenEvent") }
    private func openPrivacy(_ pane: String) { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) } }
    func configure() {
        guard !shuttingDown else { return }
        if captureBusy { captureDirty = true; return }
        scroll.stop(); held = []; gestureState = [:]
        scroll.preferences = effectiveScroll
        activeProfileName = preferences.profiles.first { $0.id == frontmostID }?.name ?? "Общий профиль"
        guard device.connected else { return }
        if canControl && active && appliedScroll == effectiveScroll.enabled && appliedButtons == effectiveButtons { return }
        captureBusy = true
        if canControl {
            let buttons = effectiveButtons
            let scrollEnabled = effectiveScroll.enabled
            service.configureCapture(scroll: scrollEnabled, buttons: buttons) { [weak self] success in
                guard let self else { return }
                self.captureBusy = false; self.active = success && self.canControl
                self.eventButtons = success ? buttons : [:]
                self.appliedScroll = success ? scrollEnabled : nil
                self.appliedButtons = success ? buttons : [:]
                self.status = success ? "Настройки применены" : "Обработка не включена"
                if self.captureDirty { self.captureDirty = false; self.configure() }
            }
        } else {
            active = false
            service.release { [weak self] _ in
                guard let self else { return }; self.captureBusy = false; self.eventButtons = [:]; self.appliedScroll = nil; self.appliedButtons = [:]
                self.status = self.paused ? "Обработка приостановлена" : "Ожидаем разрешений"
                if self.captureDirty { self.captureDirty = false; self.configure() }
            }
        }
    }
    func pause() { paused = true; scroll.stop(); ring.close(); configure() }
    func togglePause() { paused.toggle(); configure() }
    func setDPI(_ value: Int) {
        guard conflicts.isEmpty else { return }; busy = true
        service.setDPI(value) { [weak self] success in
            guard let self else { return }; self.busy = false
            if success { self.preferences.desiredDPI = value; self.save(); self.error = nil }
        }
    }
    func setWheel(_ mode: WheelMode, threshold: Int, torque: Int?) {
        guard conflicts.isEmpty else { return }; busy = true
        service.setWheel(mode, threshold: threshold, torque: torque) { [weak self] success in
            guard let self else { return }; self.busy = false
            if success { self.preferences.desiredWheel = mode; self.preferences.desiredThreshold = threshold; self.preferences.desiredTorque = torque; self.save(); self.error = nil }
        }
    }
    func setHaptics(_ enabled: Bool, intensity: Int) {
        guard conflicts.isEmpty else { return }; busy = true
        service.setHaptics(enabled, intensity: intensity) { [weak self] success in
            guard let self else { return }; self.busy = false
            if success { self.preferences.desiredHaptics = enabled; self.preferences.desiredIntensity = intensity; self.save(); self.error = nil }
        }
    }
    func testHaptics() { service.pulse() }
    func showRing() {
        guard accessibility else { grantAccessibility(); return }
        scroll.stop()
        ring.show(actions: preferences.ring, execute: { [weak self] action in self?.executor.execute(action); self?.service.pulse() }, pulse: { [weak self] in self?.service.pulse(4) })
    }
    func switchHost(_ host: Int) {
        active = false; scroll.stop(); ring.close()
        service.switchHost(host) { [weak self] success in if !success { self?.configure() } }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { self.error = "Не удалось изменить запуск при входе: \(error.localizedDescription)" }
    }
    func testAction(_ action: MouseAction) { executor.execute(action) }
    func addProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.prompt = "Добавить профиль"
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        guard !preferences.profiles.contains(where: { $0.id == id }) else { return }
        preferences.profiles.append(AppProfile(id: id, name: url.deletingPathExtension().lastPathComponent, scroll: preferences.scroll, buttons: preferences.buttons)); preferencesChanged()
    }
    private func handle(_ event: HIDPacket) {
        guard active, canControl else { return }
        if event.feature == device.features[0x2121], event.function == 0, event.payload.count >= 3 {
            let high = event.payload[0] & 16 != 0
            scroll.feed(vertical: Double(signedWord(event.payload, 1)) / (high ? device.verticalMultiplier : 1) * 40)
        } else if event.feature == device.features[0x2150], event.function == 0 {
            scroll.feed(horizontal: Double(signedWord(event.payload)) / device.horizontalResolution * 800)
        } else if event.feature == device.features[0x1b04] {
            if event.function == 0, event.payload.count >= 8 {
                let next = Set(stride(from: 0, to: 8, by: 2).map { word(event.payload, $0) }.filter { $0 != 0 })
                for id in next.subtracting(held) {
                    scroll.stop()
                    let action = eventButtons[String(id)] ?? .system
                    if action == .gestures { gestureState[id] = GestureAccumulator(discardFirst: id == 0x1a0) }
                    else { executor.execute(action) }
                }
                for id in held.subtracting(next) {
                    if let gesture = gestureState.removeValue(forKey: id) { executor.gesture(gesture.direction); service.pulse() }
                }
                held = next
            } else if event.function == 1, event.payload.count >= 4 {
                for id in Array(gestureState.keys) { gestureState[id]?.add(dx: Double(signedWord(event.payload)), dy: Double(signedWord(event.payload, 2))) }
            }
        }
    }
    func shutdown(_ completion: @escaping () -> Void) {
        shuttingDown = true; active = false; monitor?.invalidate(); scroll.stop(); ring.close()
        executor.cancelPendingActions()
        service.release { [weak self] success in
            guard let self else { completion(); return }
            self.service.finishGuardian(clean: success) { self.service.transport.stop(); completion() }
        }
    }
}

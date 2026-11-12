import AppKit
import Carbon.HIToolbox
import MouseCore

final class ActionExecutor {
    // WindowServer symbolic hotkey IDs; fallbacks are the macOS defaults (arrow keys carry Fn).
    private lazy var spotlight = SymbolicShortcut(hotKey: 64, name: "Spotlight")
    private lazy var appExpose = SymbolicShortcut(hotKey: 33, name: "Окна приложения", fallback: .init(key: 125, modifiers: 0x840000))
    private lazy var desktop = SymbolicShortcut(hotKey: 36, name: "Показать рабочий стол", fallback: .init(key: 103, modifiers: 0x800000))
    private lazy var previousDesktop = SymbolicShortcut(hotKey: 79, name: "Рабочий стол слева", fallback: .init(key: 123, modifiers: 0x840000))
    private lazy var nextDesktop = SymbolicShortcut(hotKey: 81, name: "Рабочий стол справа", fallback: .init(key: 124, modifiers: 0x840000))
    private var shortcuts: [SymbolicShortcut] { [spotlight, appExpose, desktop, previousDesktop, nextDesktop] }
    struct Effects {
        let trusted: () -> Bool
        let key: (CGKeyCode, CGEventFlags) -> Void
        let media: (Int) -> Void
        let symbolic: (String) -> Void
        let systemApplication: (String, String) -> Void
        let application: (RingApplication) -> Void
    }
    private let effects: Effects?
    init(effects: Effects? = nil) { self.effects = effects }
    var showRing: (() -> Void)?
    var onError: ((String) -> Void)?
    var requestMissionControl: (() -> Void)?
    var willExecuteDockAction: (() -> Void)?
    func execute(_ ringAction: RingAction) {
        switch ringAction {
        case .mouse(let action): execute(action)
        case .application(let application): openApplication(application)
        }
    }
    func execute(_ action: MouseAction) {
        guard (effects?.trusted() ?? AXIsProcessTrusted()) else { onError?("Разрешите Универсальный доступ для выполнения действий мыши."); return }
        switch action {
        // Gestures are resolved per direction by AppModel before reaching here.
        case .system, .none, .gestures: break
        case .ring: showRing?()
        case .missionControl:
            guard let requestMissionControl else { onError?("Mission Control не подключён к обработчику действий."); return }
            requestMissionControl()
        case .appExpose: willExecuteDockAction?(); symbolic("appExpose") { self.appExpose }
        case .desktop: willExecuteDockAction?(); symbolic("desktop") { self.desktop }
        case .previousDesktop: willExecuteDockAction?(); symbolic("previousDesktop") { self.previousDesktop }
        case .nextDesktop: willExecuteDockAction?(); symbolic("nextDesktop") { self.nextDesktop }
        case .launchpad: willExecuteDockAction?(); openLaunchpad()
        case .spotlight: symbolic("spotlight") { self.spotlight }
        case .back: key(33, .maskCommand)
        case .forward: key(30, .maskCommand)
        case .copy: key(8, .maskCommand)
        case .paste: key(9, .maskCommand)
        case .undo: key(6, .maskCommand)
        case .redo: key(6, [.maskCommand, .maskShift])
        case .screenshot: key(21, [.maskCommand, .maskShift])
        case .playPause: media(16)
        case .volumeUp: media(0)
        case .volumeDown: media(1)
        case .mute: media(7)
        case .nextTrack: media(17)
        case .previousTrack: media(18)
        }
    }
    func cancelPendingActions() {
        guard effects == nil else { return }
        for shortcut in shortcuts { shortcut.cancelPendingRestore { [weak self] in self?.onError?($0) } }
    }
    func openMissionControlLegacy() { openSystemApplication("/System/Applications/Mission Control.app", name: "Mission Control") }
    private func symbolic(_ name: String, shortcut: () -> SymbolicShortcut) {
        if let effects { effects.symbolic(name) } else { perform(shortcut()) }
    }
    private func openLaunchpad() {
        if let effects { effects.systemApplication("/System/Applications/Launchpad.app", "Launchpad") }
        else { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Launchpad.app")) }
    }
    private func perform(_ shortcut: SymbolicShortcut) {
        shortcut.perform { [weak self] in self?.onError?($0) }
    }
    // Open the system app even when its keyboard shortcut is disabled or remapped.
    // Reopen events also reach an already-running instance (not just activation).
    private func openSystemApplication(_ path: String, name: String) {
        if let effects { effects.systemApplication(path, name); return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async { self?.onError?("Не удалось открыть \(name): \(error.localizedDescription)") }
        }
    }
    private func openApplication(_ application: RingApplication) {
        if let effects { effects.application(application); return }
        guard let url = application.resolvedURL else {
            onError?("Приложение \(application.name) не найдено. Выберите его заново в настройках кольца.")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async { self?.onError?("Не удалось открыть \(application.name): \(error.localizedDescription)") }
        }
    }
    private func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
        if let effects { effects.key(code, flags); return }
        let source = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags; up?.flags = flags
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
    }
    private func media(_ code: Int) {
        if let effects { effects.media(code); return }
        for state in [0x0a, 0x0b] {
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)), timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: (code << 16) | (state << 8), data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

import Foundation

public enum MouseAction: String, Codable, CaseIterable, Identifiable {
    case system, none, back, forward, missionControl, appExpose, desktop, launchpad, spotlight, copy, paste, undo, redo, screenshot, playPause, volumeUp, volumeDown, mute, nextTrack, previousTrack, ring, gestures
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: return "Как в системе"; case .none: return "Ничего"; case .back: return "Назад"; case .forward: return "Вперёд"
        case .missionControl: return "Mission Control"; case .appExpose: return "Окна приложения"; case .desktop: return "Показать рабочий стол"
        case .launchpad: return "Приложения"; case .spotlight: return "Spotlight"; case .copy: return "Копировать"; case .paste: return "Вставить"
        case .undo: return "Отменить"; case .redo: return "Повторить"; case .screenshot: return "Снимок области"
        case .playPause: return "Пуск / пауза"; case .volumeUp: return "Громче"; case .volumeDown: return "Тише"; case .mute: return "Без звука"
        case .nextTrack: return "Следующий трек"; case .previousTrack: return "Предыдущий трек"; case .ring: return "Кольцо действий"; case .gestures: return "Жесты"
        }
    }
    public var symbol: String {
        switch self {
        case .system: return "cursorarrow"; case .none: return "minus"; case .back: return "arrow.left"; case .forward: return "arrow.right"
        case .missionControl: return "rectangle.3.group"; case .appExpose: return "macwindow.on.rectangle"; case .desktop: return "desktopcomputer"
        case .launchpad: return "square.grid.3x3"; case .spotlight: return "magnifyingglass"; case .copy: return "doc.on.doc"; case .paste: return "doc.on.clipboard"
        case .undo: return "arrow.uturn.backward"; case .redo: return "arrow.uturn.forward"; case .screenshot: return "viewfinder"
        case .playPause: return "playpause.fill"; case .volumeUp: return "speaker.plus.fill"; case .volumeDown: return "speaker.minus.fill"
        case .mute: return "speaker.slash.fill"; case .nextTrack: return "forward.end.fill"; case .previousTrack: return "backward.end.fill"
        case .ring: return "circle.hexagongrid"; case .gestures: return "hand.draw"
        }
    }
    public static var ringChoices: [Self] { allCases.filter { ![.system, .ring, .gestures].contains($0) } }
}
public struct ScrollPreferences: Codable, Equatable {
    public var enabled = true
    public var smooth = true
    public var natural = true
    public var horizontalNatural = true
    public var speed: Double = 1
    public var horizontalSpeed: Double = 1
    public var smoothness: Double = 0.07
    public init() {}
    public mutating func sanitize() {
        speed = speed.isFinite ? max(0.2, min(4, speed)) : 1
        horizontalSpeed = horizontalSpeed.isFinite ? max(0.2, min(4, horizontalSpeed)) : 1
        smoothness = smoothness.isFinite ? max(0.015, min(0.18, smoothness)) : 0.07
    }
}
public struct AppProfile: Codable, Identifiable, Equatable {
    public var id: String // bundle identifier; no activity history is stored
    public var name: String
    public var scroll = ScrollPreferences()
    public var buttons: [String: MouseAction] = [:]
    public init(id: String, name: String, scroll: ScrollPreferences, buttons: [String: MouseAction]) { self.id = id; self.name = name; self.scroll = scroll; self.buttons = buttons }
}
public struct Preferences: Codable {
    public var scroll = ScrollPreferences()
    public var buttons: [String: MouseAction] = [:]
    public var ring: [MouseAction] = [.missionControl, .spotlight, .screenshot, .copy, .paste, .playPause]
    public var profiles: [AppProfile] = []
    public var desiredDPI: Int?
    public var desiredWheel: WheelMode?
    public var desiredThreshold: Int = 30
    public var desiredTorque: Int?
    public var desiredHaptics: Bool?
    public var desiredIntensity: Int = 50
    public init() {}
    public mutating func sanitize() {
        scroll.sanitize()
        for i in profiles.indices { profiles[i].scroll.sanitize() }
        if let dpi = desiredDPI { desiredDPI = max(200, min(8000, dpi / 50 * 50)) }
        desiredThreshold = max(1, min(254, desiredThreshold))
        if let torque = desiredTorque { desiredTorque = max(1, min(100, torque)) }
        desiredIntensity = max(0, min(100, desiredIntensity))
        if ring.count != 6 || ring.contains(where: { !MouseAction.ringChoices.contains($0) }) { ring = Preferences().ring }
    }
}
public struct GestureAccumulator {
    private var x = 0.0, y = 0.0
    private var discardFirst: Bool
    public init(discardFirst: Bool) { self.discardFirst = discardFirst }
    public mutating func add(dx: Double, dy: Double) {
        if discardFirst { discardFirst = false; return }
        x += dx; y += dy
    }
    public var direction: String? {
        guard max(abs(x), abs(y)) > 60 else { return nil }
        return abs(x) > abs(y) ? (x > 0 ? "right" : "left") : (y > 0 ? "down" : "up")
    }
}

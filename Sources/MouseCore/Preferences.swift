import Foundation

public enum MouseAction: String, Codable, CaseIterable, Identifiable {
    case system, none, back, forward, missionControl, appExpose, desktop, previousDesktop, nextDesktop, launchpad, spotlight, copy, paste, undo, redo, screenshot, playPause, volumeUp, volumeDown, mute, nextTrack, previousTrack, ring, gestures
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: return "Как в системе"; case .none: return "Ничего"; case .back: return "Назад"; case .forward: return "Вперёд"
        case .missionControl: return "Mission Control"; case .appExpose: return "Окна приложения"; case .desktop: return "Показать рабочий стол"
        case .previousDesktop: return "Рабочий стол слева"; case .nextDesktop: return "Рабочий стол справа"
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
        case .previousDesktop: return "rectangle.lefthalf.inset.filled.arrow.left"; case .nextDesktop: return "rectangle.righthalf.inset.filled.arrow.right"
        case .launchpad: return "square.grid.3x3"; case .spotlight: return "magnifyingglass"; case .copy: return "doc.on.doc"; case .paste: return "doc.on.clipboard"
        case .undo: return "arrow.uturn.backward"; case .redo: return "arrow.uturn.forward"; case .screenshot: return "viewfinder"
        case .playPause: return "playpause.fill"; case .volumeUp: return "speaker.plus.fill"; case .volumeDown: return "speaker.minus.fill"
        case .mute: return "speaker.slash.fill"; case .nextTrack: return "forward.end.fill"; case .previousTrack: return "backward.end.fill"
        case .ring: return "circle.hexagongrid"; case .gestures: return "hand.draw"
        }
    }
    public static var ringChoices: [Self] { allCases.filter { ![.system, .ring, .gestures].contains($0) } }
    /// A gesture direction always runs an action: native handling and nested gestures are meaningless there.
    public static var gestureChoices: [Self] { allCases.filter { ![.system, .gestures].contains($0) } }
}
public struct RingApplication: Codable, Equatable {
    public var bundleIdentifier: String?
    public var name: String
    public var path: String
    public init(bundleIdentifier: String?, name: String, path: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.path = path
    }
}
public enum RingAction: Codable, Equatable {
    case mouse(MouseAction)
    case application(RingApplication)

    private enum CodingKeys: String, CodingKey { case application }

    public init(from decoder: Decoder) throws {
        if let action = try? decoder.singleValueContainer().decode(MouseAction.self) {
            self = .mouse(action)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = .application(try container.decode(RingApplication.self, forKey: .application))
    }
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .mouse(let action):
            var container = encoder.singleValueContainer()
            try container.encode(action)
        case .application(let application):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(application, forKey: .application)
        }
    }
    public var title: String {
        switch self {
        case .mouse(let action): return action.title
        case .application(let application): return application.name
        }
    }
    public var symbol: String {
        switch self {
        case .mouse(let action): return action.symbol
        case .application: return "app.fill"
        }
    }
    public var isValid: Bool {
        switch self {
        case .mouse(let action): return MouseAction.ringChoices.contains(action)
        case .application(let application):
            let hasName = !application.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasLocation = !(application.bundleIdentifier ?? "").isEmpty || !application.path.isEmpty
            return hasName && hasLocation
        }
    }
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
    /// Gesture direction actions per control; keys are decimal CIDs like `buttons`.
    public var gestures: [String: GestureActions] = [:]
    public var ring: [RingAction] = [.mouse(.missionControl), .mouse(.spotlight), .mouse(.screenshot), .mouse(.copy), .mouse(.paste), .mouse(.playPause)]
    public var profiles: [AppProfile] = []
    public var desiredDPI: Int?
    public var desiredWheel: WheelMode?
    public var desiredThreshold: Int = 30
    public var desiredTorque: Int?
    public var desiredHaptics: Bool?
    public var desiredIntensity: Int = 50
    public init() {}
    /// Keys missing from an older `preferences.v1` keep their defaults instead of resetting everything (INV-14).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        scroll = try c.decodeIfPresent(ScrollPreferences.self, forKey: .scroll) ?? d.scroll
        buttons = try c.decodeIfPresent([String: MouseAction].self, forKey: .buttons) ?? d.buttons
        gestures = try c.decodeIfPresent([String: GestureActions].self, forKey: .gestures) ?? d.gestures
        ring = try c.decodeIfPresent([RingAction].self, forKey: .ring) ?? d.ring
        profiles = try c.decodeIfPresent([AppProfile].self, forKey: .profiles) ?? d.profiles
        desiredDPI = try c.decodeIfPresent(Int.self, forKey: .desiredDPI)
        desiredWheel = try c.decodeIfPresent(WheelMode.self, forKey: .desiredWheel)
        desiredThreshold = try c.decodeIfPresent(Int.self, forKey: .desiredThreshold) ?? d.desiredThreshold
        desiredTorque = try c.decodeIfPresent(Int.self, forKey: .desiredTorque)
        desiredHaptics = try c.decodeIfPresent(Bool.self, forKey: .desiredHaptics)
        desiredIntensity = try c.decodeIfPresent(Int.self, forKey: .desiredIntensity) ?? d.desiredIntensity
    }
    public func gestureActions(for cid: UInt16) -> GestureActions { gestures[String(cid)] ?? GestureActions() }
    public mutating func sanitize() {
        scroll.sanitize()
        for i in profiles.indices { profiles[i].scroll.sanitize() }
        for key in Array(gestures.keys) { gestures[key]?.sanitize() }
        if let dpi = desiredDPI { desiredDPI = max(200, min(8000, dpi / 50 * 50)) }
        desiredThreshold = max(1, min(254, desiredThreshold))
        if let torque = desiredTorque { desiredTorque = max(1, min(100, torque)) }
        desiredIntensity = max(0, min(100, desiredIntensity))
        if ring.count != 6 || ring.contains(where: { !$0.isValid }) { ring = Preferences().ring }
    }
}
public enum GestureDirection: String, Codable, CaseIterable, Identifiable {
    case up, down, left, right, click
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .up: return "Вверх"; case .down: return "Вниз"; case .left: return "Влево"; case .right: return "Вправо"
        case .click: return "Нажатие"
        }
    }
    public var symbol: String {
        switch self {
        case .up: return "arrow.up"; case .down: return "arrow.down"; case .left: return "arrow.left"; case .right: return "arrow.right"
        case .click: return "smallcircle.filled.circle"
        }
    }
}
/// Defaults reproduce the fixed mapping used before gestures became configurable.
public struct GestureActions: Codable, Equatable {
    public var up: MouseAction = .missionControl
    public var down: MouseAction = .appExpose
    public var left: MouseAction = .previousDesktop
    public var right: MouseAction = .nextDesktop
    public var click: MouseAction = .missionControl
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GestureActions()
        // An unknown value in one direction must not reset the whole preferences.v1.
        func action(_ key: CodingKeys) -> MouseAction? { (try? c.decodeIfPresent(MouseAction.self, forKey: key)) ?? nil }
        up = action(.up) ?? d.up
        down = action(.down) ?? d.down
        left = action(.left) ?? d.left
        right = action(.right) ?? d.right
        click = action(.click) ?? d.click
        sanitize()
    }
    public subscript(direction: GestureDirection) -> MouseAction {
        get {
            switch direction { case .up: return up; case .down: return down; case .left: return left; case .right: return right; case .click: return click }
        }
        set {
            switch direction { case .up: up = newValue; case .down: down = newValue; case .left: left = newValue; case .right: right = newValue; case .click: click = newValue }
        }
    }
    public mutating func sanitize() {
        let defaults = GestureActions()
        for direction in GestureDirection.allCases where !MouseAction.gestureChoices.contains(self[direction]) { self[direction] = defaults[direction] }
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
    /// Travel below the threshold is a click; otherwise the dominant axis wins.
    public var direction: GestureDirection {
        guard max(abs(x), abs(y)) > 60 else { return .click }
        return abs(x) > abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .down : .up)
    }
}

import AppKit
import Carbon.HIToolbox
import MouseCore

final class ActionExecutor {
    var showRing: (() -> Void)?
    func execute(_ action: MouseAction) {
        guard AXIsProcessTrusted() else { return }
        switch action {
        case .system, .none: break
        case .ring: showRing?()
        case .gestures, .missionControl: symbolic(32, fallback: (126, .maskControl))
        case .appExpose: symbolic(33, fallback: (125, .maskControl))
        case .desktop: symbolic(36, fallback: (103, []))
        case .launchpad: NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Launchpad.app"))
        case .spotlight: symbolic(64, fallback: (49, .maskCommand))
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
    func gesture(_ direction: String?) {
        switch direction {
        case "left": symbolic(79, fallback: (123, .maskControl))
        case "right": symbolic(81, fallback: (124, .maskControl))
        case "up": execute(.missionControl)
        case "down": execute(.appExpose)
        default: execute(.missionControl)
        }
    }
    private func symbolic(_ id: Int, fallback: (CGKeyCode, CGEventFlags)) {
        let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys")
        if let keys = domain?["AppleSymbolicHotKeys"] as? [String: Any],
           let binding = keys[String(id)] as? [String: Any],
           let enabled = binding["enabled"] as? Bool {
            guard enabled else { NSSound.beep(); return }
            if let value = binding["value"] as? [String: Any], let p = value["parameters"] as? [NSNumber], p.count >= 3, p[1].intValue < 65535 {
                key(CGKeyCode(p[1].intValue), CGEventFlags(rawValue: p[2].uint64Value)); return
            }
        }
        key(fallback.0, fallback.1)
    }
    private func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
        let source = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags; up?.flags = flags
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
    }
    private func media(_ code: Int) {
        for state in [0x0a, 0x0b] {
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)), timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: (code << 16) | (state << 8), data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

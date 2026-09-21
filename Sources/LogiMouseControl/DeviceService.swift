import Foundation
import MouseCore

struct MouseControl: Identifiable {
    let id: UInt16
    let flags: UInt16
    var rawXY: Bool { flags & 0x100 != 0 }
    var name: String {
        switch id {
        case 0x50: return "Левая кнопка"; case 0x51: return "Правая кнопка"; case 0x52: return "Нажатие колеса"
        case 0x53, 0xbd, 0xce, 0xdb: return "Назад"; case 0x56, 0xcf: return "Вперёд"
        case 0xc3: return "Кнопка жестов"; case 0xc4, 0xed, 0xfd: return "Кнопка режима колеса"
        case 0x1a0: return "Тактильная панель"
        default: return String(format: "Кнопка 0x%04X", id)
        }
    }
}
struct DeviceSnapshot {
    var connected = false
    var features: [UInt16: UInt8] = [:]
    var battery: Int?
    var charging = false
    var dpi: Int?
    var dpiValues: [Int] = []
    var wheelMode: WheelMode?
    var threshold = 30
    var torque: Int?
    var haptics: Bool?
    var intensity = 50
    var waveforms: UInt32 = 0
    var controls: [MouseControl] = []
    var hostCount = 0
    var currentHost = 0
    var verticalMultiplier = 1.0
    var horizontalResolution = 120.0
    var warnings: [String] = []
}

/// Hardware command sequence is serialized. UI only receives completed snapshots.
final class DeviceService {
    let transport = HIDTransport()
    let queue = DispatchQueue(label: "local.logimouse.hardware", qos: .userInitiated)
    private var snapshot = DeviceSnapshot()
    private var originalWheel: UInt8?
    private var originalThumb: [UInt8]?
    private var originalButtons: [UInt16: [UInt8]] = [:]
    private var captured = false
    private let guardian = CaptureGuardian()
    var onSnapshot: ((DeviceSnapshot) -> Void)?
    var onEvent: ((HIDPacket) -> Void)?
    var onError: ((String) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?

    init() {
        transport.onConnect = { [weak self] in self?.refresh(discover: true) }
        transport.onDisconnect = { [weak self] in
            guard let self else { return }
            self.onDisconnected?()
            self.queue.async {
                self.snapshot = DeviceSnapshot(); self.originalWheel = nil; self.originalThumb = nil
                self.originalButtons = [:]; self.captured = false; try? self.checkpoint(); self.publish()
            }
        }
        transport.onStatus = { [weak self] in self?.onError?($0) }
        transport.onEvent = { [weak self] in self?.onEvent?($0) }
    }
    private func publish() {
        let state = snapshot
        DispatchQueue.main.async { [weak self] in self?.onSnapshot?(state) }
    }
    private func perform(_ work: @escaping () throws -> Void, completion: ((Bool) -> Void)? = nil) {
        queue.async {
            do { try work(); self.publish(); DispatchQueue.main.async { completion?(true) } }
            catch { self.publish(); DispatchQueue.main.async { self.onError?(error.localizedDescription); completion?(false) } }
        }
    }
    private func call(_ feature: UInt16, _ function: UInt8, _ payload: [UInt8] = []) throws -> [UInt8] {
        guard let index = snapshot.features[feature] else { throw HIDFailure.unsupported(feature) }
        let bytes = try transport.request(feature: index, function: function, payload: payload)
        guard bytes.count >= 3 else { throw HIDFailure.malformed }
        return bytes
    }
    func refresh(discover: Bool = false) {
        perform({
            if discover || !self.snapshot.connected {
                self.snapshot = DeviceSnapshot()
                // Long-report root feature lookups also prove the protocol endpoint is alive.
                for id: UInt16 in [0x2201, 0x2111, 0x2110, 0x2121, 0x2150, 0x1004, 0x19b0, 0x1b04, 0x1814] {
                    let p = try self.transport.request(feature: 0, function: 0, payload: splitWord(id) + [0])
                    guard !p.isEmpty else { throw HIDFailure.malformed }
                    if p[0] != 0 { self.snapshot.features[id] = p[0] }
                }
                self.snapshot.connected = true
                self.snapshot.controls = []
                if self.snapshot.features[0x1b04] != nil {
                    let count = min(64, Int(try self.call(0x1b04, 0)[0]))
                    for i in 0..<count {
                        let p = try self.call(0x1b04, 1, [UInt8(i)])
                        guard p.count >= 9 else { continue }
                        let flags = UInt16(p[4]) | UInt16(p[8]) << 8
                        if flags & 0x20 != 0 && flags & 0x80 == 0 { self.snapshot.controls.append(MouseControl(id: word(p), flags: flags)) }
                    }
                }
                if self.snapshot.features[0x2121] != nil {
                    self.snapshot.verticalMultiplier = Double(max(1, try self.call(0x2121, 0)[0]))
                }
                if self.snapshot.features[0x2150] != nil {
                    self.snapshot.horizontalResolution = Double(max(1, word(try self.call(0x2150, 0), 2)))
                }
                if self.snapshot.features[0x2201] != nil {
                    let p = try self.call(0x2201, 1)
                    self.snapshot.dpiValues = Self.parseDPI(Array(p.dropFirst()))
                }
            }
            self.snapshot.warnings = []
            self.readOptional("DPI") { try self.readDPI() }
            self.readOptional("MagSpeed") { try self.readWheel() }
            self.readOptional("Виброотклик") { try self.readHaptics() }
            if self.snapshot.features[0x1004] != nil {
                self.readOptional("Батарея") {
                    let caps = try self.call(0x1004, 0)
                    let p = try self.call(0x1004, 1)
                    self.snapshot.battery = caps[1] & 2 != 0 && p[0] <= 100 ? Int(p[0]) : nil
                    self.snapshot.charging = [1, 2, 4].contains(p[2])
                }
            }
            if self.snapshot.features[0x1814] != nil {
                self.readOptional("Easy-Switch") {
                    let p = try self.call(0x1814, 0); self.snapshot.hostCount = Int(p[0]); self.snapshot.currentHost = Int(p[1])
                }
            }
        }, completion: { success in if success && discover { self.onConnected?() } })
    }
    private func readOptional(_ label: String, _ work: () throws -> Void) {
        do { try work() } catch { snapshot.warnings.append("\(label): \(error.localizedDescription)") }
    }
    private static func parseDPI(_ p: [UInt8]) -> [Int] {
        var values: [Int] = []; var i = 0
        while i + 1 < p.count {
            let value = Int(word(p, i)); if value == 0 { break }
            if value & 0xe000 == 0xe000 {
                let step = value & 0x1fff
                guard let start = values.last, step > 0, i + 3 < p.count else { return [] }
                let end = Int(word(p, i + 2)); guard end >= start else { return [] }
                values += stride(from: start, through: end, by: step); values.append(end); i += 4
            } else { values.append(value); i += 2 }
        }
        return Array(Set(values)).sorted()
    }
    private func readDPI() throws {
        guard snapshot.features[0x2201] != nil else { return }
        snapshot.dpi = Int(word(try call(0x2201, 2), 1))
    }
    private func readWheel() throws {
        let enhanced = snapshot.features[0x2111] != nil
        guard enhanced || snapshot.features[0x2110] != nil else { return }
        let p = try call(enhanced ? 0x2111 : 0x2110, enhanced ? 1 : 0)
        snapshot.wheelMode = p[0] == 1 ? .freeSpin : (p[1] == 255 ? .ratchet : .smartShift)
        if p[1] > 0 && p[1] < 255 { snapshot.threshold = Int(p[1]) }
        if enhanced {
            let caps = try call(0x2111, 0)
            snapshot.torque = caps[0] & 1 != 0 ? Int(p[2]) : nil
        }
    }
    private func readHaptics() throws {
        guard snapshot.features[0x19b0] != nil else { return }
        let p = try call(0x19b0, 1)
        guard p[0] <= 1, p[1] <= 100 else { throw HIDFailure.malformed }
        snapshot.haptics = p[0] == 1; snapshot.intensity = Int(p[1])
        let caps = try call(0x19b0, 0)
        guard caps.count >= 8 else { throw HIDFailure.malformed }
        snapshot.waveforms = UInt32(caps[4]) << 24 | UInt32(caps[5]) << 16 | UInt32(caps[6]) << 8 | UInt32(caps[7])
    }
    func setDPI(_ value: Int, completion: @escaping (Bool) -> Void) {
        perform({
            guard self.snapshot.dpiValues.contains(value) else { throw HIDFailure.verification }
            _ = try self.call(0x2201, 3, [0] + splitWord(UInt16(value)))
            try self.readDPI()
            guard self.snapshot.dpi == value else { throw HIDFailure.verification }
        }, completion: completion)
    }
    func setWheel(_ mode: WheelMode, threshold: Int, torque: Int?, completion: @escaping (Bool) -> Void) {
        perform({
            let enhanced = self.snapshot.features[0x2111] != nil
            let payload = [mode.wireValue, mode.threshold(threshold), enhanced ? UInt8(clamping: torque ?? 0) : 0]
            _ = try self.call(enhanced ? 0x2111 : 0x2110, enhanced ? 2 : 1, payload)
            try self.readWheel()
            guard self.snapshot.wheelMode == mode,
                  mode != .smartShift || self.snapshot.threshold == threshold,
                  torque == nil || self.snapshot.torque == torque else { throw HIDFailure.verification }
        }, completion: completion)
    }
    func setHaptics(_ enabled: Bool, intensity: Int, completion: @escaping (Bool) -> Void) {
        perform({
            _ = try self.call(0x19b0, 2, [enabled ? 1 : 0, UInt8(clamping: intensity), 0])
            try self.readHaptics()
            guard self.snapshot.haptics == enabled, self.snapshot.intensity == intensity else { throw HIDFailure.verification }
        }, completion: completion)
    }
    func pulse(_ waveform: UInt8 = 1) {
        perform({
            guard self.snapshot.haptics == true, self.snapshot.waveforms & (1 << waveform) != 0 else { return }
            _ = try self.call(0x19b0, 4, [waveform, 0, 0])
        })
    }
    func configureCapture(scroll: Bool, buttons: [String: MouseAction], completion: @escaping (Bool) -> Void) {
        perform({
            do {
                if scroll {
                    if self.originalWheel == nil { self.originalWheel = try self.call(0x2121, 1)[0] }
                    try self.checkpoint()
                    _ = try self.call(0x2121, 2, [3, 0, 0]) // diverted, high resolution; analytics off
                    guard try self.call(0x2121, 1)[0] & 3 == 3 else { throw HIDFailure.verification }
                    if self.snapshot.features[0x2150] != nil {
                        if self.originalThumb == nil { self.originalThumb = try self.call(0x2150, 1) }
                        try self.checkpoint()
                        _ = try self.call(0x2150, 2, [1, 0, 0])
                        guard try self.call(0x2150, 1)[0] == 1 else { throw HIDFailure.verification }
                    }
                } else { try self.restoreScroll() }
                for control in self.snapshot.controls {
                    let action = buttons[String(control.id)] ?? .system
                    if action == .system {
                        if self.originalButtons[control.id] != nil { try self.restoreButton(control.id) }
                        continue
                    }
                    if self.originalButtons[control.id] == nil { self.originalButtons[control.id] = try self.call(0x1b04, 2, splitWord(control.id)) }
                    try self.checkpoint()
                    let xy = action == .gestures && control.rawXY
                    _ = try self.call(0x1b04, 3, reportingPayload(cid: control.id, capabilities: control.flags, diverted: true, rawXY: xy))
                    let report = try self.call(0x1b04, 2, splitWord(control.id))
                    guard report[2] & 1 != 0, (report[2] & 16 != 0) == xy else { throw HIDFailure.verification }
                }
                self.captured = scroll
                try self.checkpoint()
            } catch {
                // Return all successfully diverted controls when any part of arming fails.
                try? self.restoreAll()
                throw error
            }
        }, completion: completion)
    }
    private func restoreScroll() throws {
        if let originalWheel {
            // Never hand back a diverted wheel inherited from a crashed/other driver.
            _ = try call(0x2121, 2, [originalWheel & 0x06, 0, 0]); self.originalWheel = nil
        }
        if let originalThumb {
            _ = try call(0x2150, 2, [0, originalThumb[1] & 1, 0]); self.originalThumb = nil
        }
        captured = false
    }
    private func restoreButton(_ id: UInt16) throws {
        guard let original = originalButtons[id], original.count >= 6 else { return }
        // Temporary diversion belongs to this process; never leave a dead recipient.
        guard let control = snapshot.controls.first(where: { $0.id == id }) else { throw HIDFailure.verification }
        _ = try call(0x1b04, 3, reportingPayload(cid: id, capabilities: control.flags, diverted: false, rawXY: false, remap: [original[3], original[4]]))
        originalButtons.removeValue(forKey: id)
    }
    private func restoreAll() throws {
        var failure: Error?
        do { try restoreScroll() } catch { failure = error }
        for id in Array(originalButtons.keys) { do { try restoreButton(id) } catch { failure = error } }
        try checkpoint()
        if let failure { throw failure }
    }
    private func checkpoint() throws {
        try guardian.checkpoint(CaptureRecovery(wheel: originalWheel, thumb: originalThumb, buttons: Dictionary(uniqueKeysWithValues: originalButtons.map { (String($0.key), $0.value) })))
    }
    func finishGuardian(clean: Bool, completion: @escaping () -> Void) { queue.async { self.guardian.finish(clean: clean); DispatchQueue.main.async(execute: completion) } }
    func checkCaptureSafety(completion: @escaping (Bool) -> Void) { perform({ try self.checkpoint() }, completion: completion) }
    func restoreRecovery(_ state: CaptureRecovery, completion: @escaping (Bool) -> Void) {
        perform({
            var failure: Error?
            if let wheel = state.wheel { do { _ = try self.call(0x2121, 2, [wheel & 6, 0, 0]) } catch { failure = error } }
            if let thumb = state.thumb, thumb.count >= 2 { do { _ = try self.call(0x2150, 2, [0, thumb[1] & 1, 0]) } catch { failure = error } }
            for (key, original) in state.buttons {
                guard let id = UInt16(key), original.count >= 6 else { continue }
                guard let control = self.snapshot.controls.first(where: { $0.id == id }) else { continue }
                do { _ = try self.call(0x1b04, 3, reportingPayload(cid: id, capabilities: control.flags, diverted: false, rawXY: false, remap: [original[3], original[4]])) } catch { failure = error }
            }
            if let failure { throw failure }
        }, completion: completion)
    }
    func release(completion: @escaping (Bool) -> Void) { perform({ try self.restoreAll() }, completion: completion) }
    func switchHost(_ host: Int, completion: @escaping (Bool) -> Void) {
        perform({
            guard host >= 0, host < self.snapshot.hostCount, let index = self.snapshot.features[0x1814] else { throw HIDFailure.verification }
            try self.restoreAll()
            try self.transport.notify(feature: index, function: 1, payload: [UInt8(host), 0, 0])
        }, completion: completion)
    }
}

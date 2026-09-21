import Foundation

public enum HIDFailure: Error, LocalizedError {
    case safetyUnavailable, disconnected, timeout, unsupported(UInt16), malformed, rejected(UInt8), io(Int32), verification
    public var errorDescription: String? {
        switch self {
        case .safetyUnavailable: return "Защитный процесс недоступен. Перезапустите Logi Mouse Control."
        case .disconnected: return "MX Master 4 не подключена."
        case .timeout: return "Мышь не ответила. Разбудите её и повторите."
        case .unsupported(let id): return String(format: "Мышь не сообщает поддержку функции 0x%04X.", id)
        case .malformed: return "Получен неполный ответ мыши."
        case .rejected(let code): return "Мышь отклонила команду (\(code))."
        case .io: return "macOS не разрешает связь с мышью. Включите Мониторинг ввода и перезапустите приложение."
        case .verification: return "Мышь не подтвердила настройку. Изменение не сохранено."
        }
    }
}
public struct HIDPacket: Equatable {
    public let device: UInt8
    public let feature: UInt8
    public let function: UInt8
    public let softwareID: UInt8
    public let payload: [UInt8]
    public init(device: UInt8 = 0xff, feature: UInt8, function: UInt8, softwareID: UInt8, payload: [UInt8] = []) {
        self.device = device; self.feature = feature; self.function = function
        self.softwareID = softwareID; self.payload = Array(payload.prefix(16))
    }
    /// BLE only exposes the 20-byte long report (0x11).
    public var bytes: [UInt8] {
        [0x11, device, feature, (function << 4) | (softwareID & 0x0f)] + payload + Array(repeating: 0, count: 16 - payload.count)
    }
    public static func decode(_ data: [UInt8]) -> HIDPacket? {
        guard let first = data.first, (first == 0x11 && data.count >= 20) || (first == 0x10 && data.count >= 7) else { return nil }
        return HIDPacket(device: data[1], feature: data[2], function: data[3] >> 4, softwareID: data[3] & 15, payload: Array(data.dropFirst(4)))
    }
    public func response(to request: HIDPacket) -> Result<[UInt8], HIDFailure>? {
        guard device == request.device else { return nil }
        if feature == 0xff, payload.count >= 2,
           (function << 4 | softwareID) == request.feature,
           payload[0] == (request.function << 4 | request.softwareID) {
            return .failure(.rejected(payload[1]))
        }
        guard feature == request.feature, function == request.function, softwareID == request.softwareID else { return nil }
        return .success(payload)
    }
}
public func word(_ bytes: [UInt8], _ offset: Int = 0) -> UInt16 {
    guard bytes.count > offset + 1 else { return 0 }
    return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
}
public func signedWord(_ bytes: [UInt8], _ offset: Int = 0) -> Int16 { Int16(bitPattern: word(bytes, offset)) }
public func splitWord(_ value: UInt16) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 255)] }

public enum WheelMode: String, CaseIterable, Codable {
    case smartShift, ratchet, freeSpin
    public var title: String { switch self { case .smartShift: return "SmartShift"; case .ratchet: return "Пошаговый"; case .freeSpin: return "Свободный" } }
    public var wireValue: UInt8 { self == .freeSpin ? 1 : 2 }
    public func threshold(_ value: Int) -> UInt8 { self == .smartShift ? UInt8(clamping: max(1, min(254, value))) : 255 }
}

/// Write only flags that the control's capability table permits. In particular,
/// ordinary Back/Forward controls must not receive unsupported raw-XY flags.
public func reportingPayload(cid: UInt16, capabilities: UInt16, diverted: Bool, rawXY: Bool, remap: [UInt8] = [0, 0]) -> [UInt8] {
    var flags: UInt8 = diverted ? 3 : 2
    if capabilities & 0x40 != 0 { flags |= 0x08 } // clear persistent diversion
    if capabilities & 0x100 != 0 { flags |= 0x20; if rawXY { flags |= 0x10 } }
    if capabilities & 0x200 != 0 { flags |= 0x80 } // clear force-raw-XY
    var extra: UInt8 = 0
    if capabilities & 0x400 != 0 { extra |= 0x02 } // disable analytics, never enable it
    if capabilities & 0x800 != 0 { extra |= 0x08 }
    return splitWord(cid) + [flags, remap.first ?? 0, remap.count > 1 ? remap[1] : 0, extra]
}

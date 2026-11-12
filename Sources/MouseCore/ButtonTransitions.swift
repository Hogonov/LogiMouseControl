import Foundation

public struct ButtonTransitions {
    public let released: [UInt16]
    public let pressed: [UInt16]
    public init(previous: Set<UInt16>, next: Set<UInt16>) {
        released = previous.subtracting(next).sorted()
        pressed = next.subtracting(previous).sorted()
    }
}

public struct GestureInputState {
    public private(set) var held: Set<UInt16> = []
    private var sessions: [UInt16: GestureSession] = [:]
    private var suppressedUntilRelease: Set<UInt16> = []
    public init() {}
    public func transitions(to next: Set<UInt16>) -> ButtonTransitions { ButtonTransitions(previous: held, next: next) }
    public mutating func collectReleases(_ ids: [UInt16], at time: Double) -> [(UInt16, GestureSession.Outcome)] {
        ids.sorted().compactMap { id in
            guard !suppressedUntilRelease.contains(id), var session = sessions.removeValue(forKey: id) else { return nil }
            return (id, session.release(at: time))
        }
    }
    public mutating func begin(_ id: UInt16, session: GestureSession) {
        guard !suppressedUntilRelease.contains(id) else { return }; sessions[id] = session
    }
    public mutating func updateHeld(_ next: Set<UInt16>, released: [UInt16]) {
        held = next; suppressedUntilRelease.subtract(released)
    }
    public mutating func move(dx: Double, dy: Double, at time: Double) -> [SwipeStep] {
        var result: [SwipeStep] = []
        for id in sessions.keys.sorted() where !suppressedUntilRelease.contains(id) {
            let allow = !sessions.contains { $0.key != id && $0.value.isSwiping }
            result += sessions[id]?.add(dx: dx, dy: dy, at: time, allowSwipe: allow) ?? []
        }
        return result
    }
    public mutating func finishHorizontalForMissionControl(at time: Double, held next: Set<UInt16>) -> [(UInt16, GestureSession.Outcome)] {
        var result: [(UInt16, GestureSession.Outcome)] = []
        for id in sessions.keys.sorted() where sessions[id]?.isSwiping == true {
            guard var session = sessions.removeValue(forKey: id) else { continue }
            result.append((id, session.release(at: time)))
            if next.contains(id) { suppressedUntilRelease.insert(id) }
        }
        return result
    }
    public mutating func clear() -> [SwipeStep] {
        var result: [SwipeStep] = []
        for id in sessions.keys.sorted() { result += sessions[id]?.cancel() ?? [] }
        sessions.removeAll(); held.removeAll(); suppressedUntilRelease.removeAll()
        return result
    }
}

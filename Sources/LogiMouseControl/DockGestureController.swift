import Foundation
import MouseCore

/// All methods run on the main thread. Effects are injected for deterministic checks.
final class DockGestureController {
    struct Prepared { let send: (SwipeStep, Int) -> Bool }
    private let now: () -> Double
    private let schedule: (Double, @escaping () -> Void) -> (() -> Void)
    private let allowed: () -> Bool
    private let canSendTerminal: () -> Bool
    private let prepare: (MissionControlGesture.Configuration) -> Prepared?
    private let finishHorizontal: () -> Void
    private let legacy: () -> Void
    private let error: (String) -> Void
    private let config: MissionControlGesture.Configuration
    private var gesture: MissionControlGesture
    private var prepared: Prepared?
    private var cancelTask: (() -> Void)?
    private var generation: UInt64 = 0

    init(config: MissionControlGesture.Configuration = .init(), now: @escaping () -> Double,
         schedule: @escaping (Double, @escaping () -> Void) -> (() -> Void), allowed: @escaping () -> Bool,
         canSendTerminal: @escaping () -> Bool,
         prepare: @escaping (MissionControlGesture.Configuration) -> Prepared?, finishHorizontal: @escaping () -> Void,
         legacy: @escaping () -> Void, error: @escaping (String) -> Void) {
        self.config = config; self.gesture = MissionControlGesture(configuration: config)
        self.now = now; self.schedule = schedule; self.allowed = allowed; self.canSendTerminal = canSendTerminal; self.prepare = prepare
        self.finishHorizontal = finishHorizontal; self.legacy = legacy; self.error = error
    }
    func request() {
        guard allowed() else { cancel(); error("Разрешите Универсальный доступ для выполнения действий мыши."); return }
        let time = now()
        if let start = gesture.startTime {
            if time.isFinite && time - start < config.staleAfter { return }
            cancel()
        }
        guard config.intervalCount != nil, time.isFinite, let sequence = prepare(config) else {
            finishHorizontal()
            if allowed() { legacy() } else { error("Разрешите Универсальный доступ для выполнения действий мыши.") }
            return
        }
        finishHorizontal()
        guard allowed() else { error("Разрешите Универсальный доступ для выполнения действий мыши."); return }
        let startTime = now()
        guard startTime.isFinite else { legacy(); return }
        generation &+= 1; prepared = sequence
        guard let first = gesture.start(at: startTime).first, sequence.send(first, 0) else { fail(); return }
        scheduleNext()
    }
    func cancel() {
        generation &+= 1; cancelTask?(); cancelTask = nil
        let frames = gesture.cancel()
        // Closing admission must not strand an already-started Dock gesture.
        if canSendTerminal(), let frame = frames.first { _ = prepared?.send(frame, gesture.lastIndex) }
        prepared = nil
    }
    func postHorizontal(_ step: SwipeStep, send: (SwipeStep) -> Void) {
        if step.phase == .began { cancel() }
        send(step)
    }
    private func scheduleNext() {
        guard let start = gesture.startTime else { return }
        let deadline = start + min(config.duration, Double(gesture.lastIndex + 1) * config.frameInterval)
        let id = generation
        cancelTask = schedule(max(0, deadline - now())) { [weak self] in self?.tick(id) }
    }
    private func tick(_ id: UInt64) {
        guard id == generation, prepared != nil else { return }
        guard allowed() else { cancel(); return }
        let frames = gesture.advance(at: now())
        for frame in frames {
            guard prepared?.send(frame, gesture.lastIndex) == true else {
                if gesture.startTime == nil, canSendTerminal() {
                    _ = prepared?.send(SwipeStep(.cancelled, progress: frame.progress), gesture.lastIndex)
                }
                fail(); return
            }
        }
        if gesture.startTime == nil { cancelTask = nil; prepared = nil } else { scheduleNext() }
    }
    private func fail() {
        cancel()
        error("Не удалось завершить жест Mission Control. Повторите действие.")
    }
}

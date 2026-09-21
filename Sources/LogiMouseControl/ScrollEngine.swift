import AppKit
import MouseCore

final class ScrollEngine {
    static let marker: Int64 = 0x4c4d435343524c
    var preferences = ScrollPreferences() { didSet { stop() } }
    private var vertical = ScrollIntegrator(), horizontal = ScrollIntegrator()
    private var timer: DispatchSourceTimer?
    private var lastFrame = 0.0
    private var lastInput = 0.0
    private var started = false
    private let source = CGEventSource(stateID: .privateState)
    private var cancellationMonitor: Any?
    var onFailure: (() -> Void)?

    init() {
        source?.localEventsSuppressionInterval = 0
        cancellationMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            if event.type != .scrollWheel || (event.hasPreciseScrollingDeltas && event.cgEvent?.getIntegerValueField(.eventSourceUserData) != Self.marker) { self?.stop() }
        }
    }
    func feed(vertical y: Double = 0, horizontal x: Double = 0) {
        guard preferences.enabled, AXIsProcessTrusted() else { return }
        let y = y * preferences.speed * (preferences.natural ? -1 : 1)
        let x = x * preferences.horizontalSpeed * (preferences.horizontalNatural ? -1 : 1)
        vertical.feed(y); horizontal.feed(x)
        lastInput = ProcessInfo.processInfo.systemUptime
        if timer == nil {
            lastFrame = lastInput - 1.0 / 120
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: 1.0 / 120, leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer; timer.resume()
        }
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        guard AXIsProcessTrusted() else { stop(); onFailure?(); return }
        let dt = now - lastFrame
        lastFrame = now
        let y = preferences.smooth ? vertical.advance(seconds: dt, smoothness: preferences.smoothness) : vertical.takeImmediately()
        let x = preferences.smooth ? horizontal.advance(seconds: dt, smoothness: preferences.smoothness) : horizontal.takeImmediately()
        if x != 0 || y != 0 { post(x: x, y: y, phase: started ? 2 : 1); started = true }
        if !vertical.isActive && !horizontal.isActive && now - lastInput > 0.09 { finish() }
    }
    private func post(x: Int32, y: Int32, phase: Int64) {
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0) else { onFailure?(); return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.flags = CGEventSource.flagsState(.combinedSessionState)
        event.post(tap: .cghidEventTap)
    }
    private func finish() {
        if started { post(x: 0, y: 0, phase: 4) }
        started = false; timer?.cancel(); timer = nil
    }
    func stop() { finish(); vertical.reset(); horizontal.reset() }
}

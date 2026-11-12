import AppKit
import MouseCore

final class Harness {
    var time = 0.0
    var allowed = true
    var available = true
    var failSend = false
    var revokeOnFinish = false
    var callbacks: [() -> Void] = []
    var effects: [String] = []
    lazy var controller = DockGestureController(now: { [unowned self] in self.time }, schedule: { [unowned self] _, callback in
        self.callbacks.append(callback); return {}
    }, allowed: { [unowned self] in self.allowed }, prepare: { [unowned self] _ in
        self.effects.append("prepare")
        guard self.available else { return nil }
        return .init { [unowned self] step, _ in
            self.effects.append("frame:\(step.phase)")
            return !self.failSend
        }
    }, finishHorizontal: { [unowned self] in
        self.effects.append("finish")
        if self.revokeOnFinish { self.allowed = false }
    }, legacy: { [unowned self] in self.effects.append("legacy") }, error: { [unowned self] _ in self.effects.append("error") })
    func tick(_ time: Double) { self.time = time; let callback = callbacks.removeFirst(); callback() }
}
func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }

do {
    let h = Harness(); h.controller.request()
    check(h.effects == ["prepare", "finish", "frame:began"], "immediate began")
    h.controller.request(); check(h.effects.count == 3 && h.callbacks.count == 1, "repeat")
    h.tick(0.08); check(h.effects.last == "frame:changed", "skip frames")
    h.tick(0.12); check(h.effects.suffix(2) == ["frame:changed", "frame:ended"], "terminal")
    h.controller.request(); check(h.effects.last == "frame:began", "new request")
}
do {
    let h = Harness(); h.controller.request(); let old = h.callbacks[0]
    h.time = 0.251; h.controller.request()
    check(h.effects.contains("frame:cancelled"), "stale cancellation")
    let count = h.effects.count; old(); check(h.effects.count == count, "old callback")
    h.controller.postHorizontal(SwipeStep(.began, progress: 0)) { _ in h.effects.append("horizontal") }
    check(h.effects.suffix(2) == ["frame:cancelled", "horizontal"], "horizontal ordering")
    h.controller.cancel(); h.callbacks.forEach { $0() }
    check(h.effects.last == "horizontal", "callbacks after cancel")
}
do {
    let h = Harness(); h.available = false; h.controller.request()
    check(h.effects == ["prepare", "finish", "legacy"], "fallback")
    let denied = Harness(); denied.allowed = false; denied.controller.request()
    check(denied.effects == ["error"], "denied")
    let revoked = Harness(); revoked.revokeOnFinish = true; revoked.controller.request()
    check(revoked.effects == ["prepare", "finish", "error"], "revoked before began")
    let lost = Harness(); lost.controller.request(); lost.allowed = false; lost.controller.cancel()
    check(lost.effects == ["prepare", "finish", "frame:began"], "no post without permission")
    lost.callbacks.forEach { $0() }; check(lost.effects.count == 3, "stale after permission loss")
}
do {
    let h = Harness(); var effects: [String] = []
    let executor = ActionExecutor(effects: .init(trusted: { true }, key: { _, _ in effects.append("key") }, media: { _ in effects.append("media") }, symbolic: { effects.append($0) }, systemApplication: { _, _ in effects.append("system") }, application: { _ in effects.append("application") }))
    executor.requestMissionControl = { h.controller.request() }
    executor.willExecuteDockAction = { h.controller.cancel() }
    executor.execute(.missionControl); executor.execute(.volumeUp); executor.execute(.copy)
    check(effects == ["media", "key"], "independent actions")
    executor.execute(.nextDesktop)
    check(h.effects.last == "frame:cancelled" && effects.last == "nextDesktop", "conflicting action")
    executor.execute(RingAction.mouse(.missionControl))
    check(h.effects.last == "frame:began", "ring route")
    executor.execute(.application(RingApplication(bundleIdentifier: nil, name: "Example", path: "/example")))
    check(effects.last == "application" && h.effects.last == "frame:began", "application route")
}
for _ in 0..<8 {
    let h = Harness(); h.controller.request(); h.controller.cancel(); h.controller.cancel()
    let count = h.effects.count; h.callbacks.forEach { $0() }
    check(h.effects.filter { $0 == "frame:cancelled" }.count == 1 && h.effects.count == count, "idempotent lifecycle cancellation")
}
do {
    let h = Harness(); h.controller.request(); h.failSend = true; h.tick(0.008)
    check(h.effects.contains("error") && !h.effects.contains("legacy"), "failure after began")
    let count = h.effects.count; h.callbacks.forEach { $0() }; check(h.effects.count == count, "failed session invalidated")
    check(DockSwipe.verticalSign(natural: true) == 1 && DockSwipe.verticalSign(natural: false) == -1, "vertical sign hypotheses")
}
do {
    let h = Harness(); var signs: [Double] = []; var natural = true; var callbacks: [() -> Void] = []
    let controller = DockGestureController(now: { h.time }, schedule: { _, callback in callbacks.append(callback); return {} }, allowed: { true }, prepare: { _ in
        let sign = DockSwipe.verticalSign(natural: natural)
        return .init { _, _ in signs.append(sign); return true }
    }, finishHorizontal: {}, legacy: {}, error: { _ in preconditionFailure("unexpected error") })
    controller.request(); natural = false; h.time = 0.12; callbacks.removeFirst()()
    check(signs == [1, 1, 1], "sign fixed throughout session")
    controller.request(); check(signs.last == -1, "new sign on next session")
}
print("DockGestureChecks passed")

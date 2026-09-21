import Foundation

// All dependencies are fakes. No CGEvents, Spotlight launch, or OS settings access.
final class Harness {
    var enabled: Bool
    var canRead = true
    var canPrepare = true
    var enableSucceeds = true
    var disableSucceeds = true
    var states: [Bool] = []
    var posted = 0
    var queued: [() -> Void] = []
    var errors: [String] = []
    lazy var shortcut = SpotlightShortcut(api: .init(binding: { [self] in
        canRead ? .init(key: 49, modifiers: 1 << 20) : nil
    }, isEnabled: { [self] in enabled }, setEnabled: { [self] value in
        states.append(value)
        let success = value ? enableSucceeds : disableSucceeds
        if success { enabled = value }
        return success
    }), prepare: { [self] binding in
        precondition(binding.key == 49 && binding.modifiers == 1 << 20)
        return canPrepare ? { [self] in posted += 1 } : nil
    }, schedule: { [self] in queued.append($0) })
    init(enabled: Bool) { self.enabled = enabled }
    func run() { shortcut.perform { [self] in errors.append($0) } }
}

let enabled = Harness(enabled: true)
enabled.run()
precondition(enabled.posted == 1 && enabled.states.isEmpty && enabled.queued.isEmpty)
print("PASS enabled shortcut leaves settings untouched")

let disabled = Harness(enabled: false)
disabled.run()
precondition(disabled.posted == 1 && disabled.states == [true] && disabled.enabled)
disabled.queued[0]()
precondition(disabled.states == [true, false] && !disabled.enabled && disabled.errors.isEmpty)
print("PASS disabled shortcut restores only after queued delivery")

let repeated = Harness(enabled: false)
repeated.run(); repeated.run()
repeated.queued[0]()
precondition(repeated.enabled && repeated.states == [true])
repeated.queued[1]()
precondition(!repeated.enabled && repeated.states == [true, false] && repeated.posted == 2)
print("PASS rapid repeated requests preserve the original disabled state")

for failure in ["read", "prepare"] {
    let h = Harness(enabled: false)
    h.canRead = failure != "read"; h.canPrepare = failure != "prepare"
    h.run()
    precondition(h.posted == 0 && h.states.isEmpty && h.queued.isEmpty && h.errors.count == 1)
}
print("PASS setup failures do not change settings or dispatch")

let rejected = Harness(enabled: false)
rejected.enableSucceeds = false; rejected.run()
precondition(rejected.posted == 0 && rejected.states == [true, false] && !rejected.errors.isEmpty)
print("PASS enabling failure attempts rollback and never dispatches")

let restoration = Harness(enabled: false)
restoration.disableSucceeds = false; restoration.run(); restoration.queued[0]()
precondition(restoration.errors.count == 1)
restoration.disableSucceeds = true; restoration.run(); restoration.queued[1]()
precondition(!restoration.enabled)
print("PASS restoration failure is reported and can recover on the next request")

var unavailableErrors = 0
let unavailable = SpotlightShortcut(api: nil, prepare: { _ in preconditionFailure("Must not prepare") }, schedule: { _ in preconditionFailure("Must not schedule") })
unavailable.perform { _ in unavailableErrors += 1 }
precondition(unavailableErrors == 1)
print("PASS unavailable SPI reports an error without fallback app launch")
let shutdown = Harness(enabled: false)
shutdown.run()
shutdown.shortcut.cancelPendingRestore { _ in preconditionFailure("Unexpected restore error") }
precondition(!shutdown.enabled && shutdown.states == [true, false])
shutdown.queued[0]()
precondition(shutdown.states == [true, false])
print("PASS clean shutdown restores immediately and invalidates pending callbacks")
print("8 isolated checks passed; no real actions executed")

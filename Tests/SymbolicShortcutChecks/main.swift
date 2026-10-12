import Foundation

// All dependencies are fakes. No CGEvents, Spotlight launch, Space switch, or OS settings access.
final class Harness {
    var enabled: Bool
    var fallback: SymbolicShortcut.Binding?
    var prepared: [SymbolicShortcut.Binding] = []
    var canRead = true
    var canPrepare = true
    var enableSucceeds = true
    var disableSucceeds = true
    var states: [Bool] = []
    var posted = 0
    var queued: [() -> Void] = []
    var errors: [String] = []
    lazy var shortcut = SymbolicShortcut(name: "Spotlight", api: .init(binding: { [self] in
        canRead ? .init(key: 49, modifiers: 1 << 20) : nil
    }, isEnabled: { [self] in enabled }, setEnabled: { [self] value in
        states.append(value)
        let success = value ? enableSucceeds : disableSucceeds
        if success { enabled = value }
        return success
    }), fallback: fallback, prepare: { [self] binding in
        prepared.append(binding)
        return canPrepare ? { [self] in posted += 1 } : nil
    }, schedule: { [self] in queued.append($0) })
    init(enabled: Bool) { self.enabled = enabled }
    func run() { shortcut.perform { [self] in errors.append($0) } }
}

let enabled = Harness(enabled: true)
enabled.run()
precondition(enabled.posted == 1 && enabled.states.isEmpty && enabled.queued.isEmpty)
precondition(enabled.prepared == [.init(key: 49, modifiers: 1 << 20)])
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
let unavailable = SymbolicShortcut(name: "Spotlight", api: nil, prepare: { _ in preconditionFailure("Must not prepare") }, schedule: { _ in preconditionFailure("Must not schedule") })
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

// Spaces: WindowServer may omit an unchanged default; the macOS default with Fn is used then.
let spaceDefault = SymbolicShortcut.Binding(key: 123, modifiers: 0x840000)
let reported = Harness(enabled: true)
reported.fallback = spaceDefault; reported.run()
precondition(reported.prepared == [.init(key: 49, modifiers: 1 << 20)] && reported.posted == 1)
print("PASS reported binding wins over the fallback")
let missing = Harness(enabled: true)
missing.fallback = spaceDefault; missing.canRead = false; missing.run()
precondition(missing.prepared == [spaceDefault] && missing.posted == 1 && missing.errors.isEmpty)
print("PASS missing binding uses the default with its Fn flag")
let missingDisabled = Harness(enabled: false)
missingDisabled.fallback = spaceDefault; missingDisabled.canRead = false; missingDisabled.run()
precondition(missingDisabled.posted == 1 && missingDisabled.states == [true])
missingDisabled.queued[0]()
precondition(!missingDisabled.enabled && missingDisabled.states == [true, false])
print("PASS fallback binding still restores a disabled shortcut")
let noBinding = Harness(enabled: false)
noBinding.canRead = false; noBinding.run()
precondition(noBinding.posted == 0 && noBinding.prepared.isEmpty && noBinding.states.isEmpty && noBinding.errors.count == 1)
precondition(noBinding.errors[0].contains("«Spotlight»"))
print("PASS no binding and no fallback reports an error without dispatch")
let left = Harness(enabled: false), right = Harness(enabled: false)
left.run(); right.run()
left.shortcut.cancelPendingRestore { _ in preconditionFailure("Unexpected restore error") }
precondition(!left.enabled && right.enabled && right.states == [true])
right.queued[0]()
precondition(!right.enabled)
print("PASS separate shortcuts restore independently")
print("13 isolated checks passed; no real actions executed")

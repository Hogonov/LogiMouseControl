import AppKit
import Darwin

/// Dispatch a WindowServer symbolic hotkey (Spotlight, Spaces, App Exposé …) with
/// the binding WindowServer currently uses. The defaults file is not read: it omits
/// unchanged defaults, and arrow-key bindings need their Fn flag to match.
/// The private API is resolved at runtime; no defaults/plist files are changed.
final class SymbolicShortcut {
    struct Binding: Equatable {
        let key: CGKeyCode
        let modifiers: UInt32
    }
    struct API {
        var binding: () -> Binding?
        var isEnabled: () -> Bool
        var setEnabled: (Bool) -> Bool

        // Same SPI/signatures used by OpenLogi's symbolic_hotkey.rs (MIT).
        private struct Symbols {
            typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt32>) -> Int32
            typealias Enabled = @convention(c) (UInt32) -> Bool
            typealias SetEnabled = @convention(c) (UInt32, Bool) -> Int32
            let get: Get
            let enabled: Enabled
            let set: SetEnabled
            static let loaded: Symbols? = {
                guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
                      let getSymbol = dlsym(handle, "CGSGetSymbolicHotKeyValue"),
                      let enabledSymbol = dlsym(handle, "CGSIsSymbolicHotKeyEnabled"),
                      let setSymbol = dlsym(handle, "CGSSetSymbolicHotKeyEnabled") else { return nil }
                // Keep the framework loaded for the lifetime of these function pointers.
                return Symbols(get: unsafeBitCast(getSymbol, to: Get.self), enabled: unsafeBitCast(enabledSymbol, to: Enabled.self),
                               set: unsafeBitCast(setSymbol, to: SetEnabled.self))
            }()
        }

        static func system(_ hotKey: UInt32) -> API? {
            guard let symbols = Symbols.loaded else { return nil }
            return API(binding: {
                var character: UInt16 = 0, key: UInt16 = 0, modifiers: UInt32 = 0
                guard symbols.get(hotKey, &character, &key, &modifiers) == 0, key < UInt16.max else { return nil }
                return Binding(key: key, modifiers: modifiers)
            }, isEnabled: { symbols.enabled(hotKey) }, setEnabled: { symbols.set(hotKey, $0) == 0 })
        }
    }

    let name: String
    private let api: API?
    private let fallback: Binding?
    private let prepare: (Binding) -> (() -> Void)?
    private let schedule: (@escaping () -> Void) -> Void
    private var needsRestore = false
    private var generation = 0

    /// `fallback` is the macOS default binding, used only when WindowServer reports none.
    convenience init(hotKey: UInt32, name: String, fallback: Binding? = nil) {
        self.init(name: name, api: .system(hotKey), fallback: fallback, prepare: { binding in
            guard let source = CGEventSource(stateID: .hidSystemState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: binding.key, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: binding.key, keyDown: false) else { return nil }
            let flags = CGEventFlags(rawValue: UInt64(binding.modifiers))
            down.flags = flags; up.flags = flags
            return { down.post(tap: .cgSessionEventTap); up.post(tap: .cgSessionEventTap) }
        }, schedule: { restore in DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: restore) })
    }

    /// Injected dependencies allow checks without any system calls or input events.
    init(name: String, api: API?, fallback: Binding? = nil, prepare: @escaping (Binding) -> (() -> Void)?, schedule: @escaping (@escaping () -> Void) -> Void) {
        self.name = name; self.api = api; self.fallback = fallback; self.prepare = prepare; self.schedule = schedule
    }

    func perform(onError: @escaping (String) -> Void) {
        guard let api else {
            onError("Системная команда «\(name)» недоступна в этой версии macOS."); return
        }
        guard let binding = api.binding() ?? fallback, let post = prepare(binding) else {
            onError("Не удалось прочитать или подготовить сочетание «\(name)». Проверьте его в Системных настройках → Клавиатура → Сочетания клавиш."); return
        }
        if !api.isEnabled() {
            needsRestore = true
            guard api.setEnabled(true) else {
                restore(onError: onError)
                onError("Не удалось временно включить системную команду «\(name)»."); return
            }
        }
        post()
        if needsRestore {
            generation += 1
            let current = generation
            // Posting is asynchronous: restoring immediately can disable the
            // hotkey before WindowServer receives it. Repeated clicks extend
            // this one restoration window, keeping the original disabled state.
            schedule { [self] in
                guard generation == current else { return }
                restore(onError: onError)
            }
        }
    }

    func cancelPendingRestore(onError: (String) -> Void) {
        // Clean shutdown must not leave a temporarily enabled shortcut behind.
        restore(onError: onError)
    }

    private func restore(onError: (String) -> Void) {
        guard needsRestore, let api else { return }
        generation += 1
        if api.setEnabled(false) {
            needsRestore = false
        } else {
            onError("Не удалось вернуть отключённое сочетание «\(name)». Проверьте его в Системных настройках → Клавиатура → Сочетания клавиш.")
        }
    }
}

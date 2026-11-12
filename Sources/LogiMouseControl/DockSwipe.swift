import AppKit
import Darwin
import MouseCore

/// Drives the Spaces transition like a trackpad swipe (ADR-0002). macOS 27 reads an
/// IOHIDEvent attached to a type-30 CGEvent instead of private CGEvent fields.
/// Private functions are resolved at runtime; nothing is written to defaults or
/// system settings.
final class DockSwipe {
    // The vertical backend failed user validation (CH-0007/R-13).
    // Keep requests on the legacy route until the gesture is validated on this OS.
    private static let missionControlGesturesEnabled = false
    private struct Symbols {
        typealias Create = @convention(c) (CFAllocator?, UInt32, UInt64, UInt32) -> Unmanaged<CFTypeRef>?
        typealias SetInteger = @convention(c) (CFTypeRef, UInt32, Int) -> Void
        typealias SetFloat = @convention(c) (CFTypeRef, UInt32, Double) -> Void
        typealias Append = @convention(c) (CFTypeRef, CFTypeRef, UInt32) -> Void
        typealias Attach = @convention(c) (CGEvent, CFTypeRef) -> Void
        let create: Create
        let setInteger: SetInteger
        let setFloat: SetFloat
        let append: Append
        let attach: Attach
        static let loaded: Symbols? = {
            guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27,
                  let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
                  let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
                  let create = dlsym(iokit, "IOHIDEventCreate"), let setInteger = dlsym(iokit, "IOHIDEventSetIntegerValue"),
                  let setFloat = dlsym(iokit, "IOHIDEventSetFloatValue"), let append = dlsym(iokit, "IOHIDEventAppendEvent"),
                  let attach = dlsym(skyLight, "SLEventSetIOHIDEvent") else { return nil }
            // The frameworks stay loaded for the lifetime of these function pointers.
            return Symbols(create: unsafeBitCast(create, to: Create.self), setInteger: unsafeBitCast(setInteger, to: SetInteger.self),
                           setFloat: unsafeBitCast(setFloat, to: SetFloat.self), append: unsafeBitCast(append, to: Append.self),
                           attach: unsafeBitCast(attach, to: Attach.self))
        }()
    }
    private static let dockSwipeType: UInt32 = 23, velocityType: UInt32 = 9
    private static let motionField = dockSwipeType << 16 | 1, progressField = dockSwipeType << 16 | 2, flavorField = dockSwipeType << 16 | 5
    private static let velocityXField = velocityType << 16, velocityYField = velocityType << 16 | 1
    private static let dockPrimaryFlavor = 3
    private static let phaseShift: UInt32 = 24
    private var symbols: Symbols? { Symbols.loaded }
    private var hidSign = -1.0

    /// Without these functions gestures fall back to the discrete desktop shortcuts.
    var isAvailable: Bool { symbols != nil }

    func post(_ step: SwipeStep) {
        guard AXIsProcessTrusted() else { return }
        if step.phase == .began { hidSign = Self.naturalScrolling() ? -1 : 1 }
        makeEvent(step, axis: .horizontal, sign: hidSign)?.post(tap: .cgSessionEventTap)
    }

    /// Allocates every possible vertical frame before the first event is sent.
    func prepareMissionControl(_ config: MissionControlGesture.Configuration) -> DockGestureController.Prepared? {
        guard Self.missionControlGesturesEnabled,
              let count = config.intervalCount, symbols != nil else { return nil }
        let sign = Self.verticalSign(natural: Self.naturalScrolling())
        var events: [String: CGEvent] = [:]
        for index in 0...count {
            let progress = config.targetProgress * (Double(index) / Double(count))
            let steps = [SwipeStep(index == 0 ? .began : .changed, progress: progress), SwipeStep(.cancelled, progress: progress)]
            for step in steps {
                guard let event = makeEvent(step, axis: .vertical, sign: sign) else { return nil }
                events["\(step.phase.rawValue):\(index)"] = event
            }
        }
        guard let end = makeEvent(SwipeStep(.ended, progress: config.targetProgress, velocity: config.targetProgress / config.duration), axis: .vertical, sign: sign) else { return nil }
        events["\(SwipePhase.ended.rawValue):\(count)"] = end
        let preparedEvents = events
        return DockGestureController.Prepared { step, index in
            guard let event = preparedEvents["\(step.phase.rawValue):\(index)"] else { return false }
            event.post(tap: .cgSessionEventTap)
            return true
        }
    }

    private func makeEvent(_ step: SwipeStep, axis: DockGestureAxis, sign: Double) -> CGEvent? {
        guard let symbols else { return nil }
        guard let hid = symbols.create(nil, Self.dockSwipeType, 0, step.phase.rawValue << Self.phaseShift)?.takeRetainedValue(),
              let event = CGEvent(source: nil), let type = CGEventType(rawValue: 30) else { return nil }
        symbols.setInteger(hid, Self.motionField, axis.rawValue)
        symbols.setInteger(hid, Self.flavorField, Self.dockPrimaryFlavor)
        symbols.setFloat(hid, Self.progressField, step.progress * sign)
        if step.phase == .ended || step.phase == .cancelled {
            // macOS 27 drops an end phase without a velocity child.
            guard let velocity = symbols.create(nil, Self.velocityType, 0, 0)?.takeRetainedValue() else { return nil }
            symbols.setFloat(velocity, Self.velocityXField, step.velocity * sign)
            symbols.setFloat(velocity, Self.velocityYField, step.velocity * sign)
            symbols.append(hid, velocity, 0)
        }
        event.type = type
        symbols.attach(event, hid)
        event.setIntegerValueField(.eventSourceUserData, value: ScrollEngine.marker)
        return event
    }
    /// macOS 27 reads the swipe sign the other way when natural scrolling is on.
    /// The key is absent, meaning on, until the user changes the setting.
    private static func naturalScrolling() -> Bool {
        let key = "com.apple.swipescrolldirection"
        return UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
    }
    static func verticalSign(natural: Bool) -> Double { natural ? 1 : -1 }
}

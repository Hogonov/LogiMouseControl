import Foundation

/// Raw values are `IOHIDEventPhaseBits`, the phases of a trackpad Dock swipe.
public enum SwipePhase: UInt32 {
    case began = 1, changed = 2, ended = 4, cancelled = 8
}
/// One Dock swipe event. Progress counts desktops toward the one on the right and is
/// cumulative within a segment; velocity (desktops per second) matters only at the end.
public struct SwipeStep: Equatable {
    public let phase: SwipePhase
    public let progress: Double
    public let velocity: Double
    public init(_ phase: SwipePhase, progress: Double, velocity: Double = 0) {
        self.phase = phase; self.progress = progress; self.velocity = velocity
    }
}
/// Turns horizontal Raw XY travel into a continuous swipe between desktops.
/// A whole desktop of progress ends the segment and starts the next one, so one
/// long movement crosses several desktops without releasing the button.
public struct SpaceSwipe {
    public static let countsPerSpaceAt1000DPI = 800.0
    /// Travel per desktop follows the sensor resolution, so the hand distance stays the same.
    public static func countsPerSpace(dpi: Int?) -> Double {
        guard let dpi, dpi > 0 else { return countsPerSpaceAt1000DPI }
        return countsPerSpaceAt1000DPI * Double(dpi) / 1000
    }
    private let sign: Double
    private let countsPerSpace: Double
    public private(set) var progress = 0.0
    public private(set) var velocity = 0.0
    public private(set) var began = false
    private var lastTime = 0.0

    /// `sign` is +1 when moving right goes to the desktop on the right, −1 when mirrored.
    public init(sign: Double, countsPerSpace: Double) {
        self.sign = sign < 0 ? -1 : 1
        self.countsPerSpace = countsPerSpace.isFinite && countsPerSpace > 0 ? countsPerSpace : Self.countsPerSpaceAt1000DPI
    }
    public mutating func move(dx: Double, at time: Double) -> [SwipeStep] {
        guard dx.isFinite else { return [] }
        let delta = sign * dx / countsPerSpace
        progress += delta
        guard began else {
            began = true; lastTime = time
            return [SwipeStep(.began, progress: progress)] + crossings()
        }
        let dt = min(0.1, max(0.004, time - lastTime))
        lastTime = time
        velocity = 0.6 * velocity + 0.4 * delta / dt
        let crossed = crossings()
        return crossed.isEmpty ? [SwipeStep(.changed, progress: progress)] : crossed
    }
    /// The Dock decides from progress and velocity whether to finish, as after a trackpad swipe;
    /// a flick back cancels.
    public mutating func release(at time: Double) -> [SwipeStep] {
        guard began else { return [] }
        began = false
        let exit = time - lastTime > 0.15 ? 0 : velocity
        let phase: SwipePhase = exit * progress < 0 && abs(exit) > 0.5 ? .cancelled : .ended
        return [SwipeStep(phase, progress: progress, velocity: exit)]
    }
    /// Lifecycle stops return the desktop to where it was.
    public mutating func cancel() -> [SwipeStep] {
        guard began else { return [] }
        began = false
        return [SwipeStep(.cancelled, progress: progress)]
    }
    private mutating func crossings() -> [SwipeStep] {
        var steps: [SwipeStep] = []
        while abs(progress) >= 1 {
            let direction: Double = progress > 0 ? 1 : -1
            steps.append(SwipeStep(.ended, progress: direction, velocity: direction * max(1, abs(velocity))))
            progress -= direction
            steps.append(SwipeStep(.began, progress: progress))
        }
        return steps
    }
}
/// One hold of a gesture control: a smooth desktop swipe when horizontal travel crosses
/// the gesture threshold first, otherwise a direction resolved on release.
public struct GestureSession {
    public enum Outcome: Equatable {
        case action(GestureDirection)
        case swipe([SwipeStep], GestureDirection)
    }
    private var accumulator: GestureAccumulator
    private let swipeSign: Double?
    private let countsPerSpace: Double
    private var swipe: SpaceSwipe?
    private var vertical = false
    public var isSwiping: Bool { swipe?.began ?? false }

    /// `swipeSign` is nil when left and right are not the desktop actions or swipes are unavailable.
    public init(discardFirst: Bool, swipeSign: Double?, countsPerSpace: Double) {
        accumulator = GestureAccumulator(discardFirst: discardFirst)
        self.swipeSign = swipeSign; self.countsPerSpace = countsPerSpace
    }
    /// `allowSwipe` is false while another control drives a swipe.
    public mutating func add(dx: Double, dy: Double, at time: Double, allowSwipe: Bool) -> [SwipeStep] {
        let before = accumulator.x
        accumulator.add(dx: dx, dy: dy)
        if swipe != nil { return swipe!.move(dx: accumulator.x - before, at: time) }
        switch accumulator.direction {
        case .click: return []
        case .up, .down: vertical = true; return []
        case .left, .right:
            guard let swipeSign, allowSwipe, !vertical else { return [] }
            var started = SpaceSwipe(sign: swipeSign, countsPerSpace: countsPerSpace)
            let steps = started.move(dx: accumulator.x, at: time)
            swipe = started
            return steps
        }
    }
    public mutating func release(at time: Double) -> Outcome {
        guard var current = swipe else { return .action(accumulator.direction) }
        swipe = nil
        return .swipe(current.release(at: time), accumulator.x < 0 ? .left : .right)
    }
    public mutating func cancel() -> [SwipeStep] {
        defer { swipe = nil }
        return swipe?.cancel() ?? []
    }
}

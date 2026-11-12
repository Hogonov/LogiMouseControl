import Foundation

public enum DockGestureAxis: Int { case horizontal = 1, vertical = 2 }
public struct DockGestureFrame: Equatable {
    public let axis: DockGestureAxis
    public let step: SwipeStep
    public init(axis: DockGestureAxis, step: SwipeStep) { self.axis = axis; self.step = step }
}

/// Pure description of a bounded opening gesture. No system events are sent here.
public struct MissionControlGesture {
    public struct Configuration {
        public var duration = 0.120
        public var frameInterval = 0.008
        public var targetProgress = 1.0
        public var staleAfter = 0.250
        public init() {}
        public var intervalCount: Int? {
            guard duration.isFinite, frameInterval.isFinite, targetProgress.isFinite, staleAfter.isFinite,
                  duration > 0, frameInterval > 0, targetProgress > 0, staleAfter > duration,
                  (targetProgress / duration).isFinite else { return nil }
            let count = ceil(duration / frameInterval)
            guard count.isFinite, count >= 1, count <= 10_000 else { return nil }
            return Int(count)
        }
    }
    public let configuration: Configuration
    public private(set) var startTime: Double?
    public private(set) var lastIndex = 0
    private var lastTime = 0.0
    public init(configuration: Configuration = Configuration()) { self.configuration = configuration }
    public mutating func start(at time: Double) -> [SwipeStep] {
        guard startTime == nil, time.isFinite, configuration.intervalCount != nil else { return [] }
        startTime = time; lastTime = time; lastIndex = 0
        return [SwipeStep(.began, progress: 0)]
    }
    public mutating func advance(at time: Double) -> [SwipeStep] {
        guard let start = startTime, let count = configuration.intervalCount else { return [] }
        guard time.isFinite else { return cancel() }
        guard time >= lastTime else { return [] }
        lastTime = time
        let age = time - start
        if age >= configuration.staleAfter { return cancel() }
        let index = age >= configuration.duration ? count : min(count, Int(floor(age / configuration.frameInterval)))
        guard index > lastIndex else { return [] }
        lastIndex = index
        let progress = configuration.targetProgress * (Double(index) / Double(count))
        if index == count {
            startTime = nil
            return [SwipeStep(.changed, progress: progress), SwipeStep(.ended, progress: progress, velocity: configuration.targetProgress / configuration.duration)]
        }
        return [SwipeStep(.changed, progress: progress)]
    }
    public mutating func cancel() -> [SwipeStep] {
        guard startTime != nil, let count = configuration.intervalCount else { return [] }
        startTime = nil
        return [SwipeStep(.cancelled, progress: configuration.targetProgress * (Double(lastIndex) / Double(count)))]
    }
}

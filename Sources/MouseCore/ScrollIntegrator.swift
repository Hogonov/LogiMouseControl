import Foundation

/// Time-based exponential interpolation. Input distance is conserved; fractional pixels
/// accumulate instead of being rounded away. Changing direction cancels the old tail.
public struct ScrollIntegrator {
    public private(set) var remaining: Double = 0
    private var fraction: Double = 0
    public init() {}
    public mutating func feed(_ distance: Double) {
        guard distance.isFinite else { return }
        if distance * remaining < 0 { reset() }
        remaining += distance
    }
    public mutating func advance(seconds: Double, smoothness: Double) -> Int32 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        let tau = max(0.015, min(0.18, smoothness))
        let amount = remaining * (1 - exp(-min(seconds, 0.05) / tau))
        remaining -= amount
        fraction += amount
        if abs(remaining) < 0.05 { fraction += remaining; remaining = 0 }
        let whole = fraction.rounded(.towardZero)
        fraction -= whole
        return Int32(clamping: Int64(max(Double(Int32.min), min(Double(Int32.max), whole))))
    }
    public mutating func takeImmediately() -> Int32 {
        fraction += remaining; remaining = 0
        let whole = fraction.rounded(.towardZero); fraction -= whole
        return Int32(clamping: Int64(max(Double(Int32.min), min(Double(Int32.max), whole))))
    }
    public var isActive: Bool { abs(remaining) >= 0.05 }
    public mutating func reset() { remaining = 0; fraction = 0 }
}

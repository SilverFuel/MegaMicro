import Foundation

/// Pure animation curves. All take absolute time `t` (seconds, any epoch)
/// so frames are deterministic and testable.
enum EffectMath {
    /// Sine breathing between 35% and 100% intensity.
    static func breathing(t: TimeInterval, period: Double) -> Double {
        let phase = 0.5 + 0.5 * sin(2 * .pi * t / period)
        return 0.35 + 0.65 * phase
    }

    /// Square-wave on/off at `hz`, 50% duty cycle.
    static func square(t: TimeInterval, hz: Double) -> Bool {
        let cycle = t * hz
        return cycle - floor(cycle) < 0.5
    }

    /// Linear 1→0 over `total` seconds of age, clamped.
    static func fadeOut(age: TimeInterval, total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(max(1 - age / total, 0), 1)
    }

    /// Brightness multiplier for a spec at time `t` with state age `age`.
    static func intensity(for kind: EffectSpec.Kind, t: TimeInterval, age: TimeInterval) -> Double {
        switch kind {
        case .solid: 1
        case .breathing(let period): breathing(t: t, period: period)
        case .blink(let hz), .strobe(let hz): square(t: t, hz: hz) ? 1 : 0
        case .fadeOut(let total): fadeOut(age: age, total: total)
        }
    }
}

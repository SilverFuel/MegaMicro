import Foundation

/// One rendered frame of board lighting. `perLED` indexes match
/// `ControlSpec.ledIndex`; `wholeBoard` is the fallback for devices that can
/// only display a single color (stock VIA firmware).
/// Semantic per-LED state: the configured color and animation kind, before
/// host-side rendering. Devices whose firmware animates on-device (Codex
/// Micro) consume these; the simulator consumes the rendered `perLED` colors.
struct LEDSpec: Hashable, Sendable {
    var color: HSV
    var kind: EffectSpec.Kind
}

struct EffectFrame: Hashable, Sendable {
    var perLED: [HSV]
    var wholeBoard: HSV
    /// Perimeter underglow (rgblight) — independent of the key LEDs.
    var underglow: HSV
    /// ledIndex → semantic spec (color + animation) for on-device rendering.
    var perLEDSpecs: [Int: LEDSpec] = [:]

    static func uniform(_ color: HSV, ledCount: Int) -> EffectFrame {
        EffectFrame(perLED: Array(repeating: color, count: ledCount), wholeBoard: color, underglow: color)
    }
}

/// Pure frame computation: states in, colors out. The 20 Hz drive timer and
/// device I/O live elsewhere.
enum AnimationRenderer {
    /// Color for a single state at time `t` (seconds) with state age `age`.
    static func color(for state: AgentState, rules: RGBRules, t: TimeInterval, age: TimeInterval) -> HSV {
        let spec = rules.spec(for: state)
        return spec.color.scaled(brightness: EffectMath.intensity(for: spec.kind, t: t, age: age))
    }

    /// Whole frame. One agent = one key: unassigned LEDs rest at idle; each
    /// entry in `perKeyStates` (ledIndex → state, age) lights its own key.
    /// `aggregate` (highest-priority state across all agents) is rendered
    /// only into `wholeBoard`, the fallback for hardware without per-key
    /// control — it never floods the per-key view.
    static func frame(
        aggregate: AgentState,
        aggregateAge: TimeInterval,
        perKeyStates: [Int: (state: AgentState, age: TimeInterval)],
        rules: RGBRules,
        underglowMode: UnderglowMode = .aggregate,
        ledCount: Int,
        t: TimeInterval
    ) -> EffectFrame {
        let idleSpec = rules.spec(for: .idle)
        let idleColor = color(for: .idle, rules: rules, t: t, age: 0)
        var leds = Array(repeating: idleColor, count: ledCount)
        var specs: [Int: LEDSpec] = [:]
        for index in 0..<ledCount {
            specs[index] = LEDSpec(color: idleSpec.color, kind: idleSpec.kind)
        }
        for (index, entry) in perKeyStates where index >= 0 && index < ledCount {
            leds[index] = color(for: entry.state, rules: rules, t: t, age: entry.age)
            let spec = rules.spec(for: entry.state)
            specs[index] = LEDSpec(color: spec.color, kind: spec.kind)
        }
        let aggregateColor = color(for: aggregate, rules: rules, t: t, age: aggregateAge)
        let underglow: HSV = switch underglowMode {
        case .aggregate: aggregateColor
        case .solid(let hsv): hsv
        case .off: .off
        }
        return EffectFrame(perLED: leds, wholeBoard: aggregateColor, underglow: underglow, perLEDSpecs: specs)
    }
}

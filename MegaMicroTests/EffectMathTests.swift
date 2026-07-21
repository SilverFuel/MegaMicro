import XCTest
@testable import MegaMicro

final class EffectMathTests: XCTestCase {
    func testBreathingRange() {
        for t in stride(from: 0.0, through: 5.0, by: 0.05) {
            let v = EffectMath.breathing(t: t, period: 1.4)
            XCTAssertGreaterThanOrEqual(v, 0.35 - 1e-9)
            XCTAssertLessThanOrEqual(v, 1.0 + 1e-9)
        }
        // Peak at quarter period (sin = 1)
        XCTAssertEqual(EffectMath.breathing(t: 0.35, period: 1.4), 1.0, accuracy: 1e-9)
    }

    func testSquareWave2Hz() {
        XCTAssertTrue(EffectMath.square(t: 0.0, hz: 2))    // on 0–0.25
        XCTAssertTrue(EffectMath.square(t: 0.24, hz: 2))
        XCTAssertFalse(EffectMath.square(t: 0.26, hz: 2))  // off 0.25–0.5
        XCTAssertTrue(EffectMath.square(t: 0.51, hz: 2))   // next cycle
    }

    func testFadeOut() {
        XCTAssertEqual(EffectMath.fadeOut(age: 0, total: 45), 1.0)
        XCTAssertEqual(EffectMath.fadeOut(age: 22.5, total: 45), 0.5, accuracy: 1e-9)
        XCTAssertEqual(EffectMath.fadeOut(age: 46, total: 45), 0.0)
    }

    func testHSVToRGBPrimaries() {
        let red = HSV(h: 0, s: 255, v: 255).rgb
        XCTAssertEqual(red.r, 1.0, accuracy: 0.01)
        XCTAssertEqual(red.g, 0.0, accuracy: 0.05)
        let green = HSV(h: 85, s: 255, v: 255).rgb
        XCTAssertEqual(green.g, 1.0, accuracy: 0.01)
        XCTAssertEqual(green.r, 0.0, accuracy: 0.05)
        let blue = HSV(h: 170, s: 255, v: 255).rgb
        XCTAssertEqual(blue.b, 1.0, accuracy: 0.01)
        XCTAssertEqual(blue.g, 0.0, accuracy: 0.06)
    }

    func testFrameOneAgentLightsOneKeyOnly() {
        let rules = RGBRules.standard
        let frame = AnimationRenderer.frame(
            aggregate: .error, aggregateAge: 0,
            perKeyStates: [3: (state: .error, age: 0)],
            rules: rules, ledCount: 12, t: 0)
        XCTAssertEqual(frame.perLED.count, 12)
        // Error strobe at t=0 is "on": red at full spec brightness
        XCTAssertEqual(frame.perLED[3], rules.spec(for: .error).color)
        // All other keys stay idle even though the aggregate is error —
        // one agent must never flood the board.
        XCTAssertEqual(frame.perLED[0], rules.spec(for: .idle).color)
        // The whole-board fallback (per-key-incapable hardware) shows the aggregate.
        XCTAssertEqual(frame.wholeBoard, rules.spec(for: .error).color)
        // Default underglow mode mirrors the aggregate (fleet status halo).
        XCTAssertEqual(frame.underglow, rules.spec(for: .error).color)
    }

    func testUnderglowModes() {
        let rules = RGBRules.standard
        let solid = HSV(h: 200, s: 255, v: 99)
        let solidFrame = AnimationRenderer.frame(
            aggregate: .error, aggregateAge: 0, perKeyStates: [:],
            rules: rules, underglowMode: .solid(solid), ledCount: 12, t: 0)
        XCTAssertEqual(solidFrame.underglow, solid, "solid mode ignores agent states")

        let offFrame = AnimationRenderer.frame(
            aggregate: .error, aggregateAge: 0, perKeyStates: [:],
            rules: rules, underglowMode: .off, ledCount: 12, t: 0)
        XCTAssertEqual(offFrame.underglow, .off)
    }

    func testProfileWithoutUnderglowFieldDecodes() throws {
        // A profile saved before underglow existed.
        var profile = DefaultProfiles.ghostty
        profile.underglow = .aggregate
        var encoded = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(profile)) as! [String: Any]
        encoded.removeValue(forKey: "underglow")
        let data = try JSONSerialization.data(withJSONObject: encoded)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(decoded.underglow, .aggregate)
        XCTAssertEqual(decoded.id, profile.id)
    }
}

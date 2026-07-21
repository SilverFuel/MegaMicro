import Foundation

/// Color in QMK's HSV convention: all three components 0–255.
/// (QMK hue wraps at 256, not 360.)
struct HSV: Codable, Hashable, Sendable {
    var h: UInt8
    var s: UInt8
    var v: UInt8

    static let off = HSV(h: 0, s: 0, v: 0)

    /// RGB components 0–1, suitable for SwiftUI Color or 0–255 scaling.
    var rgb: (r: Double, g: Double, b: Double) {
        let h = Double(self.h) / 255.0 * 6.0
        let s = Double(self.s) / 255.0
        let v = Double(self.v) / 255.0
        let i = floor(h)
        let f = h - i
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))
        switch Int(i) % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    init(h: UInt8, s: UInt8, v: UInt8) {
        self.h = h
        self.s = s
        self.v = v
    }

    /// From RGB components 0–1 (e.g. a color picker's output).
    init(r: Double, g: Double, b: Double) {
        let maxV = max(r, g, b)
        let minV = min(r, g, b)
        let delta = maxV - minV
        var hue: Double = 0
        if delta > 0 {
            if maxV == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxV == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        let sat = maxV == 0 ? 0 : delta / maxV
        self.init(
            h: UInt8((hue * 255).rounded()),
            s: UInt8((sat * 255).rounded()),
            v: UInt8((maxV * 255).rounded()))
    }

    func scaled(brightness: Double) -> HSV {
        let clamped = min(max(brightness, 0), 1)
        return HSV(h: h, s: s, v: UInt8((Double(v) * clamped).rounded()))
    }
}

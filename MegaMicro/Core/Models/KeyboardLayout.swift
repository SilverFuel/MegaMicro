import Foundation

/// Rectangle in abstract grid units (1.0 = one key). Used only for rendering
/// the on-screen keyboard; has no meaning to the hardware.
struct GridRect: Codable, Hashable, Sendable {
    var x: Double, y: Double, w: Double, h: Double
}

struct ControlSpec: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case key, dial, joystick, touchStrip
        /// Small non-mechanical button (the Codex Micro's round black
        /// profile-switch button).
        case touchButton
    }

    var id: ControlID
    var kind: Kind
    var frame: GridRect
    /// WS2812 LED index on the device, nil for controls without an LED.
    /// Provisional for the Codex Micro until the hardware probe (M7).
    var ledIndex: Int?
    var legend: String?
    var gestures: [ControlGesture]
    /// Whether an agent can live on this key. On the Codex Micro only the
    /// six translucent keys host agents (matching the firmware's addressable
    /// agent-key ids 0–5); action keys, the Talk key, and the Codex key are
    /// command keys.
    var hostsAgents: Bool = true

    init(id: ControlID, kind: Kind, frame: GridRect, ledIndex: Int?,
         legend: String?, gestures: [ControlGesture], hostsAgents: Bool = true) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.ledIndex = ledIndex
        self.legend = legend
        self.gestures = gestures
        self.hostsAgents = hostsAgents
    }

    // Tolerant decoding: layouts saved before hostsAgents existed default it
    // to true (imported boards host agents on every key).
    enum CodingKeys: String, CodingKey {
        case id, kind, frame, ledIndex, legend, gestures, hostsAgents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ControlID.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        frame = try c.decode(GridRect.self, forKey: .frame)
        ledIndex = try c.decodeIfPresent(Int.self, forKey: .ledIndex)
        legend = try c.decodeIfPresent(String.self, forKey: .legend)
        gestures = try c.decodeIfPresent([ControlGesture].self, forKey: .gestures) ?? [.press]
        hostsAgents = try c.decodeIfPresent(Bool.self, forKey: .hostsAgents) ?? true
    }
}

/// Data-driven description of a physical keyboard. Drives both the on-screen
/// rendering and the mapping UI; adding support for another keyboard means
/// adding another layout value, not new code.
struct KeyboardLayout: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var columns: Double
    var rows: Double
    var controls: [ControlSpec]

    var ledCount: Int { controls.compactMap(\.ledIndex).count }

    func control(_ id: ControlID) -> ControlSpec? {
        controls.first { $0.id == id }
    }
}

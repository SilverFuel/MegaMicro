import Foundation

/// Stable identifier for a physical control on a keyboard, e.g. "key.0",
/// "dial", "joystick", "touchStrip". String-backed so it survives layout
/// evolution and encodes as a plain JSON object key.
struct ControlID: RawRepresentable, Hashable, Codable, CodingKeyRepresentable, Identifiable, Sendable {
    var rawValue: String
    var id: String { rawValue }

    init(rawValue: String) { self.rawValue = rawValue }

    static func key(_ index: Int) -> ControlID { ControlID(rawValue: "key.\(index)") }
    static let dial = ControlID(rawValue: "dial")
    static let joystick = ControlID(rawValue: "joystick")
    static let touchStrip = ControlID(rawValue: "touchStrip")
}

/// A gesture performable on a control. Keys only support `.press`; encoders
/// rotate, joysticks have four directions, touch strips swipe.
enum ControlGesture: String, Codable, Hashable, CaseIterable, Sendable {
    case press
    case clockwise, counterclockwise
    case up, down, left, right
    case swipeLeft, swipeRight
}

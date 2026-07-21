import Foundation

/// Physical layout of the Work Louder Codex Micro (Creator Micro 2 family):
/// rotary dial + 2 keys + joystick on top, two 4-key rows, and a bottom row
/// (small key, wide mic key, codex key). No touch strip on this device.
/// Geometry is from device photos; LED indices are provisional until the M7
/// hardware probe confirms them.
enum CodexMicroLayout {
    static let layout = KeyboardLayout(
        id: "codex-micro",
        name: "Codex Micro",
        columns: 4,
        rows: 4,
        controls: [
            ControlSpec(id: .dial, kind: .dial,
                        frame: GridRect(x: 0, y: 0, w: 1, h: 1),
                        ledIndex: nil, legend: nil,
                        gestures: [.press, .clockwise, .counterclockwise]),
            ControlSpec(id: .key(0), kind: .key,
                        frame: GridRect(x: 1, y: 0, w: 1, h: 1),
                        ledIndex: 0, legend: nil, gestures: [.press]),
            ControlSpec(id: .key(1), kind: .key,
                        frame: GridRect(x: 2, y: 0, w: 1, h: 1),
                        ledIndex: 1, legend: nil, gestures: [.press]),
            ControlSpec(id: .joystick, kind: .joystick,
                        frame: GridRect(x: 3, y: 0, w: 1, h: 1),
                        ledIndex: nil, legend: nil,
                        gestures: [.up, .down, .left, .right]),

            ControlSpec(id: .key(2), kind: .key,
                        frame: GridRect(x: 0, y: 1, w: 1, h: 1),
                        ledIndex: 2, legend: nil, gestures: [.press]),
            ControlSpec(id: .key(3), kind: .key,
                        frame: GridRect(x: 1, y: 1, w: 1, h: 1),
                        ledIndex: 3, legend: nil, gestures: [.press]),
            ControlSpec(id: .key(4), kind: .key,
                        frame: GridRect(x: 2, y: 1, w: 1, h: 1),
                        ledIndex: 4, legend: nil, gestures: [.press]),
            ControlSpec(id: .key(5), kind: .key,
                        frame: GridRect(x: 3, y: 1, w: 1, h: 1),
                        ledIndex: 5, legend: nil, gestures: [.press]),

            ControlSpec(id: .key(6), kind: .key,
                        frame: GridRect(x: 0, y: 2, w: 1, h: 1),
                        ledIndex: 6, legend: "sf:bolt", gestures: [.press], hostsAgents: false),
            ControlSpec(id: .key(7), kind: .key,
                        frame: GridRect(x: 1, y: 2, w: 1, h: 1),
                        ledIndex: 7, legend: "sf:checkmark.circle", gestures: [.press], hostsAgents: false),
            ControlSpec(id: .key(8), kind: .key,
                        frame: GridRect(x: 2, y: 2, w: 1, h: 1),
                        ledIndex: 8, legend: "sf:xmark.circle", gestures: [.press], hostsAgents: false),
            ControlSpec(id: .key(9), kind: .key,
                        frame: GridRect(x: 3, y: 2, w: 1, h: 1),
                        ledIndex: 9, legend: "sf:arrow.turn.up.right", gestures: [.press], hostsAgents: false),

            ControlSpec(id: .key(10), kind: .touchButton,
                        frame: GridRect(x: 0, y: 3, w: 1, h: 1),
                        ledIndex: nil, legend: nil, gestures: [.press]),
            ControlSpec(id: .key(11), kind: .key,
                        frame: GridRect(x: 1, y: 3, w: 2, h: 1),
                        ledIndex: 10, legend: "sf:mic", gestures: [.press], hostsAgents: false),
            ControlSpec(id: .key(12), kind: .key,
                        frame: GridRect(x: 3, y: 3, w: 1, h: 1),
                        ledIndex: 11, legend: "brand:codex", gestures: [.press], hostsAgents: false),
        ])
}

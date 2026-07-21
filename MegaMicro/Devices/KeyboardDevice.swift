import Foundation

struct DeviceCapabilities: Sendable {
    var perKeyRGB: Bool
    var underglow: Bool
    var maxBrightness: UInt8
}

/// The hardware boundary. Everything above this protocol is device-agnostic:
/// MockDevice drives the on-screen simulator today, VIAHIDDevice drives the
/// real Creator Micro when it arrives (M7), other keyboards slot in later.
protocol KeyboardDevice: AnyObject {
    var layout: KeyboardLayout { get }
    var capabilities: DeviceCapabilities { get }
    var isConnected: Bool { get }

    func connect() throws
    func disconnect()

    /// Push one rendered lighting frame. Devices without per-key control
    /// collapse to `frame.wholeBoard`.
    func apply(_ frame: EffectFrame)

    /// Escape hatch for diagnostics/probing (M7). Exactly 32 bytes.
    func sendRaw(_ report: [UInt8]) throws
}

import Foundation

/// Simulated keyboard used for all development before the hardware arrives —
/// the on-screen KeyboardView renders whatever frame was last applied, so the
/// UI literally is the LEDs.
final class MockDevice: KeyboardDevice {
    let layout: KeyboardLayout
    let capabilities = DeviceCapabilities(perKeyRGB: true, underglow: true, maxBrightness: 150)
    private(set) var isConnected = true
    private(set) var lastFrame: EffectFrame?
    private(set) var rawLog: [[UInt8]] = []

    init(layout: KeyboardLayout) {
        self.layout = layout
    }

    func connect() {}
    func disconnect() { isConnected = false }

    func apply(_ frame: EffectFrame) {
        lastFrame = frame
    }

    func sendRaw(_ report: [UInt8]) throws {
        rawLog.append(report)
    }
}

import Foundation

/// QMK/VIA raw-HID backend, implementing VIA's public custom-value protocol
/// (see the VIA/QMK sources). Whether the Creator Micro 2 / Codex Micro
/// exposes this interface is unknown until the probe runs on real hardware —
/// everything above the KeyboardDevice protocol works either way.
///
/// VIA custom-value command framing (32-byte reports, zero-padded):
///   [0x07, channel, valueID, ...payload]
///   channel 0x03 = rgb_matrix (per-key backlight), 0x02 = rgblight (underglow)
///   valueID 0x01 = brightness (0–255, effective max ~150)
///           0x02 = effect (1 = solid)
///           0x04 = color (hue 0–255, sat 0–255)
final class VIAHIDDevice: KeyboardDevice {
    enum Command {
        static let getProtocolVersion: UInt8 = 0x01
        static let customSetValue: UInt8 = 0x07
    }
    enum Channel {
        static let rgblight: UInt8 = 0x02
        static let rgbMatrix: UInt8 = 0x03
    }
    enum Value {
        static let brightness: UInt8 = 0x01
        static let effect: UInt8 = 0x02
        static let color: UInt8 = 0x04
    }
    static let effectSolid: UInt8 = 1

    let layout: KeyboardLayout
    let capabilities = DeviceCapabilities(perKeyRGB: false, underglow: true, maxBrightness: 150)

    private let transport: HIDTransport
    private var lastMatrix: HSV?
    private var lastUnderglow: HSV?
    private(set) var isConnected = false

    var onConnectionChange: ((Bool) -> Void)?

    init(layout: KeyboardLayout, transport: HIDTransport = HIDTransport()) {
        self.layout = layout
        self.transport = transport
        transport.onConnectionChange = { [weak self] connected in
            self?.isConnected = connected
            if !connected {
                self?.lastMatrix = nil
                self?.lastUnderglow = nil
            }
            self?.onConnectionChange?(connected)
        }
    }

    func connect() throws {
        try transport.open(vendorID: HIDTransport.workLouderVendorID, productID: nil)
        isConnected = true
        // Solid effect once on connect; after that only color/brightness change.
        try? sendSolidEffect()
    }

    func disconnect() {
        transport.close()
        isConnected = false
        lastMatrix = nil
        lastUnderglow = nil
    }

    /// Stock VIA firmware has no per-key control: the key matrix collapses to
    /// the whole-board color. The perimeter underglow (rgblight) is driven
    /// independently. Identical consecutive values are skipped (the 20 Hz
    /// loop ticks even when nothing changes).
    func apply(_ frame: EffectFrame) {
        guard isConnected else { return }
        let matrix = clamped(frame.wholeBoard)
        if lastMatrix != matrix {
            lastMatrix = matrix
            send(matrix, to: Channel.rgbMatrix)
        }
        let underglow = clamped(frame.underglow)
        if lastUnderglow != underglow {
            lastUnderglow = underglow
            send(underglow, to: Channel.rgblight)
        }
    }

    private func clamped(_ color: HSV) -> HSV {
        HSV(h: color.h, s: color.s, v: min(color.v, capabilities.maxBrightness))
    }

    private func send(_ color: HSV, to channel: UInt8) {
        try? transport.write([Command.customSetValue, channel, Value.color, color.h, color.s])
        try? transport.write([Command.customSetValue, channel, Value.brightness, color.v])
    }

    func sendRaw(_ report: [UInt8]) throws {
        try transport.write(report)
    }

    private func sendSolidEffect() throws {
        for channel in [Channel.rgbMatrix, Channel.rgblight] {
            try transport.write([Command.customSetValue, channel, Value.effect, Self.effectSolid])
        }
    }
}

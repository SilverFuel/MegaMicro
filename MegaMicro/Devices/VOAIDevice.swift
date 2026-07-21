import Foundation

/// Codex Micro / Creator Micro 2 backend: per-key agent lighting over the
/// firmware's JSON-RPC HID protocol (`v.oai.thstatus`). The firmware animates
/// effects on-device, so we send one small message per state change instead
/// of a 20 Hz color stream.
///
/// UNVALIDATED ON HARDWARE until the first physical unit arrives — built from
/// the OpenAI device-kit protocol as documented by DevVig/microbridge (MIT),
/// confirmed non-VIA by Work Louder.
final class VOAIDevice: KeyboardDevice {
    /// The firmware addresses six agent keys, ids 0–5.
    static let agentKeyCount = 6

    let layout: KeyboardLayout
    let capabilities = DeviceCapabilities(perKeyRGB: true, underglow: true, maxBrightness: 255)

    private let transport: HIDTransport
    private var accumulator = VOAI.FrameAccumulator()
    private var requestID = 0
    private var lastParams: [VOAI.ThreadParam]?
    private(set) var isConnected = false
    private(set) var connectedProduct: String?

    var onConnectionChange: ((Bool) -> Void)?
    /// Semantic input from the pad itself (keys, dial, joystick) — no event
    /// tap or Input-app setup involved.
    var onDeviceEvent: ((VOAI.DeviceEvent) -> Void)?

    init(layout: KeyboardLayout, transport: HIDTransport = HIDTransport(reportSize: VOAI.reportSize, usesLeadingReportID: true)) {
        self.layout = layout
        self.transport = transport
        transport.onConnectionChange = { [weak self] connected in
            self?.isConnected = connected
            if !connected { self?.lastParams = nil }
            self?.onConnectionChange?(connected)
        }
        transport.onInputReport = { [weak self] report in
            guard let self else { return }
            if let (channel, message) = self.accumulator.append(report),
               let event = VOAI.parseMessage(channel: channel, message: message) {
                self.onDeviceEvent?(event)
            }
        }
    }

    func connect() throws {
        try transport.open(
            vendorID: VOAI.vendorID,
            productIDs: VOAI.allPIDs,
            usagePage: VOAI.usagePage,
            usage: nil)
        isConnected = true
    }

    func disconnect() {
        transport.close()
        isConnected = false
        lastParams = nil
    }

    /// Translate the frame's semantic per-LED specs into thread lighting
    /// params; send only when something actually changed.
    func apply(_ frame: EffectFrame) {
        guard isConnected else { return }
        var params: [VOAI.ThreadParam] = []
        for id in 0..<Self.agentKeyCount {
            guard let spec = frame.perLEDSpecs[id] else { continue }
            let (effect, speed) = VOAI.effectParams(for: spec.kind)
            var brightness = Double(spec.color.v) / 255.0
            if case .fadeOut = spec.kind, id < frame.perLED.count {
                // Firmware has no fade effect: ride the host-rendered value,
                // quantized so the fade is ~16 messages, not 900.
                brightness = (Double(frame.perLED[id].v) / 255.0 * 16).rounded() / 16
            }
            params.append(VOAI.ThreadParam(
                id: id,
                c: VOAI.packedRGB(spec.color),
                b: brightness,
                e: effect.rawValue,
                s: speed))
        }
        guard params != lastParams else { return }
        lastParams = params
        do {
            requestID += 1
            let message = try VOAI.threadStatusRequest(id: requestID, params: params)
            for report in VOAI.frames(channel: VOAI.channelRPC, message: message) {
                try transport.write(report)
            }
        } catch {
            // Dropped frame; next state change retries.
        }
    }

    func sendRaw(_ report: [UInt8]) throws {
        try transport.write(report)
    }
}

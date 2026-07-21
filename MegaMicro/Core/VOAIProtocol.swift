import Foundation

/// The Codex Micro / Creator Micro 2 wire protocol: compact JSON-RPC carried
/// in 64-byte HID reports. Derived from OpenAI's published device kit (as
/// documented by the MIT-licensed DevVig/microbridge project); confirmed by
/// Work Louder that this hardware family is not QMK/VIA.
///
/// Frame layout (64 bytes): [reportID 0x06][channel][payload len 0–61][UTF-8
/// payload…]. Messages longer than 61 bytes span consecutive reports; a
/// report with len < 61 terminates the message.
enum VOAI {
    // MARK: Identity

    static let vendorID = 0x303A                 // Espressif (ESP32-class board)
    static let codexMicroPID = 0x8360
    static let creatorMicro2PIDs = [0x8297, 0x8298]
    static var allPIDs: [Int] { [codexMicroPID] + creatorMicro2PIDs }
    static let usagePage = 0xFF00

    static func productName(forPID pid: Int) -> String? {
        switch pid {
        case codexMicroPID: "Codex Micro"
        case 0x8297, 0x8298: "Creator Micro 2"
        default: nil
        }
    }

    // MARK: Framing

    static let reportID: UInt8 = 0x06
    static let reportSize = 64
    static let maxChunk = 61
    static let channelDebug: UInt8 = 1
    static let channelRPC: UInt8 = 2

    /// Split a message into 64-byte reports (report id included as byte 0).
    /// A message that fills its last chunk exactly gets a zero-length
    /// terminator report so the receiver knows it ended.
    static func frames(channel: UInt8, message: Data) -> [[UInt8]] {
        var reports: [[UInt8]] = []
        var offset = 0
        repeat {
            let chunk = message.dropFirst(offset).prefix(maxChunk)
            var report = [UInt8](repeating: 0, count: reportSize)
            report[0] = reportID
            report[1] = channel
            report[2] = UInt8(chunk.count)
            for (i, byte) in chunk.enumerated() {
                report[3 + i] = byte
            }
            reports.append(report)
            offset += chunk.count
        } while offset < message.count
        if message.count > 0, message.count % maxChunk == 0 {
            var terminator = [UInt8](repeating: 0, count: reportSize)
            terminator[0] = reportID
            terminator[1] = channel
            reports.append(terminator)
        }
        return reports
    }

    /// Reassembles chunked incoming reports into complete messages.
    struct FrameAccumulator {
        private var buffers: [UInt8: Data] = [:]   // per channel

        /// Feed one incoming report; returns (channel, message) when complete.
        mutating func append(_ report: [UInt8]) -> (channel: UInt8, message: Data)? {
            // Tolerate transports that strip the leading report id.
            let bytes = report.first == VOAI.reportID ? Array(report.dropFirst()) : report
            guard bytes.count >= 2 else { return nil }
            let channel = bytes[0]
            let length = Int(bytes[1])
            guard length <= maxChunk, bytes.count >= 2 + length else { return nil }
            buffers[channel, default: Data()].append(contentsOf: bytes[2..<(2 + length)])
            if length < maxChunk {
                let message = buffers.removeValue(forKey: channel) ?? Data()
                return (channel, message)
            }
            return nil
        }
    }

    // MARK: RPC

    /// Per-key lighting for the agent keys (ids 0–5).
    /// Optionals are omitted from the JSON entirely.
    struct ThreadParam: Codable, Hashable, Sendable {
        var id: Int
        var c: UInt32?     // packed 0xRRGGBB
        var b: Double?     // brightness 0–1
        var e: UInt8?      // effect (see Effect)
        var s: Double?     // speed 0–1
    }

    enum Effect: UInt8 {
        case off = 0, solid = 1, snake = 2, rainbow = 3
        case breath = 4, gradient = 5, shallowBreath = 6
    }

    static let methodThreadStatus = "v.oai.thstatus"
    static let methodRGBConfig = "v.oai.rgbcfg"      // reserved by firmware, unimplemented
    static let notifyHID = "v.oai.hid"
    static let notifyJoystick = "v.oai.rad"

    /// Compact JSON request. Ids cycle 0–999 per the kit convention.
    static func threadStatusRequest(id: Int, params: [ThreadParam]) throws -> Data {
        struct Request: Encodable {
            let id: Int
            let method: String
            let params: [ThreadParam]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Request(id: id % 1000, method: methodThreadStatus, params: params))
    }

    // MARK: Incoming events

    enum DeviceEvent: Equatable {
        case key(index: Int, action: String?)
        case joystick(angle: Double, distance: Double)
        case debug(String)
        case other(method: String)
    }

    static func parseMessage(channel: UInt8, message: Data) -> DeviceEvent? {
        if channel == channelDebug {
            return .debug(String(decoding: message, as: UTF8.self))
        }
        guard let object = try? JSONSerialization.jsonObject(with: message) as? [String: Any],
              let method = object["method"] as? String else { return nil }
        let params = object["params"] as? [String: Any] ?? [:]
        switch method {
        case notifyHID:
            guard let key = params["k"] as? Int else { return .other(method: method) }
            return .key(index: key, action: params["act"] as? String)
        case notifyJoystick:
            let angle = (params["a"] as? NSNumber)?.doubleValue ?? 0
            let distance = (params["d"] as? NSNumber)?.doubleValue ?? 0
            return .joystick(angle: angle, distance: distance)
        default:
            return .other(method: method)
        }
    }

    // MARK: Effect translation (our States & Colors → firmware effects)

    static func packedRGB(_ hsv: HSV) -> UInt32 {
        // Hue/saturation at full value; brightness travels separately in `b`.
        let rgb = HSV(h: hsv.h, s: hsv.s, v: 255).rgb
        let r = UInt32((rgb.r * 255).rounded())
        let g = UInt32((rgb.g * 255).rounded())
        let b = UInt32((rgb.b * 255).rounded())
        return (r << 16) | (g << 8) | b
    }

    /// Our animation kinds → firmware effect + speed. The firmware animates
    /// on-device, so state changes are one message, not a 20 Hz stream.
    static func effectParams(for kind: EffectSpec.Kind) -> (effect: Effect, speed: Double?) {
        switch kind {
        case .solid:
            (.solid, nil)
        case .breathing(let period):
            (.breath, clamp(1.54 / max(period, 0.1), 0.15, 1.0))
        case .blink(let hz):
            (.breath, clamp(hz / 2.4, 0.2, 1.0))
        case .strobe:
            (.breath, 1.0)
        case .fadeOut:
            (.solid, nil)   // brightness rides in `b`, quantized by the device layer
        }
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}

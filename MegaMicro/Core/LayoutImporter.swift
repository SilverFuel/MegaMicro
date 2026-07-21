import Foundation

/// Imports keyboard layouts from the community-standard JSON formats:
/// - VIA keyboard definitions (usevia.app) — a dict with `name` and
///   `layouts.keymap` (KLE rows), published for thousands of boards
/// - Bare KLE (keyboard-layout-editor.com) — a top-level array of rows
///
/// v1 scope: keys only (position/size). Rotated keys, encoders, and decals
/// beyond skipping are not imported yet; LED indices are assumed sequential
/// until hardware probing can confirm them.
enum LayoutImporter {
    enum ImportError: LocalizedError {
        case unrecognizedFormat
        case noKeys

        var errorDescription: String? {
            switch self {
            case .unrecognizedFormat:
                "Not a VIA definition or KLE layout — expected JSON with layouts.keymap, or a top-level array of rows."
            case .noKeys:
                "The layout contains no keys."
            }
        }
    }

    static func parse(data: Data, fallbackName: String) throws -> KeyboardLayout {
        let json = try JSONSerialization.jsonObject(with: data)
        var name = fallbackName
        var keymap: [Any]?

        if let dict = json as? [String: Any] {
            name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? fallbackName
            if let layouts = dict["layouts"] as? [String: Any] {
                keymap = layouts["keymap"] as? [Any]
            }
        } else if let array = json as? [Any] {
            keymap = array
        }
        guard let keymap else { throw ImportError.unrecognizedFormat }

        let frames = parseKLERows(keymap)
        guard !frames.isEmpty else { throw ImportError.noKeys }

        let controls = frames.enumerated().map { index, frame in
            ControlSpec(id: .key(index), kind: .key, frame: frame,
                        ledIndex: index, legend: nil, gestures: [.press])
        }
        return KeyboardLayout(
            id: "custom-" + slug(name),
            name: name,
            columns: frames.map { $0.x + $0.w }.max() ?? 1,
            rows: frames.map { $0.y + $0.h }.max() ?? 1,
            controls: controls)
    }

    /// KLE's stateful row format: rows are arrays mixing property objects
    /// (which adjust the cursor or the NEXT key) and strings (keys).
    private static func parseKLERows(_ rows: [Any]) -> [GridRect] {
        var result: [GridRect] = []
        var y = 0.0
        for row in rows {
            // KLE files often start with a metadata dict — not a row.
            guard let items = row as? [Any] else { continue }
            var x = 0.0
            var w = 1.0
            var h = 1.0
            var isDecal = false
            for item in items {
                if let props = item as? [String: Any] {
                    if let dx = double(props["x"]) { x += dx }
                    if let dy = double(props["y"]) { y += dy }
                    if let width = double(props["w"]) { w = width }
                    if let height = double(props["h"]) { h = height }
                    if let decal = props["d"] as? Bool { isDecal = decal }
                } else if item is String {
                    if !isDecal {
                        result.append(GridRect(x: x, y: y, w: w, h: h))
                    }
                    x += w
                    w = 1; h = 1; isDecal = false
                }
            }
            y += 1
        }
        return result
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    private static func slug(_ name: String) -> String {
        let lowered = name.lowercased()
        let mapped = lowered.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(mapped).split(separator: "-").joined(separator: "-")
    }
}

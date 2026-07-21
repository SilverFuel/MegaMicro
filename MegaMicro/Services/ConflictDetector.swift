import AppKit

/// Only one process can own the keyboard's raw HID interface. Detect the
/// known contenders so we can tell the user to close them before connecting.
enum ConflictDetector {
    struct Conflict {
        let name: String
        let advice: String
    }

    static func check() -> [Conflict] {
        var conflicts: [Conflict] = []
        for app in NSWorkspace.shared.runningApplications {
            let name = app.localizedName ?? ""
            let bundle = app.bundleIdentifier ?? ""
            if name.localizedCaseInsensitiveContains("Work Louder")
                || bundle.localizedCaseInsensitiveContains("worklouder")
                || (name == "Input" && bundle.localizedCaseInsensitiveContains("input")) {
                conflicts.append(Conflict(
                    name: name.isEmpty ? bundle : name,
                    advice: "Quit the Work Louder Input app — it holds the keyboard's raw HID interface."))
            }
        }
        return conflicts
    }

    /// Browsers with a VIA tab also grab the device via WebHID; we can't see
    /// tabs, so this is advice rather than detection.
    static let viaWebAdvice = "If usevia.app is open in a browser tab, close that tab — WebHID takes exclusive access and the LEDs will not respond."
}

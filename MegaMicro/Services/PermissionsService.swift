import AppKit
import ApplicationServices
import IOKit.hid

/// Checks and requests the two TCC permissions MegaMicro needs:
/// - Accessibility: create a consuming CGEventTap + post keystrokes
/// - Input Monitoring: listen-only fallback monitor (and raw HID input later)
enum PermissionsService {
    static func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt (once per app signature) if not yet granted.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func inputMonitoringGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

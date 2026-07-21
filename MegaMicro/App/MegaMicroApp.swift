import AppKit
import SwiftUI

/// MegaMicro is a regular app (Dock icon, ⌘Tab) — the menu-bar-agent mode
/// caused window-activation pathologies where the config window rendered but
/// wouldn't take clicks. Closing the window keeps the app (and the RGB/webhook
/// engine) running; the Dock icon or menu-bar icon reopens it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showConfigWindow(sender)
        return false
    }

    func showConfigWindow(_ app: NSApplication) {
        if let window = app.windows.first(where: { $0.identifier?.rawValue.contains("config") == true }) {
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct MegaMicroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        // Window scene first so it presents at launch; the app still lives in
        // the menu bar (LSUIElement) once the window is closed.
        Window("MegaMicro", id: "config") {
            ConfigurationWindow()
                .environment(appState)
                .environment(appState.dashboard)
        }
        .defaultSize(width: 940, height: 640)
        .commands {
            CommandMenu("Demo") {
                Button(appState.demoModeEnabled ? "Stop Demo Mode" : "Start Demo Mode") {
                    appState.toggleDemoMode()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Next Agent Cast") { appState.nextDemoCast() }
                    .disabled(!appState.demoModeEnabled)
            }
            CommandMenu("View") {
                Menu("Appearance") {
                    Button("System") { appState.setAppearance("system") }
                    Button("Light") { appState.setAppearance("light") }
                    Button("Dark") { appState.setAppearance("dark") }
                }
                Divider()
                // ⌘1–⌘9 only: single-digit key equivalents.
                ForEach(Array(ConfigSection.allCases.prefix(9).enumerated()), id: \.element) { index, section in
                    Button(section.rawValue) {
                        appState.activeSection = section
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                ForEach(Array(ConfigSection.allCases.dropFirst(9)), id: \.self) { section in
                    Button(section.rawValue) {
                        appState.activeSection = section
                    }
                }
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .environment(appState.dashboard)
        } label: {
            Text("MM")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
        }
        .menuBarExtraStyle(.window)
    }
}

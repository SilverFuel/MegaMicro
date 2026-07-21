import SwiftUI

/// One-time first-run welcome: walks through the two things MegaMicro needs
/// to be useful — permissions and agent hooks — with live checkmarks.
struct OnboardingSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 52, height: 52)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to MegaMicro")
                        .font(.title2.bold())
                    Text("Two quick steps and your agents light up.")
                        .foregroundStyle(.secondary)
                }
            }

            step(number: 1,
                 done: appState.accessibilityGranted,
                 title: "Allow Accessibility",
                 detail: "Lets MegaMicro hear your macro keyboard's keys and send shortcuts to apps like Conductor. macOS will open System Settings — flip the MegaMicro switch on.") {
                Button(appState.accessibilityGranted ? "Granted" : "Grant Accessibility…") {
                    PermissionsService.requestAccessibility()
                    PermissionsService.openAccessibilitySettings()
                }
                .disabled(appState.accessibilityGranted)
            }

            step(number: 2,
                 done: appState.hooksInstalled,
                 title: "Connect your agents",
                 detail: "Installs safe, removable hooks so Claude Code sessions — including everything inside Conductor — report their status to your keyboard. Backed up first; uninstall anytime from the Hooks pane.") {
                HStack {
                    Button(appState.hooksInstalled ? "Claude Code Connected" : "Connect Claude Code") {
                        appState.installHooks()
                    }
                    .disabled(appState.hooksInstalled)
                    if appState.codexDetected {
                        Button(appState.codexHooksInstalled ? "Codex Connected" : "Connect Codex") {
                            appState.installCodexHooks()
                        }
                        .disabled(appState.codexHooksInstalled)
                    }
                }
            }

            step(number: 3,
                 done: appState.inputMonitoringGranted,
                 title: "Input Monitoring (optional for now)",
                 detail: "Only needed to drive the physical keyboard's lights. Skip until your Codex Micro arrives — everything else works without it.") {
                Button(appState.inputMonitoringGranted ? "Granted" : "Grant…") {
                    PermissionsService.requestInputMonitoring()
                }
                .disabled(appState.inputMonitoringGranted)
            }

            Divider()

            HStack {
                Text("Everything here lives in the Permissions and Hooks panes too.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(allDone ? "Let's Build" : "Set Up Later") {
                    finish()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            appState.refreshPermissions()
            appState.refreshHooksStatus()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                Task { @MainActor in
                    appState.refreshPermissions()
                    appState.refreshHooksStatus()
                }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private var allDone: Bool {
        appState.accessibilityGranted && appState.hooksInstalled
    }

    private func finish() {
        appState.config.onboardingComplete = true
        dismiss()
    }

    @ViewBuilder
    private func step(number: Int, done: Bool, title: String, detail: String,
                      @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.system(size: 22))
                .foregroundStyle(done ? .green : .secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                action()
            }
        }
    }
}

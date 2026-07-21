import SwiftUI

/// Hardware diagnostics: conflict warnings, the probe, and its report.
/// This is the first stop when the Codex Micro arrives.
struct DiagnosticsPane: View {
    @Environment(AppState.self) private var appState
    @State private var probing = false
    @State private var reportText = ""
    @State private var conflicts: [ConflictDetector.Conflict] = []

    var body: some View {
        Form {
            Section("Before connecting") {
                if conflicts.isEmpty {
                    Label("No conflicting apps detected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(conflicts, id: \.name) { conflict in
                        Label("\(conflict.name): \(conflict.advice)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                Text(ConflictDetector.viaWebAdvice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This is the first thing to run when your keyboard arrives.")
                        .font(.callout.weight(.semibold))
                    Text("""
                    Right now, everything you see in MegaMicro happens on the on-screen \
                    keyboard. To light up the real keys, the app has to talk to the physical \
                    keyboard over USB — and different keyboards speak different "languages." \
                    The probe plugs-and-asks: it detects the keyboard, checks whether it \
                    speaks the standard protocol MegaMicro already knows (the one used by \
                    most custom keyboards, including Work Louder's earlier models), and \
                    prints a short report.
                    """)
                    .font(.callout)
                    Text("""
                    • **Run Hardware Probe** — just looks and asks. Changes nothing.
                    • **Probe + Red Test Write** — same, then tries to turn the whole \
                    keyboard solid red for a moment. If you see red, the light pipeline \
                    works end-to-end and agent states will show on the real keys.
                    """)
                    .font(.callout)
                    Text("""
                    If the report says the keyboard doesn't answer, that's useful too — copy \
                    the report and we'll use it to figure out the keyboard's own protocol. \
                    Either way, nothing here can harm the keyboard.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                HStack {
                    Button(probing ? "Probing…" : "Run Hardware Probe") {
                        runProbe(testWrite: false)
                    }
                    .disabled(probing)
                    Button("Probe + Red Test Write") {
                        runProbe(testWrite: true)
                    }
                    .disabled(probing)
                    Spacer()
                    if !reportText.isEmpty {
                        Button("Copy Report") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(reportText, forType: .string)
                        }
                    }
                }

                HStack {
                    if appState.hardwareConnected {
                        Label("Live: \(appState.hardwareName ?? "keyboard")", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Disconnect") { appState.disconnectHardware() }
                    } else {
                        Button("Connect Keyboard (Go Live)") {
                            appState.connectHardware()
                        }
                        Text("Takes over the lights so agent states show on the real keys.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                if !reportText.isEmpty {
                    ScrollView {
                        Text(reportText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 180, maxHeight: 320)
                }
            } header: {
                Text("Hardware Probe")
            } footer: {
                Text("Connect the keyboard with its USB-C cable for this — the probe can't reach it over Bluetooth. Technical details, for the curious: it looks for the QMK/VIA raw HID interface (vendor id 0x574C, usage page 0xFF60) and runs the VIA protocol handshake.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .onAppear { conflicts = ConflictDetector.check() }
    }

    private func runProbe(testWrite: Bool) {
        probing = true
        conflicts = ConflictDetector.check()
        Task { @MainActor in
            let report = await ProbeService().run(testWrite: testWrite)
            reportText = report.text
            probing = false
            appState.log("hardware probe finished (raw interface: \(report.foundRawInterface ? "yes" : "no"))")
        }
    }
}

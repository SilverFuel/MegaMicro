import SwiftUI

/// Sheet for editing what one control gesture does in the active profile.
struct MappingEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let target: EditTarget

    private enum ActionType: String, CaseIterable, Identifiable {
        case keystroke = "Keystroke"
        case holdKeystroke = "Hold Keystroke (push-to-talk)"
        case openURL = "Open URL"
        case shell = "Shell Command"
        case typeText = "Type Text"
        case switchProfile = "Switch Profile"
        case cycleProfile = "Cycle Profiles"
        case none = "Nothing"
        var id: String { rawValue }
    }

    @State private var actionType: ActionType = .none
    @State private var keyCode: UInt16 = KeyCodes.n
    @State private var modifiers: Modifiers = []
    @State private var text = ""
    @State private var profileID = ""
    @State private var keyLabel = ""
    @State private var recording = false
    @State private var recordMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(target.control.rawValue) · \(target.gesture.rawValue)")
                .font(.title3.bold())

            Picker("Action", selection: $actionType) {
                ForEach(ActionType.allCases) { Text($0.rawValue).tag($0) }
            }

            switch actionType {
            case .keystroke, .holdKeystroke:
                if actionType == .holdKeystroke {
                    Text("The shortcut is held down for as long as the key is held — for push-to-talk dictation and similar hold-to-activate tools.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Text(recording
                         ? "Press the shortcut now…"
                         : KeyChord(keyCode: keyCode, modifiers: modifiers).display)
                        .font(.title3.monospaced())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(recording ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(recording ? Color.accentColor : Color.secondary.opacity(0.3)))
                    Button(recording ? "Cancel" : "Record…") { toggleRecording() }
                }
                HStack(spacing: 12) {
                    Toggle("🌐", isOn: modifierBinding(.fn))
                    Toggle("⌃", isOn: modifierBinding(.control))
                    Toggle("⌥", isOn: modifierBinding(.option))
                    Toggle("⇧", isOn: modifierBinding(.shift))
                    Toggle("⌘", isOn: modifierBinding(.command))
                }
                .toggleStyle(.button)
                .disabled(recording)
                Text("Click Record, then press the real shortcut on your keyboard. Toggles let you adjust modifiers afterwards (e.g. add 🌐).")
                    .font(.caption).foregroundStyle(.secondary)
            case .openURL:
                TextField("conductor://prompt=Fix%20the%20tests", text: $text)
                    .textFieldStyle(.roundedBorder)
            case .shell:
                TextField("pnpm test", text: $text)
                    .textFieldStyle(.roundedBorder)
            case .typeText:
                TextField("y⏎ (use \\r for return)", text: $text)
                    .textFieldStyle(.roundedBorder)
            case .switchProfile:
                Picker("Profile", selection: $profileID) {
                    ForEach(appState.config.profiles) { Text($0.name).tag($0.id) }
                }
            case .cycleProfile:
                Text("Advances to the next profile each press, wrapping around — the mode-switch key.")
                    .foregroundStyle(.secondary)
            case .none:
                Text("This control does nothing.").foregroundStyle(.secondary)
            }

            if target.gesture == .press, target.control.rawValue.hasPrefix("key.") {
                Divider()
                Text("Key glyph — match whatever physical keycap is on this key:")
                    .font(.callout)
                GlyphGrid(current: keyLabel.isEmpty ? nil : keyLabel) { selection in
                    keyLabel = selection ?? ""
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear(perform: loadCurrent)
        .onDisappear(perform: stopRecording)
    }

    // MARK: Shortcut recording

    private func toggleRecording() {
        recording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        recording = true
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            keyCode = event.keyCode
            modifiers = Modifiers(cgFlags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
            stopRecording()
            return nil   // swallow the recorded press
        }
    }

    private func stopRecording() {
        if let recordMonitor {
            NSEvent.removeMonitor(recordMonitor)
        }
        recordMonitor = nil
        recording = false
    }

    private func modifierBinding(_ flag: Modifiers) -> Binding<Bool> {
        Binding(
            get: { modifiers.contains(flag) },
            set: { on in if on { modifiers.insert(flag) } else { modifiers.remove(flag) } })
    }

    private func loadCurrent() {
        switch appState.action(for: target.control, gesture: target.gesture) {
        case .keystroke(let chord, _):
            actionType = .keystroke
            keyCode = chord.keyCode
            modifiers = chord.modifiers
        case .holdKeystroke(let chord, _):
            actionType = .holdKeystroke
            keyCode = chord.keyCode
            modifiers = chord.modifiers
        case .openURL(let url):
            actionType = .openURL; text = url
        case .shell(let command):
            actionType = .shell; text = command
        case .typeText(let value):
            actionType = .typeText
            text = value.replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\u{1B}", with: "\\e")
        case .switchProfile(let id):
            actionType = .switchProfile; profileID = id
        case .cycleProfile:
            actionType = .cycleProfile
        case .none:
            actionType = .none
        }
        if profileID.isEmpty { profileID = appState.config.profiles.first?.id ?? "" }
        keyLabel = appState.activeLayoutSettings.keyLegends[target.control] ?? ""
    }

    private func save() {
        let action: Action
        switch actionType {
        case .keystroke:
            action = .keystroke(chord: KeyChord(keyCode: keyCode, modifiers: modifiers), target: .frontmost)
        case .holdKeystroke:
            action = .holdKeystroke(chord: KeyChord(keyCode: keyCode, modifiers: modifiers), target: .frontmost)
        case .openURL:
            action = .openURL(text)
        case .shell:
            action = .shell(command: text)
        case .typeText:
            let unescaped = text
                .replacingOccurrences(of: "\\r", with: "\r")
                .replacingOccurrences(of: "\\e", with: "\u{1B}")
            action = .typeText(unescaped)
        case .switchProfile:
            action = .switchProfile(profileID)
        case .cycleProfile:
            action = .cycleProfile
        case .none:
            action = .none
        }
        appState.setAction(action, for: target.control, gesture: target.gesture)
        let trimmed = keyLabel.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            appState.activeLayoutSettings.keyLegends.removeValue(forKey: target.control)
        } else {
            appState.activeLayoutSettings.keyLegends[target.control] = trimmed
        }
    }
}

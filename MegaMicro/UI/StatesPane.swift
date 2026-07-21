import SwiftUI
import AppKit

/// Edit how each agent state renders — color, animation, speed — for the
/// active profile. The on-screen keyboard previews changes live; the inject
/// buttons fire a fake agent report so you can watch any state.
struct StatesPane: View {
    @Environment(AppState.self) private var appState

    private static let stateDescriptions: [AgentState: String] = [
        .idle: "Nothing happening on this key",
        .thinking: "Agent is reasoning about a prompt",
        .coding: "Agent is running tools / writing code",
        .waiting: "Agent needs your input or approval",
        .success: "Agent finished — fades out over time",
        .error: "Agent failed — stays lit until dismissed",
    ]

    var body: some View {
        Form {
            Section {
                Text("Agents report these states through hooks or the webhook; each key shows its agent's state. Colors and animations belong to the active profile (**\(appState.activeProfile.name)**), so every profile can have its own look.")
                    .font(.callout)
            }

            Section {
                ForEach(AgentState.allCases, id: \.self) { state in
                    stateRow(state)
                }
            } header: {
                Text("States")
            } footer: {
                HStack {
                    Text("Preview: watch the Keyboard pane, or inject a state here.")
                        .font(.caption)
                    Spacer()
                    Button("Reset Colors to Defaults") {
                        updateRules(RGBRules.standard)
                    }
                }
            }

            Section("Inject a test state") {
                HStack(spacing: 8) {
                    ForEach(AgentState.allCases, id: \.self) { state in
                        Button(state.wireName) {
                            appState.injectState(state)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color(hsv: appState.activeProfile.rgbRules.spec(for: state).color))
                    }
                }
                Text("Equivalent to an agent reporting that state — use it to preview lighting without running a real agent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Row

    @ViewBuilder
    private func stateRow(_ state: AgentState) -> some View {
        let spec = appState.activeProfile.rgbRules.spec(for: state)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.wireName).font(.headline)
                    Text(Self.stateDescriptions[state] ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ColorPicker("", selection: colorBinding(state), supportsOpacity: false)
                    .labelsHidden()
                effectPicker(state, spec: spec)
            }
            speedSlider(state, spec: spec)
        }
        .padding(.vertical, 2)
    }

    private func effectPicker(_ state: AgentState, spec: EffectSpec) -> some View {
        Picker("", selection: kindBinding(state)) {
            Text("Solid").tag(KindChoice.solid)
            Text("Breathing").tag(KindChoice.breathing)
            Text("Blink").tag(KindChoice.blink)
            Text("Strobe").tag(KindChoice.strobe)
            Text("Fade Out").tag(KindChoice.fadeOut)
        }
        .labelsHidden()
        .frame(width: 110)
    }

    @ViewBuilder
    private func speedSlider(_ state: AgentState, spec: EffectSpec) -> some View {
        switch spec.kind {
        case .solid:
            EmptyView()
        case .breathing(let period):
            labeledSlider("Breath cycle", value: period, range: 0.8...6, unit: "s", state: state) { .breathing(period: $0) }
        case .blink(let hz):
            labeledSlider("Blink rate", value: hz, range: 0.3...4, unit: "Hz", state: state) { .blink(hz: $0) }
        case .strobe(let hz):
            labeledSlider("Strobe rate", value: hz, range: 2...12, unit: "Hz", state: state) { .strobe(hz: $0) }
        case .fadeOut(let total):
            labeledSlider("Fade over", value: total, range: 5...120, unit: "s", state: state) { .fadeOut(total: $0) }
        }
    }

    private func labeledSlider(
        _ label: String, value: Double, range: ClosedRange<Double>, unit: String,
        state: AgentState, make: @escaping (Double) -> EffectSpec.Kind
    ) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Slider(value: Binding(
                get: { value },
                set: { newValue in updateSpec(state) { $0.kind = make(newValue) } }
            ), in: range)
            Text(String(format: "%.1f %@", value, unit))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 55, alignment: .trailing)
        }
    }

    // MARK: Bindings

    private enum KindChoice: Hashable { case solid, breathing, blink, strobe, fadeOut }

    private func kindBinding(_ state: AgentState) -> Binding<KindChoice> {
        Binding(
            get: {
                switch appState.activeProfile.rgbRules.spec(for: state).kind {
                case .solid: .solid
                case .breathing: .breathing
                case .blink: .blink
                case .strobe: .strobe
                case .fadeOut: .fadeOut
                }
            },
            set: { choice in
                updateSpec(state) { spec in
                    switch choice {
                    case .solid: spec.kind = .solid
                    case .breathing: spec.kind = .breathing(period: 2.8)
                    case .blink: spec.kind = .blink(hz: 1.2)
                    case .strobe: spec.kind = .strobe(hz: 5)
                    case .fadeOut: spec.kind = .fadeOut(total: 45)
                    }
                }
            })
    }

    private func colorBinding(_ state: AgentState) -> Binding<Color> {
        Binding(
            get: {
                Color(hsv: appState.activeProfile.rgbRules.spec(for: state).color)
            },
            set: { newColor in
                guard let rgb = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                // Preserve the configured brightness; the picker sets hue/sat.
                let previous = appState.activeProfile.rgbRules.spec(for: state).color
                var hsv = HSV(r: rgb.redComponent, g: rgb.greenComponent, b: rgb.blueComponent)
                hsv.v = previous.v
                updateSpec(state) { $0.color = hsv }
            })
    }

    private func updateSpec(_ state: AgentState, _ mutate: (inout EffectSpec) -> Void) {
        var rules = appState.activeProfile.rgbRules
        var spec = rules.spec(for: state)
        mutate(&spec)
        rules.rules[state] = spec
        updateRules(rules)
    }

    private func updateRules(_ rules: RGBRules) {
        guard let index = appState.config.profiles.firstIndex(where: { $0.id == appState.config.activeProfileID }) else { return }
        appState.config.profiles[index].rgbRules = rules
    }

}

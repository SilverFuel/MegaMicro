import SwiftUI

/// Dev/demo bar: inject agent states as if a Claude Code hook had fired,
/// exactly equivalent to a webhook POST.
struct SimulatorControls: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 8) {
            Text("Inject state:")
                .foregroundStyle(.secondary)
            ForEach(AgentState.allCases, id: \.self) { state in
                Button(state.wireName) {
                    appState.injectState(state)
                }
                .buttonStyle(.bordered)
                .tint(tint(for: state))
            }
        }
        .font(.callout)
    }

    private func tint(for state: AgentState) -> Color {
        Color(hsv: appState.activeProfile.rgbRules.spec(for: state).color)
    }
}

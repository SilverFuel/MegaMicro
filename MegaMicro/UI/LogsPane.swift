import SwiftUI
import AppKit

/// Full activity log: everything MegaMicro does and every agent report,
/// newest at the bottom. Also written to
/// ~/Library/Application Support/MegaMicro/activity.log.
struct LogsPane: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Logs").font(.title2.bold())
                    Text("Technical events used for troubleshooting connections, hooks, key presses, and lighting. For an everyday summary of agent work, use Dashboard.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.activityLog.joined(separator: "\n"), forType: .string)
                }
                Button("Clear") {
                    appState.activityLog.removeAll()
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if appState.activityLog.isEmpty {
                            Text("Nothing yet.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(appState.activityLog.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(8)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .onAppear { proxy.scrollTo("bottom") }
                .onChange(of: appState.activityLog.count) {
                    proxy.scrollTo("bottom")
                }
            }

            Text("The full log is also on disk: ~/Library/Application Support/MegaMicro/activity.log")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }
}

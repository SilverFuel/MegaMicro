import SwiftUI

struct WatchRootView: View {
    @Bindable var model: WatchModel

    var body: some View {
        if model.hasData {
            TabView {
                BoardPage()
                FeedPage()
            }
            .tabViewStyle(.verticalPage)
        } else {
            VStack(spacing: 8) {
                ProgressView()
                Text("Open MegaMicro on your iPhone")
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

/// Page 1 — the device board, filling the square watch face.
struct BoardPage: View {
    var body: some View {
        KeyboardView()
            .environment(\.agentBoardMode, true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Page 2 (swipe) — the activity feed.
struct FeedPage: View {
    @Environment(DashboardModel.self) private var dashboard

    var body: some View {
        List {
            HStack(spacing: 8) {
                Circle().fill(stateColor(dashboard.fleetNotification.state))
                    .frame(width: 9, height: 9)
                Text(dashboard.fleetNotification.headline).font(.caption).lineLimit(2)
            }
            ForEach(dashboard.activityFeed.prefix(20)) { item in
                HStack(spacing: 8) {
                    SourceIcon(source: item.source, size: 15).frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.agentName + " " + item.message)
                            .font(.caption2).lineLimit(2)
                        if let project = item.project {
                            Text(project).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Circle().fill(stateColor(item.state)).frame(width: 6, height: 6)
                }
            }
            if dashboard.activityFeed.isEmpty {
                Text("No activity yet").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func stateColor(_ state: AgentState) -> Color {
        let c = dashboard.rgbRules.spec(for: state).color
        return Color(hsv: HSV(h: c.h, s: c.s, v: 255))
    }
}

import SwiftUI
import WatchConnectivity

@main
struct MegaMicroWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model)
                .environment(model.dashboard)
                .onAppear { model.activate() }
        }
    }
}

/// Receives dashboard snapshots relayed from the paired iPhone and re-derives
/// the LED animation locally. The Watch is a pure monitor.
@Observable @MainActor
final class WatchModel: NSObject, WCSessionDelegate {
    let dashboard = DashboardModel()
    var hasData = false
    private let decoder = JSONDecoder()

    func activate() {
        dashboard.startClientRendering()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    fileprivate func apply(_ context: [String: Any]) {
        guard let data = context["snapshot"] as? Data,
              let snapshot = try? decoder.decode(DashboardSnapshot.self, from: data) else { return }
        dashboard.apply(snapshot)
        hasData = true
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        // Apply whatever the phone last pushed while the Watch app was closed…
        let context = session.receivedApplicationContext
        Task { @MainActor in self.apply(context) }
        // …and proactively ask the phone for the current snapshot.
        requestSnapshot(session)
    }

    private nonisolated func requestSnapshot(_ session: WCSession) {
        guard session.isReachable else { return }
        session.sendMessage(["request": "snapshot"], replyHandler: { reply in
            Task { @MainActor in self.apply(reply) }
        }, errorHandler: nil)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.apply(message) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        requestSnapshot(session)
    }
}

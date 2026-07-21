import Foundation
import WatchConnectivity

/// Relays the latest dashboard snapshot from the iPhone to a paired Apple Watch.
/// The Watch can't reach the Mac directly, so the phone forwards state it
/// already receives over the LAN. Throttled — the Watch is a glance, not a
/// frame-rate mirror.
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    private var lastSent = Date.distantPast
    private let minInterval: TimeInterval = 1.0
    private var latest: Data?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Forward an encoded `DashboardSnapshot`. When the Watch is reachable we
    /// push live via `sendMessage`; otherwise `updateApplicationContext` leaves
    /// the latest state for it to wake to. Also cached so we can answer a
    /// Watch's explicit request immediately.
    func send(snapshotJSON: Data) {
        latest = snapshotJSON
        let now = Date()
        guard now.timeIntervalSince(lastSent) >= minInterval else { return }
        guard WCSession.default.activationState == .activated else { return }
        lastSent = now
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(["snapshot": snapshotJSON], replyHandler: nil, errorHandler: nil)
        }
        try? session.updateApplicationContext(["snapshot": snapshotJSON])
    }

    // WCSessionDelegate (iOS requires these)
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    /// The Watch asks for the current snapshot on launch; reply with the latest.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            replyHandler(self.latest.map { ["snapshot": $0] } ?? [:])
        }
    }
}

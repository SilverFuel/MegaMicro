import Foundation
import UserNotifications

/// Opt-in native alerts for the few agent transitions that are useful away
/// from the keyboard. State filtering lives here so callers cannot
/// accidentally turn routine thinking/coding updates into notification spam.
final class MacNotificationService {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func post(for session: AgentSession, project: String?) {
        let title: String
        switch session.state {
        case .waiting: title = "Agent needs your input"
        case .error: title = "Agent encountered an error"
        case .success: title = "Agent finished"
        default: return
        }

        let provider = session.agent ?? readableProvider(session.source)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = [provider, project].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
        content.sound = .default
        content.userInfo = ["source": session.source, "session": session.session]

        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "agent.\(session.source).\(session.session).\(session.state.wireName).\(UUID().uuidString)",
            content: content,
            trigger: nil))
    }

    private func readableProvider(_ source: String) -> String {
        source.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

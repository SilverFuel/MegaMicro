import Foundation

/// Human-readable summary of the fleet's most urgent state — the "Activity"
/// card. Shared across platforms so a synced client can render it directly.
struct FleetNotification: Equatable, Sendable, Codable {
    let state: AgentState
    let headline: String
    let detail: String
    let keySlot: Int?
}

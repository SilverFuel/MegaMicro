import Foundation

/// Wire protocol shared by the macOS sync server and the iOS/watchOS clients.
/// Everything here is `Codable` + `Sendable` so a snapshot round-trips over the
/// LAN WebSocket and a client can render/re-derive the dashboard locally.

/// The full dashboard state a client needs to render the board, tooltips, and
/// activity feed. The LED animation is NOT streamed — the client re-derives it
/// from `sessions` + `rgbRules`/`underglow` via `AnimationRenderer`, so this is
/// pushed only when state changes, not at frame rate.
struct DashboardSnapshot: Codable, Sendable {
    var deviceName: String
    var workspacesRoot: String
    var layoutId: String
    var ledCount: Int

    var sessions: [AgentSession]
    var keyBindings: [Int: KeyAgentBinding]
    var keyLegends: [ControlID: String]
    var workspaces: [ConductorWorkspace]
    var conductorAgents: [String: ConductorAgentInfo]
    var cwdBranches: [String: String]
    var activityFeed: [ActivityFeedItem]
    var fleetNotification: FleetNotification

    var rgbRules: RGBRules
    var underglow: UnderglowMode
    /// Solid-color mode (no pulsing/flashing), mirrored from the Mac. Additive
    /// and one-directional (Mac→client), so existing clients that predate it
    /// simply ignore the extra key.
    var steadyGlow: Bool = false
}

/// A reassign/monitor action a client sends back to the Mac. Mirrors the
/// string-payload command surface already on `AppState`
/// (`handleAgentDrop`/`unassignKey`/`unassignAllKeys`/`dismissAgent`/`focusAgent`).
enum SyncCommand: Codable, Sendable {
    /// `payload` is the existing drop protocol: "auto" | "off" | "workspace:<id>"
    /// | "path:<dir>" | "session:<key>" | "move:<slot>". `control` is a
    /// `ControlID.rawValue`, e.g. "key.3".
    case drop(payload: String, control: String)
    case unassign(slot: Int)
    case unassignAll
    /// `payload` is "workspace:<id>" or "session:<key>".
    case dismiss(payload: String)
    case focus(slot: Int)
}

/// Client → server envelope. First message after connect must be `.hello` with
/// the pairing token; the server ignores commands until the token validates.
enum ClientMessage: Codable, Sendable {
    case hello(SyncHello)
    case command(SyncCommand)
}

/// Server → client envelope.
enum ServerMessage: Codable, Sendable {
    case snapshot(DashboardSnapshot)
    case rejected(reason: String)
    /// Sent once when a client authenticates with the ephemeral pairing code:
    /// hands back the long-lived token for the client to store and reuse.
    case paired(token: String)
}

struct SyncHello: Codable, Sendable {
    /// Either the 6-digit pairing code (first pairing) or the stored long-lived
    /// token (subsequent connects).
    var secret: String
    var clientName: String
}

/// Everything a phone needs to reach and authenticate with one Mac. The Mac
/// shows this (minus nothing) as a QR code during pairing; the discoverable
/// parts (everything except `token`) also ride in the Bonjour TXT record.
struct PairingInfo: Codable, Sendable {
    var instanceID: String
    var deviceName: String
    var host: String
    var port: Int
    var token: String
}

enum SyncBonjour {
    /// Bonjour service type MegaMicro advertises / browses for.
    static let serviceType = "_megamicro._tcp"
    /// TXT-record keys.
    static let txtInstanceID = "id"
    static let txtDeviceName = "name"
}

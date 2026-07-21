import XCTest
@testable import MegaMicro

final class SyncProtocolTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testCommandRoundTrips() throws {
        let commands: [SyncCommand] = [
            .drop(payload: "session:codex#abc", control: "key.3"),
            .unassign(slot: 2),
            .unassignAll,
            .dismiss(payload: "workspace:PeopleSmarts/kabul"),
            .focus(slot: 5),
        ]
        for command in commands {
            let data = try encoder.encode(ClientMessage.command(command))
            let decoded = try decoder.decode(ClientMessage.self, from: data)
            guard case .command(let round) = decoded else {
                return XCTFail("expected .command, got \(decoded)")
            }
            XCTAssertEqual(String(describing: round), String(describing: command))
        }
    }

    func testHelloRoundTrips() throws {
        let data = try encoder.encode(ClientMessage.hello(SyncHello(secret: "123456", clientName: "Jesse's iPhone")))
        guard case .hello(let hello) = try decoder.decode(ClientMessage.self, from: data) else {
            return XCTFail("expected .hello")
        }
        XCTAssertEqual(hello.secret, "123456")
        XCTAssertEqual(hello.clientName, "Jesse's iPhone")
    }

    func testSnapshotRoundTrips() throws {
        let profile = DefaultProfiles.conductor
        let session = AgentSession(source: "codex", session: "abc", cwd: "/tmp/x",
                                   state: .coding, updatedAt: Date(timeIntervalSince1970: 1_000_000),
                                   terminalSession: "42", terminalKind: "wezterm",
                                   terminalEndpoint: "/tmp/wez.sock")
        let snapshot = DashboardSnapshot(
            deviceName: "Jesse's MegaMicro",
            workspacesRoot: "/Users/j/conductor/workspaces",
            layoutId: CodexMicroLayout.layout.id,
            ledCount: CodexMicroLayout.layout.ledCount,
            sessions: [session],
            keyBindings: [3: .path("/tmp/x"), 4: .off],
            keyLegends: [:],
            workspaces: [ConductorWorkspace(project: "P", name: "kabul", path: "/p/kabul",
                                            displayName: "add-auth")],
            conductorAgents: ["kabul": ConductorAgentInfo(agentType: "codex", model: "gpt-5.5")],
            cwdBranches: ["/tmp/x": "main"],
            activityFeed: [ActivityFeedItem(
                at: Date(timeIntervalSince1970: 1_000_000), category: .working, state: .coding,
                source: "codex", agentName: "Codex", project: "add-auth", keySlot: 3,
                message: "started working", simulated: false)],
            fleetNotification: FleetNotification(state: .coding, headline: "add-auth · Codex — working",
                                                 detail: "Actively using tools · Key 4", keySlot: 3),
            rgbRules: profile.rgbRules,
            underglow: profile.underglow)

        let data = try encoder.encode(snapshot)
        let round = try decoder.decode(DashboardSnapshot.self, from: data)
        XCTAssertEqual(round.deviceName, "Jesse's MegaMicro")
        XCTAssertEqual(round.sessions.first?.state, .coding)
        XCTAssertEqual(round.sessions.first?.terminalSession, "42")
        XCTAssertEqual(round.sessions.first?.terminalKind, "wezterm")
        XCTAssertEqual(round.sessions.first?.terminalEndpoint, "/tmp/wez.sock")
        XCTAssertEqual(round.keyBindings[3], .path("/tmp/x"))
        XCTAssertEqual(round.keyBindings[4], .off)
        XCTAssertEqual(round.workspaces.first?.displayName, "add-auth")
        XCTAssertEqual(round.conductorAgents["kabul"]?.agentType, "codex")
        XCTAssertEqual(round.activityFeed.first?.message, "started working")
        XCTAssertEqual(round.fleetNotification.keySlot, 3)
    }
}

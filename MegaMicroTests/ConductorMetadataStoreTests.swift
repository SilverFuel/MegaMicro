import XCTest
@testable import MegaMicro

final class ConductorMetadataStoreTests: XCTestCase {
    private let sep = "\u{1f}"

    func testParseKeysByPathAndDirectoryName() {
        let text = [
            "/Users/j/conductor/workspaces/Proj/kabul\(sep)kabul\(sep)codex\(sep)gpt-5.5",
            "\(sep)buffalo\(sep)claude\(sep)",  // older row: no workspace_path, no model
        ].joined(separator: "\n")

        let map = ConductorMetadataStore.parse(text)

        // Keyed by both the full path and the directory name.
        XCTAssertEqual(map["/Users/j/conductor/workspaces/Proj/kabul"],
                       ConductorAgentInfo(agentType: "codex", model: "gpt-5.5"))
        XCTAssertEqual(map["kabul"], ConductorAgentInfo(agentType: "codex", model: "gpt-5.5"))
        // Missing path/model handled: keyed only by directory name, nil model.
        XCTAssertEqual(map["buffalo"], ConductorAgentInfo(agentType: "claude", model: nil))
    }

    func testParseSkipsRowsWithoutAgentType() {
        let text = "/p\(sep)dir\(sep)\(sep)gpt-5.5"  // empty agent_type
        XCTAssertTrue(ConductorMetadataStore.parse(text).isEmpty)
    }

    func testParseIgnoresMalformedLines() {
        let text = "only\(sep)three\(sep)fields\nvalid\(sep)dir\(sep)codex\(sep)m"
        let map = ConductorMetadataStore.parse(text)
        XCTAssertEqual(map.count, 2)  // path "valid" + dir "dir", both → codex
        XCTAssertEqual(map["dir"]?.agentType, "codex")
    }
}

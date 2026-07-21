import XCTest
@testable import MegaMicro

final class LayoutImporterTests: XCTestCase {
    func testVIADefinitionWithGapsAndWideKeys() throws {
        let via = """
        {
          "name": "Test Pad",
          "vendorId": "0x574C",
          "layouts": {
            "keymap": [
              ["0,0", {"x": 0.5}, "0,1", {"w": 2}, "0,2"],
              [{"y": 0.25}, "1,0", "1,1"]
            ]
          }
        }
        """
        let layout = try LayoutImporter.parse(data: Data(via.utf8), fallbackName: "fallback")
        XCTAssertEqual(layout.name, "Test Pad")
        XCTAssertEqual(layout.id, "custom-test-pad")
        let keys = layout.controls
        XCTAssertEqual(keys.count, 5)
        // Row 0: key at 0, gap 0.5 → key at 1.5, wide key (w2) at 2.5
        XCTAssertEqual(keys[0].frame, GridRect(x: 0, y: 0, w: 1, h: 1))
        XCTAssertEqual(keys[1].frame, GridRect(x: 1.5, y: 0, w: 1, h: 1))
        XCTAssertEqual(keys[2].frame, GridRect(x: 2.5, y: 0, w: 2, h: 1))
        // Row 1 pushed down 0.25 extra
        XCTAssertEqual(keys[3].frame, GridRect(x: 0, y: 1.25, w: 1, h: 1))
        XCTAssertEqual(keys[4].frame, GridRect(x: 1, y: 1.25, w: 1, h: 1))
        // Extents
        XCTAssertEqual(layout.columns, 4.5)
        XCTAssertEqual(layout.rows, 2.25)
        // Sequential provisional LED indices
        XCTAssertEqual(keys.compactMap(\.ledIndex), [0, 1, 2, 3, 4])
    }

    func testBareKLEArrayWithMetadataAndDecal() throws {
        let kle = """
        [
          {"name": "ignored metadata block"},
          ["A", {"d": true}, "decal", "B"]
        ]
        """
        let layout = try LayoutImporter.parse(data: Data(kle.utf8), fallbackName: "My Pad")
        XCTAssertEqual(layout.name, "My Pad")
        XCTAssertEqual(layout.controls.count, 2, "decals are not keys")
        // Decal still advances the cursor.
        XCTAssertEqual(layout.controls[1].frame.x, 2)
    }

    func testUnrecognizedFormatThrows() {
        XCTAssertThrowsError(try LayoutImporter.parse(data: Data(#"{"foo": 1}"#.utf8), fallbackName: "x"))
        XCTAssertThrowsError(try LayoutImporter.parse(data: Data("[]".utf8), fallbackName: "x"))
    }

    func testMigrationV5MovesBindingsIntoLayoutSettings() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("megamicro-v5-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(fileURL: dir.appendingPathComponent("config.json"))

        var old = AppConfig()
        old.version = 4
        old.keyBindings = [2: .workspace("p/w")]
        old.keyLegends = [.key(0): "⚡"]
        old.layoutSettings = [:]
        try store.save(old)

        let migrated = store.load()
        XCTAssertEqual(migrated.layoutSettings["codex-micro"]?.keyBindings[2], .workspace("p/w"))
        XCTAssertEqual(migrated.layoutSettings["codex-micro"]?.keyLegends[.key(0)], "⚡")
        XCTAssertTrue(migrated.keyBindings.isEmpty)
        XCTAssertEqual(migrated.activeLayoutID, "codex-micro")
    }
}

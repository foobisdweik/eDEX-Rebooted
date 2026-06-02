import XCTest
@testable import SettingsEditorSupport

final class NativeSettingsEditorTests: XCTestCase {
    func testEmptyInitExposesDefaultsAndNoRawKeys() {
        let doc = EdexSettingsDocument()
        XCTAssertTrue(doc.raw.isEmpty)
        XCTAssertEqual(doc.int(.clockHours), 24)
        XCTAssertEqual(doc.string(.theme), "tron")
    }

    func testInitThrowsWhenTopLevelIsNotObject() {
        XCTAssertThrowsError(try EdexSettingsDocument(jsonString: "[1,2,3]"))
        XCTAssertThrowsError(try EdexSettingsDocument(jsonString: "42"))
    }

    func testIntAccessorRejectsOutOfRangeValueWithoutCrashing() throws {
        // 2^63 is finite but exceeds Int.max; the cast must not trap.
        let doc = try EdexSettingsDocument(jsonString: #"{"monitor":9223372036854775808}"#)
        XCTAssertNil(doc.int(.monitor))
    }

    func testParsesScalarSettings() throws {
        let doc = try EdexSettingsDocument(
            jsonString: #"{"shell":"/bin/zsh","termFontSize":15,"audio":true,"audioVolume":0.8}"#)
        XCTAssertEqual(doc.string(.shell), "/bin/zsh")
        XCTAssertEqual(doc.int(.termFontSize), 15)
        XCTAssertEqual(doc.bool(.audio), true)
        XCTAssertEqual(doc.double(.audioVolume), 0.8)
    }

    func testAppliesDefaultsForMissingKeys() throws {
        let doc = try EdexSettingsDocument(jsonString: "{}")
        XCTAssertEqual(doc.int(.clockHours), 24)
        XCTAssertEqual(doc.double(.audioVolume), 1.0)
        XCTAssertEqual(doc.bool(.keepGeometry), true)
        XCTAssertEqual(doc.int(.termFontSize), 15)
        XCTAssertEqual(doc.string(.theme), "tron")
        XCTAssertEqual(doc.string(.keyboard), "en-US")
    }

    func testPreservesUnknownKeysOnSerialize() throws {
        var doc = try EdexSettingsDocument(
            jsonString: #"{"theme":"tron","forceFullscreen":true,"port":3000,"experimentalFeatures":false}"#)
        doc.setString("nord", for: .theme)
        let reparsed = try EdexSettingsDocument(jsonString: try doc.jsonString())
        XCTAssertEqual(reparsed.string(.theme), "nord")
        XCTAssertEqual(reparsed.raw["forceFullscreen"], .bool(true))
        XCTAssertEqual(reparsed.raw["port"], .number(3000))
        XCTAssertEqual(reparsed.raw["experimentalFeatures"], .bool(false))
    }

    func testAudioVolumeClampsToUnitRange() throws {
        var doc = try EdexSettingsDocument(jsonString: "{}")
        doc.setDouble(1.7, for: .audioVolume)
        XCTAssertEqual(doc.double(.audioVolume), 1.0)
        doc.setDouble(-0.5, for: .audioVolume)
        XCTAssertEqual(doc.double(.audioVolume), 0.0)
    }

    func testTermFontSizeClampsToMinimum() throws {
        var doc = try EdexSettingsDocument(jsonString: "{}")
        doc.setInt(0, for: .termFontSize)
        XCTAssertEqual(doc.int(.termFontSize), 1)
    }

    func testClockHoursNormalizesToTwelveOrTwentyFour() throws {
        var doc = try EdexSettingsDocument(jsonString: "{}")
        doc.setInt(13, for: .clockHours)
        XCTAssertEqual(doc.int(.clockHours), 24)
        doc.setInt(12, for: .clockHours)
        XCTAssertEqual(doc.int(.clockHours), 12)
    }

    func testRestartRequiredKeysDetectsRebootChanges() throws {
        let old = try EdexSettingsDocument(jsonString: #"{"theme":"tron","hideDotfiles":false}"#)
        var updated = old
        updated.setString("nord", for: .theme)
        updated.setBool(true, for: .hideDotfiles)
        XCTAssertEqual(EdexSettingsDocument.restartRequiredKeys(from: old, to: updated), ["theme"])
    }

    func testNoRestartForRuntimeOnlyChange() throws {
        let old = try EdexSettingsDocument(jsonString: #"{"hideDotfiles":false}"#)
        var updated = old
        updated.setBool(true, for: .hideDotfiles)
        XCTAssertTrue(EdexSettingsDocument.restartRequiredKeys(from: old, to: updated).isEmpty)
    }

    func testFieldSchemaListsAllEditableSettings() {
        let keys = Set(EdexSettingsField.all.map { $0.key })
        XCTAssertEqual(keys, Set(EdexSettingsKey.allCases))
    }

    func testBooleanFieldsUseToggleControl() {
        let audio = EdexSettingsField.all.first { $0.key == .audio }
        XCTAssertEqual(audio?.control, .toggle)
    }

    func testClockHoursFieldOffersTwelveAndTwentyFour() {
        let field = EdexSettingsField.all.first { $0.key == .clockHours }
        XCTAssertEqual(field?.control, .choice(["24", "12"]))
    }
}

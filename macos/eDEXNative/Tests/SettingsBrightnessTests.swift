import XCTest
@testable import EdexDomainSupport

/// Coverage for the Spike-A brightness settings keys at the layers the test target
/// can actually reach:
///   1. The JSON *decode shape* the app's `SettingsFile` relies on — exercised
///      through a local `Decodable` mirror (the real `SettingsFile`/`SettingsSummary`
///      live in the eDEXNative executable target, which tests can't import).
///   2. Survival of the keys through the real settings-editor round-trip
///      (`EdexSettingsDocument` parse → edit → serialize → reparse).
///
/// The *canonical default values* (203 / 1600 / 0 / "liquid-retina-xdr-16") are
/// asserted where they actually live — the Rust `default_settings()` test
/// (`default_settings_includes_brightness_keys`) — not here.
final class SettingsBrightnessTests: XCTestCase {

    // MARK: - Local mirror of the SettingsFile decode shape

    private struct BrightnessFields: Decodable {
        var brightnessProfileID: String?
        var paperWhiteNits: Double?
        var peakNits: Double?
        var luminanceFloorNits: Double?
    }

    // MARK: - Decode shape

    func testMissingBrightnessKeysDecodeAsNil() throws {
        // Absent keys decode to nil so the app layer can apply its fallbacks; this
        // is the only default-related behavior observable from the test target.
        let decoded = try JSONDecoder().decode(BrightnessFields.self, from: Data("{}".utf8))
        XCTAssertNil(decoded.brightnessProfileID)
        XCTAssertNil(decoded.paperWhiteNits)
        XCTAssertNil(decoded.peakNits)
        XCTAssertNil(decoded.luminanceFloorNits)
    }

    func testParsesAllFourBrightnessKeys() throws {
        let json = """
        {
            "brightnessProfileID": "liquid-retina-xdr-16",
            "paperWhiteNits": 203,
            "peakNits": 1600,
            "luminanceFloorNits": 0
        }
        """
        let decoded = try JSONDecoder().decode(BrightnessFields.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.brightnessProfileID, "liquid-retina-xdr-16")
        XCTAssertEqual(decoded.paperWhiteNits, 203)
        XCTAssertEqual(decoded.peakNits, 1600)
        XCTAssertEqual(decoded.luminanceFloorNits, 0)
    }

    func testParsesNonDefaultValues() throws {
        // Uses a real preset id (generic-sdr) so the fixture stays aligned with the
        // BrightnessProfile preset catalog.
        let json = """
        {
            "brightnessProfileID": "generic-sdr",
            "paperWhiteNits": 100,
            "peakNits": 400,
            "luminanceFloorNits": 0.005
        }
        """
        let decoded = try JSONDecoder().decode(BrightnessFields.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.brightnessProfileID, "generic-sdr")
        XCTAssertEqual(decoded.paperWhiteNits ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(decoded.peakNits ?? 0, 400, accuracy: 0.001)
        XCTAssertEqual(decoded.luminanceFloorNits ?? 0, 0.005, accuracy: 0.0001)
    }

    // MARK: - Editor round-trip (the app's real parse → edit → serialize path)

    /// The brightness keys are free-form (not editor-surfaced), so they must survive
    /// a real `EdexSettingsDocument` edit + reserialize alongside unrelated unknown
    /// keys — mirrors `NativeSettingsEditorTests.testPreservesUnknownKeysOnSerialize`.
    func testEditorRoundTripPreservesBrightnessAndUnknownKeys() throws {
        let json = """
        {
            "brightnessProfileID": "liquid-retina-xdr-16",
            "paperWhiteNits": 203,
            "peakNits": 1600,
            "luminanceFloorNits": 0,
            "theme": "tron",
            "unknownFutureKey": 42
        }
        """
        var doc = try EdexSettingsDocument(jsonString: json)
        // A real editor edit of a surfaced key, to drive the actual edit path.
        doc.setBool(true, for: .reducedMotion)
        let reparsed = try EdexSettingsDocument(jsonString: try doc.jsonString())

        XCTAssertEqual(reparsed.raw["brightnessProfileID"], .string("liquid-retina-xdr-16"))
        XCTAssertEqual(reparsed.raw["paperWhiteNits"], .number(203))
        XCTAssertEqual(reparsed.raw["peakNits"], .number(1600))
        XCTAssertEqual(reparsed.raw["luminanceFloorNits"], .number(0))
        // Unrelated known + unknown keys survive the round-trip.
        XCTAssertEqual(reparsed.raw["theme"], .string("tron"))
        XCTAssertEqual(reparsed.raw["unknownFutureKey"], .number(42))
        // The edit was applied.
        XCTAssertEqual(reparsed.raw["reducedMotion"], .bool(true))
    }
}

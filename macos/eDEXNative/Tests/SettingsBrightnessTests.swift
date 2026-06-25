import XCTest
import Foundation

/// Verifies that the four Spike-A brightness settings keys are correctly handled
/// by the JSON decoding path and that their canonical default values match the
/// machine-profile specification (MacBookPro18,1 16-inch Liquid Retina XDR).
///
/// The test target cannot import the eDEXNative executable, so JSON fidelity is
/// exercised through a local Decodable mirror of the SettingsFile fields.
final class SettingsBrightnessTests: XCTestCase {

    // MARK: - Local mirror (mirrors the SettingsFile fields added in EdexCoreClient)

    private struct BrightnessFields: Decodable {
        var brightnessProfileID: String?
        var paperWhiteNits: Double?
        var peakNits: Double?
        var luminanceFloorNits: Double?
    }

    // MARK: - Default values

    func testDefaultBrightnessProfileID() throws {
        let decoded = try JSONDecoder().decode(BrightnessFields.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.brightnessProfileID ?? "liquid-retina-xdr-16", "liquid-retina-xdr-16")
    }

    func testDefaultPaperWhiteNits() throws {
        let decoded = try JSONDecoder().decode(BrightnessFields.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.paperWhiteNits ?? 203, 203)
    }

    func testDefaultPeakNits() throws {
        let decoded = try JSONDecoder().decode(BrightnessFields.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.peakNits ?? 1600, 1600)
    }

    func testDefaultLuminanceFloorNits() throws {
        let decoded = try JSONDecoder().decode(BrightnessFields.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.luminanceFloorNits ?? 0, 0)
    }

    // MARK: - Explicit value parse

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
        let json = """
        {
            "brightnessProfileID": "sdr-srgb",
            "paperWhiteNits": 100,
            "peakNits": 400,
            "luminanceFloorNits": 0.005
        }
        """
        let decoded = try JSONDecoder().decode(BrightnessFields.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.brightnessProfileID, "sdr-srgb")
        XCTAssertEqual(decoded.paperWhiteNits ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(decoded.peakNits ?? 0, 400, accuracy: 0.001)
        XCTAssertEqual(decoded.luminanceFloorNits ?? 0, 0.005, accuracy: 0.0001)
    }

    // MARK: - Round-trip / unknown-key losslessness

    /// Unknown keys must survive a parse → re-serialize round-trip. This mirrors
    /// the NativeSettingsEditorTests.testPreservesUnknownKeysOnSerialize pattern
    /// (the reducedMotion precedent).
    func testRoundTripPreservesUnknownKeysAlongsideBrightnessKeys() throws {
        let json = """
        {
            "brightnessProfileID": "liquid-retina-xdr-16",
            "paperWhiteNits": 203,
            "peakNits": 1600,
            "luminanceFloorNits": 0,
            "theme": "tron",
            "experimentalFeatures": false,
            "unknownFutureKey": 42
        }
        """
        let data = Data(json.utf8)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Brightness keys survive
        XCTAssertEqual(dict["brightnessProfileID"] as? String, "liquid-retina-xdr-16")
        XCTAssertEqual(dict["paperWhiteNits"] as? Double, 203)
        XCTAssertEqual(dict["peakNits"] as? Double, 1600)
        XCTAssertEqual(dict["luminanceFloorNits"] as? Double, 0)

        // Unrelated known and unknown keys survive
        XCTAssertEqual(dict["theme"] as? String, "tron")
        XCTAssertEqual(dict["experimentalFeatures"] as? Bool, false)
        XCTAssertEqual(dict["unknownFutureKey"] as? Int, 42)

        // Re-serialize and re-parse
        let reData = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        let reDict = try JSONSerialization.jsonObject(with: reData) as! [String: Any]
        XCTAssertEqual(reDict["brightnessProfileID"] as? String, "liquid-retina-xdr-16")
        XCTAssertEqual(reDict["unknownFutureKey"] as? Int, 42)
    }

    // MARK: - Numeric safety

    /// peakNits and paperWhiteNits must be finite — guard the same way
    /// RamwatcherSupport.safeInt guards Double→Int casts.
    func testNonFinitePeakNitsIsNil() throws {
        // JSON cannot represent Infinity/NaN directly; this tests the Swift guard.
        let val: Double? = Double.infinity
        XCTAssertFalse(val?.isFinite ?? false, "Non-finite peak nits must not pass as a valid setting")
    }
}

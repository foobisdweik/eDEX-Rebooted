import XCTest
@testable import AudioSupport

final class NativeAudioTests: XCTestCase {
    func testCueCatalogMatchesLegacyAudioManager() {
        XCTAssertEqual(
            EdexAudioCue.allCases.map(\.rawValue),
            [
                "stdout",
                "stdin",
                "folder",
                "granted",
                "keyboard",
                "theme",
                "expand",
                "panels",
                "scan",
                "denied",
                "info",
                "alarm",
                "error"
            ]
        )
    }

    func testCueAssetNamesAreDocumentRelativeWavNames() {
        XCTAssertEqual(EdexAudioCue.stdout.assetName, "stdout.wav")
        XCTAssertEqual(EdexAudioCue.keyboard.assetName, "keyboard.wav")
        XCTAssertEqual(EdexAudioCue.error.assetName, "error.wav")
    }

    func testFeedbackCueGatingMatchesLegacySettings() {
        let enabled = EdexAudioCatalog(settings: EdexAudioSettings(audio: true, audioVolume: 1.0, disableFeedbackAudio: false))
        XCTAssertTrue(enabled.shouldLoad(.stdout))
        XCTAssertTrue(enabled.shouldLoad(.folder))
        XCTAssertTrue(enabled.shouldLoad(.keyboard))

        let feedbackDisabled = EdexAudioCatalog(settings: EdexAudioSettings(audio: true, audioVolume: 1.0, disableFeedbackAudio: true))
        XCTAssertFalse(feedbackDisabled.shouldLoad(.stdout))
        XCTAssertFalse(feedbackDisabled.shouldLoad(.stdin))
        XCTAssertFalse(feedbackDisabled.shouldLoad(.folder))
        XCTAssertFalse(feedbackDisabled.shouldLoad(.granted))
        XCTAssertTrue(feedbackDisabled.shouldLoad(.keyboard))
    }

    func testDisabledAudioLoadsNoCuesAndMutesPlayback() {
        let catalog = EdexAudioCatalog(settings: EdexAudioSettings(audio: false, audioVolume: 1.0, disableFeedbackAudio: false))
        XCTAssertFalse(catalog.shouldLoad(.keyboard))
        XCTAssertEqual(catalog.effectiveVolume(for: .keyboard), 0.0)
    }

    func testStdoutAndStdinUseLegacyPointFourGain() {
        let catalog = EdexAudioCatalog(settings: EdexAudioSettings(audio: true, audioVolume: 0.5, disableFeedbackAudio: false))
        XCTAssertEqual(catalog.effectiveVolume(for: .stdout), 0.2, accuracy: 0.0001)
        XCTAssertEqual(catalog.effectiveVolume(for: .stdin), 0.2, accuracy: 0.0001)
        XCTAssertEqual(catalog.effectiveVolume(for: .keyboard), 0.5, accuracy: 0.0001)
    }

    func testSettingsVolumeIsClampedToSafePlayerRange() {
        XCTAssertEqual(EdexAudioSettings(audio: true, audioVolume: .infinity, disableFeedbackAudio: false).audioVolume, 1.0)
        XCTAssertEqual(EdexAudioSettings(audio: true, audioVolume: -1.0, disableFeedbackAudio: false).audioVolume, 0.0)
        XCTAssertEqual(EdexAudioSettings(audio: true, audioVolume: 2.0, disableFeedbackAudio: false).audioVolume, 1.0)
    }

    func testSettingsDecodeUsesLegacyKeysAndDefaults() throws {
        let explicit = try JSONDecoder().decode(
            EdexAudioSettings.self,
            from: Data(#"{"audio":false,"audioVolume":0.25,"disableFeedbackAudio":true}"#.utf8)
        )
        XCTAssertEqual(explicit, EdexAudioSettings(audio: false, audioVolume: 0.25, disableFeedbackAudio: true))

        let defaults = try JSONDecoder().decode(EdexAudioSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(defaults, EdexAudioSettings(audio: true, audioVolume: 1.0, disableFeedbackAudio: false))
    }

    func testAssetResolverReturnsExistingCueAndNoOpsMissingCue() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("edex-audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let stdout = directory.appendingPathComponent("stdout.wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: stdout)

        let resolver = EdexAudioAssetResolver(assetDirectory: directory)
        XCTAssertEqual(resolver.url(for: .stdout), stdout)
        XCTAssertNil(resolver.url(for: .keyboard))
    }
}

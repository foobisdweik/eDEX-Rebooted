import XCTest
@testable import EdexDomainSupport

final class NativeMediaViewerTests: XCTestCase {

    // MARK: - MediaPlayerSupport.timeHMS (mirrors legacy mediaTimeToHMS)

    func testTimeHMSZero() {
        XCTAssertEqual(MediaPlayerSupport.timeHMS(0), "00:00:00")
    }

    func testTimeHMSSecondsOnly() {
        XCTAssertEqual(MediaPlayerSupport.timeHMS(5), "00:00:05")
        XCTAssertEqual(MediaPlayerSupport.timeHMS(59), "00:00:59")
    }

    func testTimeHMSMinutesAndSeconds() {
        XCTAssertEqual(MediaPlayerSupport.timeHMS(65), "00:01:05")
        XCTAssertEqual(MediaPlayerSupport.timeHMS(3599), "00:59:59")
    }

    func testTimeHMSHours() {
        XCTAssertEqual(MediaPlayerSupport.timeHMS(3600), "01:00:00")
        XCTAssertEqual(MediaPlayerSupport.timeHMS(3661), "01:01:01")
    }

    func testTimeHMSNegativeReturnsZero() {
        XCTAssertEqual(MediaPlayerSupport.timeHMS(-1), "00:00:00")
        XCTAssertEqual(MediaPlayerSupport.timeHMS(-100), "00:00:00")
    }

    func testTimeHMSNonFiniteReturnsZero() {
        XCTAssertEqual(MediaPlayerSupport.timeHMS(.nan), "00:00:00")
        XCTAssertEqual(MediaPlayerSupport.timeHMS(.infinity), "00:00:00")
        XCTAssertEqual(MediaPlayerSupport.timeHMS(-.infinity), "00:00:00")
    }

    func testTimeHMSTruncatesFractionalSeconds() {
        XCTAssertEqual(MediaPlayerSupport.timeHMS(61.9), "00:01:01")
    }

    // MARK: - MediaPlayerSupport.progressFraction

    func testProgressFractionMidpoint() {
        XCTAssertEqual(MediaPlayerSupport.progressFraction(current: 30, duration: 100), 0.3, accuracy: 0.0001)
    }

    func testProgressFractionClampsHigh() {
        XCTAssertEqual(MediaPlayerSupport.progressFraction(current: 150, duration: 100), 1.0, accuracy: 0.0001)
    }

    func testProgressFractionClampsLow() {
        XCTAssertEqual(MediaPlayerSupport.progressFraction(current: -10, duration: 100), 0.0, accuracy: 0.0001)
    }

    func testProgressFractionZeroDuration() {
        XCTAssertEqual(MediaPlayerSupport.progressFraction(current: 30, duration: 0), 0.0, accuracy: 0.0001)
    }

    func testProgressFractionNonFiniteDuration() {
        XCTAssertEqual(MediaPlayerSupport.progressFraction(current: 30, duration: .nan), 0.0, accuracy: 0.0001)
    }

    func testProgressFractionNonFiniteCurrent() {
        XCTAssertEqual(MediaPlayerSupport.progressFraction(current: .nan, duration: 100), 0.0, accuracy: 0.0001)
    }

    // MARK: - MediaPlayerSupport.seekTime

    func testSeekTimeHalf() {
        XCTAssertEqual(MediaPlayerSupport.seekTime(fraction: 0.5, duration: 100), 50, accuracy: 0.0001)
    }

    func testSeekTimeClampsFraction() {
        XCTAssertEqual(MediaPlayerSupport.seekTime(fraction: 1.5, duration: 100), 100, accuracy: 0.0001)
        XCTAssertEqual(MediaPlayerSupport.seekTime(fraction: -0.5, duration: 100), 0, accuracy: 0.0001)
    }

    func testSeekTimeNonFiniteReturnsZero() {
        XCTAssertEqual(MediaPlayerSupport.seekTime(fraction: .nan, duration: 100), 0, accuracy: 0.0001)
        XCTAssertEqual(MediaPlayerSupport.seekTime(fraction: 0.5, duration: .nan), 0, accuracy: 0.0001)
    }

    // MARK: - MediaPlayerSupport.clampVolume

    func testClampVolumeInRange() {
        XCTAssertEqual(MediaPlayerSupport.clampVolume(0.5), 0.5, accuracy: 0.0001)
    }

    func testClampVolumeClampsHigh() {
        XCTAssertEqual(MediaPlayerSupport.clampVolume(1.5), 1.0, accuracy: 0.0001)
    }

    func testClampVolumeClampsLow() {
        XCTAssertEqual(MediaPlayerSupport.clampVolume(-0.2), 0.0, accuracy: 0.0001)
    }

    func testClampVolumeNonFiniteDefaultsToOne() {
        XCTAssertEqual(MediaPlayerSupport.clampVolume(.nan), 1.0, accuracy: 0.0001)
        XCTAssertEqual(MediaPlayerSupport.clampVolume(.infinity), 1.0, accuracy: 0.0001)
    }

    // MARK: - MediaPlayerSupport.volumeIconName

    func testVolumeIconMuted() {
        XCTAssertEqual(MediaPlayerSupport.volumeIconName(volume: 0.8, muted: true), "mute")
    }

    func testVolumeIconZeroVolume() {
        XCTAssertEqual(MediaPlayerSupport.volumeIconName(volume: 0, muted: false), "mute")
    }

    func testVolumeIconAudible() {
        XCTAssertEqual(MediaPlayerSupport.volumeIconName(volume: 0.5, muted: false), "volume")
    }

    // MARK: - MediaPlayerSupport.playPauseIconName

    func testPlayPauseIconPlaying() {
        XCTAssertEqual(MediaPlayerSupport.playPauseIconName(isPlaying: true), "pause")
    }

    func testPlayPauseIconPaused() {
        XCTAssertEqual(MediaPlayerSupport.playPauseIconName(isPlaying: false), "play")
    }
}

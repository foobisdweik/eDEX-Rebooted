import XCTest
@testable import EdexDomainSupport

final class NativeStdoutCueGateTests: XCTestCase {
    private let epoch = Date(timeIntervalSinceReferenceDate: 0)

    func testFirstOutputFiresTheCue() {
        var gate = StdoutAudioCueGate()
        XCTAssertTrue(gate.shouldPlay(at: epoch, passwordMode: false))
    }

    func testOutputWithinThrottleWindowDoesNotFire() {
        var gate = StdoutAudioCueGate()
        XCTAssertTrue(gate.shouldPlay(at: epoch, passwordMode: false))
        // 20ms later — inside the legacy 30ms window.
        XCTAssertFalse(gate.shouldPlay(at: epoch.addingTimeInterval(0.020), passwordMode: false))
    }

    func testOutputAfterThrottleWindowFiresAgain() {
        var gate = StdoutAudioCueGate()
        XCTAssertTrue(gate.shouldPlay(at: epoch, passwordMode: false))
        // 31ms later — past the legacy 30ms window (strictly greater).
        XCTAssertTrue(gate.shouldPlay(at: epoch.addingTimeInterval(0.031), passwordMode: false))
    }

    func testExactlyAtThrottleBoundaryDoesNotFire() {
        var gate = StdoutAudioCueGate()
        XCTAssertTrue(gate.shouldPlay(at: epoch, passwordMode: false))
        // Legacy uses `> 30`, so exactly the interval is still throttled.
        XCTAssertFalse(gate.shouldPlay(at: epoch.addingTimeInterval(0.030), passwordMode: false))
    }

    func testPasswordModeSuppressesTheCue() {
        var gate = StdoutAudioCueGate()
        XCTAssertFalse(gate.shouldPlay(at: epoch, passwordMode: true))
    }

    func testPasswordModeStillAdvancesTheThrottle() {
        // Legacy stamps lastSoundFX whenever the window opens, even in password
        // mode (the play() call is what's gated, not the stamp). So a normal poll
        // immediately after a password-mode poll is still throttled.
        var gate = StdoutAudioCueGate()
        XCTAssertFalse(gate.shouldPlay(at: epoch, passwordMode: true))
        XCTAssertFalse(gate.shouldPlay(at: epoch.addingTimeInterval(0.010), passwordMode: false))
    }
}

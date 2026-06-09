import XCTest
@testable import EdexDomainSupport

final class NativeBootTests: XCTestCase {

    // MARK: - BootLines raw content

    func testRawLinesCount() {
        XCTAssertEqual(BootLines.rawLines.count, 85)
    }

    func testRawLinesFirstIsWelcome() {
        XCTAssertEqual(BootLines.rawLines.first, "Welcome to eDEX-UI!")
    }

    func testRawLinesLastIsBootComplete() {
        XCTAssertEqual(BootLines.rawLines.last, "Boot Complete")
    }

    func testRawLinesHTMLEntitiesDecoded_Line50() {
        // Original has &lt;dict ...&gt; — native should show actual angle brackets.
        let line = BootLines.rawLines[49]
        XCTAssertTrue(line.contains("<dict"), "Expected decoded < in line 50, got: \(line)")
        XCTAssertFalse(line.contains("&lt;"), "Expected no &lt; in line 50, got: \(line)")
    }

    func testRawLinesHTMLEntitiesDecoded_Line51() {
        let line = BootLines.rawLines[50]
        XCTAssertTrue(line.contains("</string>"), "Expected decoded HTML in line 51, got: \(line)")
    }

    func testRawLinesHTMLEntitiesDecoded_Line73() {
        let line = BootLines.rawLines[72]
        XCTAssertTrue(line.contains("'US'"), "Expected decoded apostrophes in line 73, got: \(line)")
        XCTAssertFalse(line.contains("&#039;"))
    }

    // MARK: - Synthetic kernel line

    func testSyntheticKernelLine_ContainsAppVersion() {
        let line = BootLines.syntheticKernelLine(appVersion: "3.0.0", date: "Mon Jun 02 2026 12:00:00")
        XCTAssertTrue(line.contains("3.0.0"))
    }

    func testSyntheticKernelLine_ContainsXNUSignature() {
        let line = BootLines.syntheticKernelLine(appVersion: "3.0.0", date: "Mon Jun 02 2026 12:00:00")
        XCTAssertTrue(line.contains("xnu-1699.22.73~1/RELEASE_X86_64"))
    }

    func testSyntheticKernelLine_ContainsDate() {
        let line = BootLines.syntheticKernelLine(appVersion: "3.0.0", date: "Tue Jan 01 2030 00:00:00")
        XCTAssertTrue(line.contains("2030"))
    }

    // MARK: - BootTiming

    func testTimingLine0_IsDefaultFormula() {
        // JS default: Math.pow(1 - (i / 1000), 3) * 25ms, where i = index+1 = 1
        let expected = pow(1.0 - 1.0 / 1000.0, 3) * 0.025
        XCTAssertEqual(BootTiming.delay(forLine: 0), expected, accuracy: 0.001)
    }

    func testTimingLine1_Is500ms() {
        // JS case i===2 fall-through to 500ms.
        XCTAssertEqual(BootTiming.delay(forLine: 1), 0.500, accuracy: 0.001)
    }

    func testTimingLine2_IsDefault() {
        // JS i=3 → default formula.
        let expected = pow(1.0 - 3.0 / 1000.0, 3) * 0.025
        XCTAssertEqual(BootTiming.delay(forLine: 2), expected, accuracy: 0.001)
    }

    func testTimingLine3_Is500ms() {
        // JS case i===4.
        XCTAssertEqual(BootTiming.delay(forLine: 3), 0.500, accuracy: 0.001)
    }

    func testTimingFastRange_30ms() {
        // JS case i > 4 && i < 25 (line indices 4..23).
        for index in 4..<24 {
            XCTAssertEqual(BootTiming.delay(forLine: index), 0.030, accuracy: 0.001,
                           "Expected 30ms for line \(index)")
        }
    }

    func testTimingLine24_Is400ms() {
        // JS case i===25.
        XCTAssertEqual(BootTiming.delay(forLine: 24), 0.400, accuracy: 0.001)
    }

    func testTimingMidDefault() {
        // JS default range for i 26..41 (line indices 25..40).
        for index in 25...40 {
            let expected = pow(1.0 - Double(index + 1) / 1000.0, 3) * 0.025
            XCTAssertEqual(BootTiming.delay(forLine: index), expected, accuracy: 0.001,
                           "Expected default delay for line \(index)")
        }
    }

    func testTimingLine41_Is300ms() {
        // JS case i===42.
        XCTAssertEqual(BootTiming.delay(forLine: 41), 0.300, accuracy: 0.001)
    }

    func testTimingFastRange2_25ms() {
        // JS case i > 42 && i < 82 (line indices 42..80).
        for index in 42...80 {
            XCTAssertEqual(BootTiming.delay(forLine: index), 0.025, accuracy: 0.001,
                           "Expected 25ms for line \(index)")
        }
    }

    func testTimingLine82_Is25ms() {
        // JS case i===83 (index 82 → i_after = 83).
        XCTAssertEqual(BootTiming.delay(forLine: 82), 0.025, accuracy: 0.001)
    }

    func testTimingLine83_Is300ms() {
        // JS case i >= bootLog.length-2 && i < bootLog.length → i in {83,84} → 300ms.
        XCTAssertEqual(BootTiming.delay(forLine: 83), 0.300, accuracy: 0.001)
    }

    func testTimingLine84_IsDefault() {
        // JS: after displaying bootLog[84] i becomes 85; 85>=83&&85<85 is FALSE
        // so it falls to the default formula, not the 300ms tail case.
        // The 300ms pre-title-flash pause is handled by the caller after the loop.
        let expected = pow(1.0 - 85.0 / 1000.0, 3) * 0.025
        XCTAssertEqual(BootTiming.delay(forLine: 84), expected, accuracy: 0.001)
    }

    // MARK: - BootSequenceConfig

    func testNointroTrue_SkipsLog() {
        XCTAssertTrue(BootSequenceConfig.shouldSkipLog(nointro: true))
    }

    func testNointroFalse_DoesNotSkipLog() {
        XCTAssertFalse(BootSequenceConfig.shouldSkipLog(nointro: false))
    }
}

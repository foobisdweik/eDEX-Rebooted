import XCTest
@testable import RamwatcherSupport

final class NativeRamwatcherTests: XCTestCase {
    private let formatter = EdexRamwatcherFormatter()
    private let gib: UInt64 = 1_073_742_000

    // MARK: - Grid

    func testGridCellCountIs440() {
        XCTAssertEqual(EdexRamwatcherFormatter.gridCellCount, 440)
    }

    // MARK: - Active / available cell counts (round to the 440 grid)

    func testActiveCountIsProportionalRoundedTo440() {
        XCTAssertEqual(formatter.activeCount(active: 8 * gib, total: 16 * gib), 220)
        XCTAssertEqual(formatter.activeCount(active: 0, total: 16 * gib), 0)
    }

    func testActiveCountIsZeroWhenTotalIsZero() {
        XCTAssertEqual(formatter.activeCount(active: 5 * gib, total: 0), 0)
    }

    func testAvailableCountUsesAvailableMinusFree() {
        XCTAssertEqual(formatter.availableCount(available: 12 * gib, free: 4 * gib, total: 16 * gib), 220)
    }

    func testAvailableCountClampsNegativeToZero() {
        XCTAssertEqual(formatter.availableCount(available: 2 * gib, free: 4 * gib, total: 16 * gib), 0)
    }

    // MARK: - Cell-state partition by rank

    func testCellStatePartitionsByRank() {
        XCTAssertEqual(formatter.cellState(rank: 0, activeCount: 220, availableCount: 100), .active)
        XCTAssertEqual(formatter.cellState(rank: 219, activeCount: 220, availableCount: 100), .active)
        XCTAssertEqual(formatter.cellState(rank: 220, activeCount: 220, availableCount: 100), .available)
        XCTAssertEqual(formatter.cellState(rank: 319, activeCount: 220, availableCount: 100), .available)
        XCTAssertEqual(formatter.cellState(rank: 320, activeCount: 220, availableCount: 100), .free)
    }

    // MARK: - Info text ("USING x OUT OF y GiB")

    func testInfoTextFormatsWholeGiB() {
        XCTAssertEqual(formatter.infoText(active: 8 * gib, total: 16 * gib), "USING 8 OUT OF 16 GiB")
    }

    func testInfoTextKeepsOneDecimal() {
        let onePointFive = UInt64(Double(gib) * 1.5)
        XCTAssertEqual(formatter.infoText(active: onePointFive, total: 16 * gib), "USING 1.5 OUT OF 16 GiB")
    }

    // MARK: - Swap

    func testSwapPercentRounds() {
        XCTAssertEqual(formatter.swapPercent(used: 2 * gib, total: 4 * gib), 50)
    }

    func testSwapPercentIsZeroWhenNoSwap() {
        XCTAssertEqual(formatter.swapPercent(used: 0, total: 0), 0)
    }

    func testSwapPercentClampsInconsistentValuesInsteadOfCrashing() {
        // A garbage reading (used >> total) overflows Int on the cast; guard → 0.
        XCTAssertEqual(formatter.swapPercent(used: .max, total: 1), 0)
    }

    func testActiveCountClampsInconsistentValuesInsteadOfCrashing() {
        // 440 * UInt64.max / 1 exceeds Int.max; guard → 0 rather than crash.
        XCTAssertEqual(formatter.activeCount(active: .max, total: 1), 0)
    }

    func testSwapTextFormatsGiB() {
        XCTAssertEqual(formatter.swapText(used: 2 * gib), "2 GiB")
    }
}

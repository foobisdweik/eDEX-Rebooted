import XCTest
@testable import ToplistSupport

final class NativeToplistTests: XCTestCase {
    private let formatter = EdexToplistFormatter()

    func testPercentTextRoundsToOneDecimal() {
        XCTAssertEqual(formatter.percentText(12.34), "12.3%")
        XCTAssertEqual(formatter.percentText(12.35), "12.4%")
    }

    func testPercentTextHandlesNonFiniteWithoutCrashing() {
        XCTAssertEqual(formatter.percentText(.nan), "0%")
        XCTAssertEqual(formatter.percentText(.infinity), "0%")
    }

    func testDefaultSortUsesLegacyCpuMemoryScoreDescending() {
        let rows = [
            EdexProcessRow(pid: 1, name: "mem", user: "u", cpu: 1, mem: 90, state: "Sleep", started: "2026-06-02T10:00:00Z"),
            EdexProcessRow(pid: 2, name: "cpu", user: "u", cpu: 2, mem: 0, state: "Run", started: "2026-06-02T10:00:00Z"),
            EdexProcessRow(pid: 3, name: "idle", user: "u", cpu: 0.1, mem: 0, state: "Sleep", started: "2026-06-02T10:00:00Z")
        ]

        XCTAssertEqual(formatter.sorted(rows, sort: .default).map(\.pid), [2, 1, 3])
    }

    func testSortStateCyclesFieldDescendingAscendingNone() {
        var sort = EdexProcessSort.default
        sort = sort.toggled(.cpu)
        XCTAssertEqual(sort, .field(.cpu, ascending: false))
        sort = sort.toggled(.cpu)
        XCTAssertEqual(sort, .field(.cpu, ascending: true))
        sort = sort.toggled(.cpu)
        XCTAssertEqual(sort, .default)
    }

    func testNumericSortsRespectAscendingFlag() {
        let rows = [
            EdexProcessRow(pid: 10, name: "a", user: "u", cpu: 1, mem: 0, state: "Sleep", started: "2026-06-02T10:00:00Z"),
            EdexProcessRow(pid: 20, name: "b", user: "u", cpu: 5, mem: 0, state: "Sleep", started: "2026-06-02T10:00:00Z")
        ]

        XCTAssertEqual(formatter.sorted(rows, sort: .field(.cpu, ascending: false)).map(\.pid), [20, 10])
        XCTAssertEqual(formatter.sorted(rows, sort: .field(.cpu, ascending: true)).map(\.pid), [10, 20])
    }

    func testStringSortMatchesLegacyDirection() {
        let rows = [
            EdexProcessRow(pid: 1, name: "zsh", user: "you", cpu: 0, mem: 0, state: "Sleep", started: "2026-06-02T10:00:00Z"),
            EdexProcessRow(pid: 2, name: "Finder", user: "you", cpu: 0, mem: 0, state: "Run", started: "2026-06-02T10:00:00Z")
        ]

        XCTAssertEqual(formatter.sorted(rows, sort: .field(.name, ascending: false)).map(\.pid), [2, 1])
        XCTAssertEqual(formatter.sorted(rows, sort: .field(.name, ascending: true)).map(\.pid), [1, 2])
    }

    func testRuntimeTextFormatsDaysHoursMinutesSeconds() {
        let started = ISO8601DateFormatter().date(from: "2026-06-01T08:09:10Z")!
        let now = ISO8601DateFormatter().date(from: "2026-06-02T10:11:13Z")!

        XCTAssertEqual(formatter.runtimeText(started: started, now: now), "01:02:02:03")
    }

    func testRuntimeTextReturnsZeroForFutureDates() {
        let started = ISO8601DateFormatter().date(from: "2026-06-03T08:09:10Z")!
        let now = ISO8601DateFormatter().date(from: "2026-06-02T10:11:13Z")!

        XCTAssertEqual(formatter.runtimeText(started: started, now: now), "00:00:00:00")
    }
}

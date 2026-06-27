import XCTest
@testable import EdexDomainSupport

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

    func testPercentTextHandlesOutOfIntRangeWithoutCrashing() {
        XCTAssertEqual(formatter.percentText(Double(Int.max)), "\(Double(Int.max))%")
        XCTAssertEqual(formatter.percentText(.greatestFiniteMagnitude), "0%")
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

    func testStringSortDirectionIsConsistentWithNumericColumns() {
        // Descending (first click / ▼) puts higher values first; for strings that is Z→A.
        // Ascending (second click / ▲) is A→Z. This matches the numeric columns and the
        // header arrow, fixing the inverted string direction in the legacy toplist.class.js.
        let rows = [
            EdexProcessRow(pid: 1, name: "zsh", user: "you", cpu: 0, mem: 0, state: "Sleep", started: "2026-06-02T10:00:00Z"),
            EdexProcessRow(pid: 2, name: "Finder", user: "you", cpu: 0, mem: 0, state: "Run", started: "2026-06-02T10:00:00Z")
        ]

        XCTAssertEqual(formatter.sorted(rows, sort: .field(.name, ascending: false)).map(\.pid), [1, 2])
        XCTAssertEqual(formatter.sorted(rows, sort: .field(.name, ascending: true)).map(\.pid), [2, 1])
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

    func testRuntimeTextRejectsOutOfIntRangeInterval() {
        let started = Date(timeIntervalSinceReferenceDate: 0)
        let now = Date(timeIntervalSinceReferenceDate: Double(Int.max))

        XCTAssertEqual(formatter.runtimeText(started: started, now: now), "00:00:00:00")
    }

    // Finding #4: `prepared` must order rows identically to `sorted` for every
    // sort, and pre-format CPU/MEM the way the cells did.
    private var preparedFixture: [EdexProcessRow] {
        [
            EdexProcessRow(pid: 1, name: "beta", user: "root", cpu: 12.5, mem: 3, state: "Sleep", started: "2026-06-02T10:00:00Z"),
            EdexProcessRow(pid: 2, name: "alpha", user: "alice", cpu: 80, mem: 50, state: "Run", started: "2026-06-01T09:30:00Z"),
            EdexProcessRow(pid: 3, name: "gamma", user: "bob", cpu: 0.1, mem: 99, state: "Idle", started: "2026-06-02T11:45:00Z"),
            EdexProcessRow(pid: 4, name: "delta", user: "alice", cpu: 5, mem: 5, state: "Sleep", started: "bogus-date"),
        ]
    }

    func testPreparedMatchesSortedOrderingForEverySort() {
        let now = ISO8601DateFormatter().date(from: "2026-06-02T12:00:00Z")!
        var sorts: [EdexProcessSort] = [.default]
        for field in EdexProcessSortField.allCases {
            sorts.append(.field(field, ascending: false))
            sorts.append(.field(field, ascending: true))
        }
        for sort in sorts {
            XCTAssertEqual(
                formatter.prepared(preparedFixture, sort: sort, now: now).map(\.pid),
                formatter.sorted(preparedFixture, sort: sort, now: now).map(\.pid),
                "sort \(sort)"
            )
        }
    }

    func testPreparedPrecomputesTextAndDate() {
        let prepared = formatter.prepared(preparedFixture, sort: .field(.pid, ascending: true))
        XCTAssertEqual(prepared.map(\.pid), [1, 2, 3, 4])
        XCTAssertEqual(prepared[0].cpuText, formatter.percentText(12.5))
        XCTAssertEqual(prepared[0].memText, formatter.percentText(3))
        XCTAssertNotNil(prepared[0].startDate)
        // Unparseable `started` keeps a nil date (runtime cell falls back).
        XCTAssertNil(prepared[3].startDate)
    }
}

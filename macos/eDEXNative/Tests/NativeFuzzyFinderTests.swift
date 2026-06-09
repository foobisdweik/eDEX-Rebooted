import XCTest
@testable import EdexDomainSupport

final class NativeFuzzyFinderTests: XCTestCase {
    func testSearchExcludesShowDisksAndGoUpRows() {
        let results = FuzzyMatcher.search([
            item("Show disks", role: .showDisks),
            item("Go up", role: .goUp),
            item("main.rs", role: .file)
        ], query: "")

        XCTAssertEqual(results.map(\.name), ["main.rs"])
    }

    func testEmptyQueryReturnsFirstLimitRowsExcludingSpecials() {
        let results = FuzzyMatcher.search([
            item("Show disks", role: .showDisks),
            item("a.txt"),
            item("b.txt"),
            item("c.txt"),
            item("d.txt")
        ], query: "", limit: 3)

        XCTAssertEqual(results.map(\.name), ["a.txt", "b.txt", "c.txt"])
    }

    func testSearchIsCaseInsensitiveSubstring() {
        let results = FuzzyMatcher.search([
            item("README.md"),
            item("main.rs"),
            item("config.toml")
        ], query: "RS")

        XCTAssertEqual(results.map(\.name), ["main.rs"])
    }

    func testPrefixMatchesSortAheadOfMidStringMatches() {
        let results = FuzzyMatcher.search([
            item("tomlconf"),
            item("config"),
            item("cobalt")
        ], query: "co")

        XCTAssertEqual(results.map(\.name), ["config", "cobalt", "tomlconf"])
    }

    func testPrefixMatchesSortAheadOfMidStringMatchesBeforeLimitIsApplied() {
        let results = FuzzyMatcher.search([
            item("tomlconf"),
            item("anotherconf"),
            item("config"),
            item("cobalt")
        ], query: "co", limit: 2)

        XCTAssertEqual(results.map(\.name), ["config", "cobalt"])
    }

    func testResultCountIsCappedAtLimit() {
        let results = FuzzyMatcher.search([
            item("a1"),
            item("a2"),
            item("a3"),
            item("a4")
        ], query: "a", limit: 2)

        XCTAssertEqual(results.map(\.name), ["a1", "a2"])
    }

    func testNoMatchesReturnsEmptyArray() {
        let results = FuzzyMatcher.search([
            item("main.rs"),
            item("config.toml")
        ], query: "zzz")

        XCTAssertEqual(results, [])
    }

    func testSelectionNextWrapsPastEndToZero() {
        XCTAssertEqual(FuzzySelection.next(from: 0, count: 3), 1)
        XCTAssertEqual(FuzzySelection.next(from: 2, count: 3), 0)
        XCTAssertEqual(FuzzySelection.next(from: 0, count: 0), 0)
    }

    func testSelectionPreviousWrapsBeforeStartToZero() {
        XCTAssertEqual(FuzzySelection.previous(from: 2, count: 3), 1)
        // Legacy fuzzyFinder.class.js wraps underflow to 0, not to the last row.
        XCTAssertEqual(FuzzySelection.previous(from: 0, count: 3), 0)
        XCTAssertEqual(FuzzySelection.previous(from: 0, count: 0), 0)
    }

    func testTerminalInputQuotesPlainPath() {
        XCTAssertEqual(FuzzyTerminalInput.quotedPath("/Users/me/main.rs"), "'/Users/me/main.rs'")
    }

    func testTerminalInputEscapesSingleQuotesForPOSIXShell() {
        XCTAssertEqual(
            FuzzyTerminalInput.quotedPath("/Users/me/don't_do_this.txt"),
            "'/Users/me/don'\\''t_do_this.txt'"
        )
    }

    private func item(_ name: String, role: FilesystemRole = .file) -> FilesystemItem {
        FilesystemItem(
            id: "/tmp/\(name)",
            name: name,
            path: "/tmp/\(name)",
            role: role,
            hidden: false,
            size: role == .file ? 1 : nil
        )
    }
}

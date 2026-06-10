import XCTest
@testable import EdexDomainSupport

final class NativeKeyboardViewTests: XCTestCase {
    private func bundledKeyboardDirectory() -> URL {
        EdexBundledAssets.keyboardsDirectory(from: #filePath)
    }

    private func enUSLayout() throws -> NativeKeyboardLayout {
        let file = bundledKeyboardDirectory().appendingPathComponent("en-US.json")
        return try NativeKeyboardLayout(
            json: String(contentsOf: file, encoding: .utf8),
            name: "en-US"
        )
    }

    private func descriptors() throws -> [[KeyboardKeyDescriptor]] {
        KeyboardViewModel.descriptors(for: try enUSLayout())
    }

    func testDescriptorRowsMatchLayout() throws {
        let layout = try enUSLayout()
        let rows = KeyboardViewModel.descriptors(for: layout)
        XCTAssertEqual(rows.count, layout.rows.count)
        for (row, descriptorRow) in zip(layout.rows, rows) {
            XCTAssertEqual(descriptorRow.count, row.keys.count)
        }
        // IDs are unique and stable across rows.
        let ids = rows.flatMap { $0 }.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEdgeKeysAreWide() throws {
        let rows = try descriptors()
        // First key of the number row (ESC) is wide; last key (BACK) is wide.
        XCTAssertEqual(rows[0].first?.role, .wide)
        XCTAssertEqual(rows[0].last?.role, .wide)
        // First key of every row is wide.
        for row in rows {
            XCTAssertEqual(row.first?.role, .wide, "first key of a row should be wide")
        }
    }

    func testEnterAndSpacebarRoles() throws {
        let rows = try descriptors()
        // row_1 ends with the primary ENTER.
        XCTAssertEqual(rows[1].last?.role, .enter)
        // row_2 ends with the empty-named enter continuation (the L-shape bottom).
        XCTAssertEqual(rows[2].last?.role, .enterContinuation)
        // row_space has the spacebar (cmd " ").
        XCTAssertTrue(rows[4].contains { $0.role == .spacebar })
    }

    func testArrowKeysAreIcons() throws {
        let rows = try descriptors()
        let up = rows[3].first { $0.role == .icon("ARROW_UP") }
        XCTAssertNotNil(up, "row_3 should expose the up-arrow icon key")
        let left = rows[4].first { $0.role == .icon("ARROW_LEFT") }
        XCTAssertNotNil(left, "row_space should expose the left-arrow icon key")
    }

    func testModifierIdentity() throws {
        let rows = try descriptors()
        let all = rows.flatMap { $0 }
        XCTAssertEqual(all.first { $0.key.name == "CAPS" }?.modifier, .capsLock)
        XCTAssertEqual(all.first { $0.key.name == "FN" }?.modifier, .fn)
        XCTAssertEqual(all.first { $0.key.name == "SHIFT" }?.modifier, .shift)
        XCTAssertEqual(all.first { $0.key.name == "CTRL" }?.modifier, .ctrl)
        XCTAssertEqual(all.first { $0.key.name == "ALT GR" }?.modifier, .alt)
        // A plain letter key has no modifier identity.
        XCTAssertNil(all.first { $0.key.name == "A" }?.modifier)
    }

    func testProminentLabelFollowsModifiers() throws {
        let rows = try descriptors()
        let one = try XCTUnwrap(rows.flatMap { $0 }.first { $0.key.name == "1" })

        XCTAssertEqual(one.prominentLabel(modifiers: KeyboardModifierState()), "1")
        XCTAssertEqual(one.prominentLabel(modifiers: KeyboardModifierState(shift: true)), "!")
        XCTAssertEqual(one.prominentLabel(modifiers: KeyboardModifierState(capsLock: true)), "!")
        // Fn promotes the function label when present (1 -> F1).
        XCTAssertEqual(one.prominentLabel(modifiers: KeyboardModifierState(fn: true)), "F1")
    }

    func testIconKeyHasNoTextLabel() throws {
        let rows = try descriptors()
        let up = try XCTUnwrap(rows[3].first { $0.role == .icon("ARROW_UP") })
        XCTAssertEqual(up.mainLabel, "")
    }

    func testBandOpacity() {
        XCTAssertEqual(KeyboardViewModel.bandOpacity(modifiers: KeyboardModifierState(), isDetached: false), 1.0)
        XCTAssertEqual(
            KeyboardViewModel.bandOpacity(modifiers: KeyboardModifierState(passwordMode: true), isDetached: false),
            0.5
        )
        XCTAssertEqual(KeyboardViewModel.bandOpacity(modifiers: KeyboardModifierState(), isDetached: true), 0.18)
        // Password mode wins over detach dimming.
        XCTAssertEqual(
            KeyboardViewModel.bandOpacity(modifiers: KeyboardModifierState(passwordMode: true), isDetached: true),
            0.5
        )
    }

    func testModifierStateToggle() {
        var state = KeyboardModifierState()
        state.toggle(.capsLock)
        XCTAssertTrue(state.capsLock)
        state.toggle(.capsLock)
        XCTAssertFalse(state.capsLock)
    }

    func testRowMetricsFitInsideKeyboardFrame() throws {
        let rows = try descriptors()
        let metrics = KeyboardRowLayoutMetrics.fit(
            rows: rows,
            availableWidth: 360,
            availableHeight: 150,
            preferredKeySide: 40,
            preferredSpacebarWidth: 220,
            preferredRowHeight: 36,
            preferredRowGap: 9,
            preferredKeyGap: 6
        )

        for row in rows {
            let width = metrics.rowWidth(for: row)
            XCTAssertLessThanOrEqual(width, 360.001)
            XCTAssertGreaterThan(metrics.keyWidth(for: row[0]), 0)
        }
        XCTAssertLessThanOrEqual(metrics.totalHeight(rowCount: rows.count), 150.001)
    }
}

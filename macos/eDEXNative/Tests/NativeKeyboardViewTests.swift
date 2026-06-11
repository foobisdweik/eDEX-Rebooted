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

    func testNumpadRowsExposeStandardTenKeyCluster() throws {
        let rows = KeyboardViewModel.numpadDescriptors()
        let all = rows.flatMap { $0 }

        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(all.first { $0.key.name == "NUM" }?.id, "numpad_0_0")
        XCTAssertNotNil(all.first { $0.key.name == "HOME" })
        XCTAssertNotNil(all.first { $0.key.name == "INS" })
        XCTAssertNotNil(all.first { $0.key.name == "DEL" })
        XCTAssertNotNil(all.first { $0.key.name == "7" && $0.key.alternateName == "HOME" })
        XCTAssertNotNil(all.first { $0.key.name == "0" && $0.key.alternateName == "INS" })
        XCTAssertEqual(all.first { $0.key.name == "0" }?.role, .wide)
    }

    func testMacBookRowsMatchPhysicalKeyboardShapeWithoutEnterContinuation() throws {
        let rows = KeyboardViewModel.macBookDescriptors(for: try enUSLayout())
        let names = rows.map { $0.map(\.key.name) }

        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(names[0], ["ESC", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"])
        XCTAssertEqual(names[1], ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "DELETE"])
        XCTAssertEqual(names[2], ["TAB", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\"])
        XCTAssertEqual(names[3], ["CAPS", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "RETURN"])
        XCTAssertEqual(names[4], ["SHIFT", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "SHIFT"])
        XCTAssertEqual(names[5], ["FN", "CTRL", "OPTION", "COMMAND", "SPACE", "COMMAND", "OPTION", "LEFT", "UP", "DOWN", "RIGHT"])
        XCTAssertFalse(rows.flatMap { $0 }.contains { $0.role == .enterContinuation })
        XCTAssertFalse(rows.flatMap { $0 }.contains { $0.key.name.isEmpty })
    }

    func testMacBookRowsExposeDistinctLeftAndRightShiftIDs() throws {
        let layout = try enUSLayout()
        let all = KeyboardViewModel.macBookDescriptors(for: layout).flatMap { $0 }

        XCTAssertEqual(all.first { $0.id == "mac_shift_left" }?.modifier, .shift)
        XCTAssertEqual(all.first { $0.id == "mac_shift_right" }?.modifier, .shift)
        XCTAssertEqual(KeyboardPhysicalKeyMapper.descriptorID(for: .leftShift, in: layout), "mac_shift_left")
        XCTAssertEqual(KeyboardPhysicalKeyMapper.descriptorID(for: .rightShift, in: layout), "mac_shift_right")
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

    func testPhysicalKeyMapperFindsPrintableKeys() throws {
        let layout = try enUSLayout()
        let all = KeyboardViewModel.macBookDescriptors(for: layout).flatMap { $0 }

        XCTAssertEqual(
            KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [], key: .character("a")), in: layout),
            all.first { $0.key.name == "A" }?.id
        )
    }

    func testPhysicalKeyMapperFallsBackFromShiftedPrintableKeys() throws {
        let layout = try enUSLayout()
        let all = KeyboardViewModel.macBookDescriptors(for: layout).flatMap { $0 }

        XCTAssertEqual(
            KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [.shift], key: .character("a")), in: layout),
            all.first { $0.key.name == "A" }?.id
        )
    }

    func testPhysicalKeyMapperFindsSpecialKeys() throws {
        let layout = try enUSLayout()
        let all = KeyboardViewModel.macBookDescriptors(for: layout).flatMap { $0 }

        XCTAssertEqual(
            KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [], key: .special(.space)), in: layout),
            all.first { $0.role == .spacebar }?.id
        )
        XCTAssertEqual(
            KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [], key: .special(.tab)), in: layout),
            all.first { $0.key.name == "TAB" }?.id
        )
        XCTAssertEqual(
            KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [], key: .character("\r")), in: layout),
            all.first { $0.id == "mac_return" }?.id
        )
        XCTAssertEqual(
            KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [], key: .character("\u{1B}")), in: layout),
            all.first { $0.key.name == "ESC" }?.id
        )
        XCTAssertEqual(
            KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [], key: .character("\u{8}")), in: layout),
            all.first { $0.key.name == "DELETE" }?.id
        )
        XCTAssertEqual(
            KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [], key: .character("\u{7F}")), in: layout),
            all.first { $0.key.name == "DELETE" }?.id
        )
        XCTAssertEqual(
            KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [], key: .character("\u{F700}")), in: layout),
            all.first { $0.role == .icon("ARROW_UP") }?.id
        )
        XCTAssertEqual(
            KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [], key: .character("\u{F701}")), in: layout),
            all.first { $0.role == .icon("ARROW_DOWN") }?.id
        )
        XCTAssertEqual(
            KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [], key: .character("\u{F702}")), in: layout),
            all.first { $0.role == .icon("ARROW_LEFT") }?.id
        )
        XCTAssertEqual(
            KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [], key: .character("\u{F703}")), in: layout),
            all.first { $0.role == .icon("ARROW_RIGHT") }?.id
        )
    }

    func testPhysicalKeyMapperIgnoresUnknownKeys() throws {
        let layout = try enUSLayout()

        XCTAssertNil(
            KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [], key: .character("☃")), in: layout)
        )
    }

    func testPhysicalKeyMapperFindsFunctionKeys() throws {
        let layout = try enUSLayout()
        let all = KeyboardViewModel.macBookDescriptors(for: layout).flatMap { $0 }

        XCTAssertEqual(
            KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [], key: .function(5)), in: layout),
            all.first { $0.key.name == "F5" }?.id
        )
    }

    func testPhysicalKeyMapperFindsModifierKeys() throws {
        let layout = try enUSLayout()
        let all = KeyboardViewModel.macBookDescriptors(for: layout).flatMap { $0 }

        XCTAssertEqual(
            KeyboardPhysicalKeyMapper.descriptorID(for: .shift, in: layout),
            all.first { $0.modifier == .shift }?.id
        )
        XCTAssertEqual(
            KeyboardPhysicalKeyMapper.descriptorID(for: .ctrl, in: layout),
            all.first { $0.modifier == .ctrl }?.id
        )
        XCTAssertEqual(
            KeyboardPhysicalKeyMapper.descriptorID(for: .alt, in: layout),
            all.first { $0.modifier == .alt }?.id
        )
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

    func testClusterMetricsFitPrimaryKeyboardAndNumpadTogether() throws {
        let rows = try descriptors()
        let numpadRows = KeyboardViewModel.numpadDescriptors()
        let metrics = KeyboardRowLayoutMetrics.fit(
            primaryRows: rows,
            numpadRows: numpadRows,
            availableWidth: 760,
            availableHeight: 190,
            preferredKeySide: 44,
            preferredSpacebarWidth: 260,
            preferredRowHeight: 52,
            preferredRowGap: 9,
            preferredKeyGap: 8,
            preferredClusterGap: 28
        )

        XCTAssertLessThanOrEqual(metrics.keySide, metrics.rowHeight * 0.85 + 0.001)
        XCTAssertEqual(metrics.keyGap, 8, accuracy: 0.001)
        for index in rows.indices {
            let width = metrics.rowWidth(for: rows[index])
                + metrics.clusterGap
                + metrics.rowWidth(for: numpadRows[index])
            XCTAssertLessThanOrEqual(width, 760.001)
        }
    }

    func testClusterMetricsFitInsideFullscreenKeyboardPanelInterior() throws {
        let rows = try descriptors()
        let numpadRows = KeyboardViewModel.numpadDescriptors()
        let metrics = KeyboardRowLayoutMetrics.fit(
            primaryRows: rows,
            numpadRows: numpadRows,
            availableWidth: 940,
            availableHeight: 330,
            preferredKeySide: 44.88,
            preferredSpacebarWidth: 576,
            preferredRowHeight: 67.58,
            preferredRowGap: 11.78,
            preferredKeyGap: 8,
            preferredClusterGap: 28
        )

        for index in rows.indices {
            let width = metrics.rowWidth(for: rows[index])
                + metrics.clusterGap
                + metrics.rowWidth(for: numpadRows[index])
            XCTAssertLessThanOrEqual(width, 940.001)
        }
    }
}

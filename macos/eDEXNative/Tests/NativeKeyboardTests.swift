import XCTest
@testable import KeyboardSupport

final class NativeKeyboardTests: XCTestCase {
    private func bundledKeyboardDirectory() -> URL {
        let packageDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/assets/kb_layouts")
    }

    private func enUSLayout() throws -> NativeKeyboardLayout {
        let file = bundledKeyboardDirectory().appendingPathComponent("en-US.json")
        return try NativeKeyboardLayout(
            json: String(contentsOf: file, encoding: .utf8),
            name: "en-US"
        )
    }

    func testBundledKeyboardLayoutsDecode() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: bundledKeyboardDirectory(),
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(files.isEmpty)
        XCTAssertTrue(files.contains { $0.lastPathComponent == "en-US.json" })

        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            let layout = try NativeKeyboardLayout(
                json: String(contentsOf: file, encoding: .utf8),
                name: name
            )
            XCTAssertEqual(layout.name, name)
            XCTAssertEqual(layout.rows.map(\.id), [.numbers, .row1, .row2, .row3, .space])
            XCTAssertGreaterThan(layout.keyCount, 50, name)
        }
    }

    func testControlSequencePlaceholdersExpand() throws {
        let layout = try enUSLayout()

        XCTAssertEqual(layout.rows[0].keys[0].command, "\u{001B}")
        let arrowUp = layout.key(iconName: "ARROW_UP")
        XCTAssertEqual(arrowUp?.command, "\u{001B}OA")
        let ctrlC = layout.key(name: "C")
        XCTAssertEqual(ctrlC?.controlCommand, "\u{0003}")
    }

    func testLabelsAndCommandsArePreserved() throws {
        let layout = try enUSLayout()
        let one = try XCTUnwrap(layout.key(name: "1"))

        XCTAssertEqual(one.name, "1")
        XCTAssertEqual(one.command, "1")
        XCTAssertEqual(one.shiftName, "!")
        XCTAssertEqual(one.shiftCommand, "!")
        XCTAssertEqual(one.functionName, "F1")
        XCTAssertEqual(one.functionCommand, "\u{001B}OP")
    }

    func testIconNamesAreNormalizedWithoutLosingCommand() throws {
        let layout = try enUSLayout()
        let arrowLeft = try XCTUnwrap(layout.key(iconName: "ARROW_LEFT"))

        XCTAssertEqual(arrowLeft.name, "ARROW_LEFT")
        XCTAssertEqual(arrowLeft.iconName, "ARROW_LEFT")
        XCTAssertEqual(arrowLeft.command, "\u{001B}OD")
    }

    func testRejectsLayoutsMissingRequiredRows() {
        let json = #"{"row_numbers":[{"name":"ESC","cmd":"~~~CTRLSEQ1~~~"}]}"#

        XCTAssertThrowsError(try NativeKeyboardLayout(json: json, name: "bad")) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                XCTFail("Expected DecodingError.dataCorrupted, got \(error)")
                return
            }
            XCTAssertEqual(
                context.debugDescription,
                "Keyboard layout missing required rows: row_1, row_2, row_3, row_space"
            )
        }
    }
}

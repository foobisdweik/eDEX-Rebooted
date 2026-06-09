import XCTest
@testable import EdexDomainSupport

final class NativeTextEditorTests: XCTestCase {

    // MARK: - EdexTextDocument basics

    func testNewDocumentIsNotDirty() {
        let doc = EdexTextDocument(path: "/tmp/a.txt", text: "hello")
        XCTAssertFalse(doc.isDirty)
        XCTAssertEqual(doc.text, "hello")
    }

    func testEditingMakesDocumentDirty() {
        var doc = EdexTextDocument(path: "/tmp/a.txt", text: "hello")
        doc.text = "hello world"
        XCTAssertTrue(doc.isDirty)
    }

    func testRevertingTextClearsDirty() {
        var doc = EdexTextDocument(path: "/tmp/a.txt", text: "hello")
        doc.text = "changed"
        XCTAssertTrue(doc.isDirty)
        doc.text = "hello"
        XCTAssertFalse(doc.isDirty)
    }

    func testMarkSavedRebaselines() {
        var doc = EdexTextDocument(path: "/tmp/a.txt", text: "hello")
        doc.text = "hello world"
        XCTAssertTrue(doc.isDirty)
        doc.markSaved()
        XCTAssertFalse(doc.isDirty)
        // A subsequent edit is dirty against the new baseline.
        doc.text = "hello world!"
        XCTAssertTrue(doc.isDirty)
    }

    // MARK: - Metrics

    func testLineCount() {
        XCTAssertEqual(EdexTextDocument(path: "/a", text: "").lineCount, 0)
        XCTAssertEqual(EdexTextDocument(path: "/a", text: "one").lineCount, 1)
        XCTAssertEqual(EdexTextDocument(path: "/a", text: "one\ntwo").lineCount, 2)
        // A trailing newline yields a trailing (empty) line, like a text editor.
        XCTAssertEqual(EdexTextDocument(path: "/a", text: "one\ntwo\n").lineCount, 3)
    }

    func testByteCountIsUTF8() {
        XCTAssertEqual(EdexTextDocument(path: "/a", text: "hello").byteCount, 5)
        // "é" is 2 UTF-8 bytes.
        XCTAssertEqual(EdexTextDocument(path: "/a", text: "héllo").byteCount, 6)
    }

    func testFileNameIsBasename() {
        XCTAssertEqual(EdexTextDocument(path: "/Users/foo/notes.txt", text: "").fileName, "notes.txt")
        XCTAssertEqual(EdexTextDocument(path: "/", text: "").fileName, "")
    }

    // MARK: - Status line

    func testStatusLineCleanDocument() {
        let doc = EdexTextDocument(path: "/a", text: "one\ntwo")
        let line = doc.statusLine
        XCTAssertTrue(line.contains("2 lines"), "got: \(line)")
        XCTAssertTrue(line.contains("7 Bytes"), "got: \(line)")
        XCTAssertFalse(line.contains("modified"), "clean doc should not show modified: \(line)")
    }

    func testStatusLineDirtyDocument() {
        var doc = EdexTextDocument(path: "/a", text: "one")
        doc.text = "one two"
        XCTAssertTrue(doc.statusLine.contains("modified"))
    }

    // MARK: - Save-outcome status

    func testSavedStatusReportsByteCount() {
        let doc = EdexTextDocument(path: "/a", text: "hello")
        XCTAssertEqual(EdexTextEditorStatus.saved(doc), "Saved 5 Bytes to disk.")
    }

    func testFailedStatusIncludesError() {
        let message = EdexTextEditorStatus.failed("permission denied")
        XCTAssertTrue(message.contains("permission denied"))
        XCTAssertTrue(message.lowercased().contains("fail"))
    }
}

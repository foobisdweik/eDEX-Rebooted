import XCTest
@testable import ModalSupport
import AudioSupport

@MainActor
final class NativeModalTests: XCTestCase {
    func testPlainTextNormalizationMatchesLegacyNativeModalSanitizer() {
        XCTAssertEqual(
            EdexModalText.normalize("Line 1<br>Line 2<script>&amp;\u{0007}</script>"),
            "Line 1\nLine 2‹script›  ‹/script›"
        )
    }

    func testLegacyKindsMapToStyleZIndexAndAudioCues() throws {
        let info = try EdexModalRequest(type: "info", title: "Info", message: "Ready")
        XCTAssertEqual(info.kind, .info)
        XCTAssertEqual(info.zIndexBase, 500)
        XCTAssertEqual(info.openCue, .info)

        let custom = try EdexModalRequest(type: "custom", title: "Processes", message: "", content: .processList)
        XCTAssertEqual(custom.kind, .custom)
        XCTAssertEqual(custom.zIndexBase, 500)
        XCTAssertEqual(custom.openCue, .info)
        XCTAssertTrue(custom.detachesKeyboard)

        let warning = try EdexModalRequest(type: "warning", title: "Careful", message: "Warn")
        XCTAssertEqual(warning.kind, .warning)
        XCTAssertEqual(warning.zIndexBase, 1000)
        XCTAssertEqual(warning.openCue, .alarm)

        let error = try EdexModalRequest(type: "error", title: "Panic", message: "Boom")
        XCTAssertEqual(error.kind, .error)
        XCTAssertEqual(error.zIndexBase, 1500)
        XCTAssertEqual(error.openCue, .error)
    }

    func testMissingTypeThrowsInsteadOfCreatingAmbiguousModal() {
        XCTAssertThrowsError(try EdexModalRequest(type: "", title: "Nope", message: "Nope")) { error in
            XCTAssertEqual(error as? EdexModalError, .missingType)
        }
    }

    func testManagerAssignsUniqueIdsFocusZOrderAndCloseCallbacks() throws {
        let manager = EdexModalManager(idGenerator: EdexModalIdGenerator(seed: 10))
        var closed = [EdexModalID]()

        let first = manager.present(try .init(type: "info", title: "One", message: "First")) { closed.append($0) }
        let second = manager.present(try .init(type: "warning", title: "Two", message: "Second")) { closed.append($0) }

        XCTAssertEqual(manager.modals.map(\.id), [first, second])
        XCTAssertEqual(manager.focusedID, second)
        XCTAssertEqual(manager.modal(id: first)?.zIndex, 501)
        XCTAssertEqual(manager.modal(id: second)?.zIndex, 1002)

        manager.focus(first)
        XCTAssertEqual(manager.focusedID, first)
        XCTAssertGreaterThan(manager.modal(id: first)?.zIndex ?? 0, manager.modal(id: second)?.zIndex ?? 0)

        XCTAssertEqual(manager.close(first), .denied)
        XCTAssertEqual(closed, [first])
        XCTAssertNil(manager.modal(id: first))
        XCTAssertEqual(manager.focusedID, second)
    }

    func testKeyboardDetachesOnlyWhileKeyboardOwningModalsAreOpen() throws {
        let manager = EdexModalManager(idGenerator: EdexModalIdGenerator(seed: 20))
        let custom = manager.present(try .init(type: "custom", title: "Processes", message: "", content: .processList))
        let info = manager.present(try .init(type: "info", title: "PDF", message: "Deferred"))

        XCTAssertTrue(manager.isKeyboardDetached)
        XCTAssertEqual(manager.close(info), .denied)
        XCTAssertTrue(manager.isKeyboardDetached)
        XCTAssertEqual(manager.close(custom), .denied)
        XCTAssertFalse(manager.isKeyboardDetached)
    }

    func testFuzzyFinderModalContentIsAvailableForNativeSearch() throws {
        let request = try EdexModalRequest(
            type: "custom",
            title: "Fuzzy cwd file search",
            message: "",
            content: .fuzzyFinder
        )

        XCTAssertEqual(request.content, .fuzzyFinder)
        XCTAssertTrue(request.detachesKeyboard)
    }

    func testMoveUpdatesOnlyTheRequestedModalOffset() throws {
        let manager = EdexModalManager(idGenerator: EdexModalIdGenerator(seed: 30))
        let first = manager.present(try .init(type: "info", title: "One", message: "First"))
        let second = manager.present(try .init(type: "info", title: "Two", message: "Second"))

        manager.move(first, dx: 14, dy: -6)
        manager.move(EdexModalID("missing"), dx: 99, dy: 99)

        XCTAssertEqual(manager.modal(id: first)?.offsetX, 14)
        XCTAssertEqual(manager.modal(id: first)?.offsetY, -6)
        XCTAssertEqual(manager.modal(id: second)?.offsetX, 0)
        XCTAssertEqual(manager.modal(id: second)?.offsetY, 0)
    }
}

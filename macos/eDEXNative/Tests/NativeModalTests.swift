import XCTest
@testable import EdexDomainSupport

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

    func testModalLayoutSizeSanitizesNonFiniteAndNegativeDimensions() {
        let size = ModalLayoutSize(width: -.infinity, height: .nan)

        XCTAssertEqual(size.width, 0)
        XCTAssertEqual(size.height, 0)
    }

    func testModalLayoutRectSanitizesNonFiniteOriginsAndDimensions() {
        let rect = ModalLayoutRect(x: .nan, y: .infinity, width: -20, height: .greatestFiniteMagnitude)

        XCTAssertEqual(rect.x, 0)
        XCTAssertEqual(rect.y, 0)
        XCTAssertEqual(rect.width, 0)
        XCTAssertEqual(rect.height, .greatestFiniteMagnitude)
    }

    func testMoveIgnoresNonFiniteDeltas() throws {
        let manager = EdexModalManager(idGenerator: EdexModalIdGenerator(seed: 35))
        let id = manager.present(try .init(type: "info", title: "One", message: "First"))

        manager.move(id, dx: 14, dy: 6)
        manager.move(id, dx: .nan, dy: -.infinity)

        XCTAssertEqual(manager.modal(id: id)?.offsetX, 14)
        XCTAssertEqual(manager.modal(id: id)?.offsetY, 6)

        let viewport = ModalLayoutRect(x: 0, y: 0, width: 800, height: 600)
        manager.move(
            id,
            dx: .nan,
            dy: -.infinity,
            placement: .init(
                viewport: viewport,
                modalSize: ModalLayoutSize(width: 300, height: 160),
                reserved: []
            )
        )

        XCTAssertEqual(manager.modal(id: id)?.offsetX, 14)
        XCTAssertEqual(manager.modal(id: id)?.offsetY, 6)
    }

    func testModalPlacementKeepsRectInsideViewport() {
        let viewport = ModalLayoutRect(x: 0, y: 0, width: 800, height: 600)
        let proposed = ModalLayoutRect(x: 700, y: 540, width: 200, height: 120)

        let result = ModalPlacement.place(proposed: proposed, viewport: viewport, reserved: [], existing: [])

        XCTAssertEqual(result.rect, ModalLayoutRect(x: 600, y: 480, width: 200, height: 120))
        XCTAssertEqual(result.status, .clamped)
    }

    func testModalPlacementAvoidsReservedRects() {
        let viewport = ModalLayoutRect(x: 0, y: 0, width: 1000, height: 700)
        let terminal = ModalLayoutRect(x: 250, y: 120, width: 500, height: 300)
        let proposed = ModalLayoutRect(x: 350, y: 180, width: 260, height: 180)

        let result = ModalPlacement.place(proposed: proposed, viewport: viewport, reserved: [terminal], existing: [])

        XCTAssertFalse(result.rect.intersects(terminal))
    }

    func testModalPlacementAvoidsExistingModalRects() {
        let viewport = ModalLayoutRect(x: 0, y: 0, width: 900, height: 600)
        let existing = ModalLayoutRect(x: 300, y: 200, width: 260, height: 180)
        let proposed = ModalLayoutRect(x: 320, y: 220, width: 260, height: 180)

        let result = ModalPlacement.place(proposed: proposed, viewport: viewport, reserved: [], existing: [existing])

        XCTAssertFalse(result.rect.intersects(existing))
    }

    func testModalPlacementDegradedFallbackMinimizesOverlapInsteadOfReturningProposed() {
        let viewport = ModalLayoutRect(x: 0, y: 0, width: 300, height: 220)
        let blocker = ModalLayoutRect(x: 0, y: 0, width: 220, height: 220)
        let proposed = ModalLayoutRect(x: 40, y: 20, width: 160, height: 140)

        let result = ModalPlacement.place(proposed: proposed, viewport: viewport, reserved: [blocker], existing: [])

        XCTAssertEqual(result.status, .degraded)
        XCTAssertNotEqual(result.rect, proposed)
        XCTAssertLessThan(result.rect.overlapArea(with: blocker), proposed.overlapArea(with: blocker))
    }

    func testManagerCanApplyPlacementAwareMove() throws {
        let manager = EdexModalManager(idGenerator: EdexModalIdGenerator(seed: 40))
        let id = manager.present(try .init(type: "info", title: "One", message: "First"))
        let viewport = ModalLayoutRect(x: 0, y: 0, width: 800, height: 600)

        manager.move(
            id,
            dx: 500,
            dy: 500,
            placement: .init(viewport: viewport, modalSize: ModalLayoutSize(width: 300, height: 160), reserved: [])
        )

        let modal = try XCTUnwrap(manager.modal(id: id))
        XCTAssertLessThanOrEqual(modal.offsetX, 250)
        XCTAssertLessThanOrEqual(modal.offsetY, 220)
    }
}

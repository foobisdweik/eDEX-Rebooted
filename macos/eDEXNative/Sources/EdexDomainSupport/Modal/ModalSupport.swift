import Foundation
import Observation

public enum EdexModalKind: String, Equatable, Sendable {
    case info
    case warning
    case error
    case custom

    public init(legacyType: String) throws {
        let normalized = legacyType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            throw EdexModalError.missingType
        }

        switch normalized {
        case "error":
            self = .error
        case "warning":
            self = .warning
        case "custom":
            self = .custom
        default:
            self = .info
        }
    }
}

public enum EdexModalError: Error, Equatable, Sendable {
    case missingType
    case unknownModalID
}

public enum EdexModalContent: Equatable, Sendable {
    case message
    case processList
    case settingsEditor
    case shortcuts
    case textEditor
    case fuzzyFinder
    case mediaViewer
    case customPlaceholder
}

public enum EdexModalText {
    public static func normalize(_ value: String?) -> String {
        let withLineBreaks = (value ?? "").replacing(
            #/<br\s*\/?>/#,
            with: "\n"
        )

        let scalarFiltered = String(String.UnicodeScalarView(withLineBreaks.unicodeScalars.map { scalar in
            if scalar.value < 0x20 || scalar.value == 0x7F {
                return scalar == "\n" || scalar == "\t" ? scalar : " "
            }
            return scalar
        }))

        return scalarFiltered
            .replacingOccurrences(of: "<", with: "‹")
            .replacingOccurrences(of: ">", with: "›")
            .replacing(#/&(?:#(?:x[0-9a-fA-F]+|\d+)|[a-zA-Z][a-zA-Z0-9]+);/#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct EdexModalRequest: Equatable, Sendable {
    public let kind: EdexModalKind
    public let title: String
    public let message: String
    public let content: EdexModalContent
    public let detachesKeyboard: Bool

    public init(
        type: String,
        title: String?,
        message: String?,
        content: EdexModalContent = .message,
        detachesKeyboard: Bool? = nil
    ) throws {
        let kind = try EdexModalKind(legacyType: type)
        self.kind = kind
        self.title = EdexModalText.normalize(title?.isEmpty == false ? title : type)
        self.message = EdexModalText.normalize(message?.isEmpty == false ? message : "Lorem ipsum dolor sit amet.")
        self.content = content
        self.detachesKeyboard = detachesKeyboard ?? (kind == .custom)
    }

    public var zIndexBase: Int {
        switch kind {
        case .error:
            1500
        case .warning:
            1000
        case .info, .custom:
            500
        }
    }

    public var openCue: EdexAudioCue {
        switch kind {
        case .error:
            .error
        case .warning:
            .alarm
        case .info, .custom:
            .info
        }
    }
}

public struct EdexModalID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public struct EdexModalIdGenerator: Sendable {
    private var nextValue: Int

    public init(seed: Int = 1) {
        nextValue = max(1, seed)
    }

    public mutating func next() -> EdexModalID {
        defer { nextValue += 1 }
        return EdexModalID("modal-\(nextValue)")
    }
}

public struct EdexModalRecord: Equatable, Sendable {
    public let id: EdexModalID
    public var request: EdexModalRequest
    public var zIndex: Int
    public var offsetX: Double
    public var offsetY: Double

    public var kind: EdexModalKind { request.kind }
    public var title: String { request.title }
    public var message: String { request.message }
    public var content: EdexModalContent { request.content }
    public var detachesKeyboard: Bool { request.detachesKeyboard }
}

public struct ModalLayoutSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width.isFinite ? max(0, width) : 0
        self.height = height.isFinite ? max(0, height) : 0
    }
}

public struct ModalLayoutRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x.isFinite ? x : 0
        self.y = y.isFinite ? y : 0
        self.width = width.isFinite ? max(0, width) : 0
        self.height = height.isFinite ? max(0, height) : 0
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func intersects(_ other: ModalLayoutRect) -> Bool {
        x < other.maxX && maxX > other.x && y < other.maxY && maxY > other.y
    }

    public func overlapArea(with other: ModalLayoutRect) -> Double {
        guard intersects(other) else { return 0 }
        let overlapWidth = max(0, min(maxX, other.maxX) - max(x, other.x))
        let overlapHeight = max(0, min(maxY, other.maxY) - max(y, other.y))
        return overlapWidth * overlapHeight
    }

    public func clamped(to viewport: ModalLayoutRect) -> ModalLayoutRect {
        let minX = viewport.x
        let minY = viewport.y
        let maxX = max(minX, viewport.maxX - width)
        let maxY = max(minY, viewport.maxY - height)

        return ModalLayoutRect(
            x: Swift.min(Swift.max(x, minX), maxX),
            y: Swift.min(Swift.max(y, minY), maxY),
            width: width,
            height: height
        )
    }
}

public enum ModalPlacementStatus: Equatable, Sendable {
    case placed
    case clamped
    case degraded
}

public struct ModalPlacementResult: Equatable, Sendable {
    public let rect: ModalLayoutRect
    public let status: ModalPlacementStatus

    public init(rect: ModalLayoutRect, status: ModalPlacementStatus) {
        self.rect = rect
        self.status = status
    }
}

public struct ModalPlacementContext: Equatable, Sendable {
    public let viewport: ModalLayoutRect
    public let modalSize: ModalLayoutSize
    public let reserved: [ModalLayoutRect]
    public let existing: [ModalLayoutRect]

    public init(
        viewport: ModalLayoutRect,
        modalSize: ModalLayoutSize,
        reserved: [ModalLayoutRect],
        existing: [ModalLayoutRect] = []
    ) {
        self.viewport = viewport
        self.modalSize = modalSize
        self.reserved = reserved
        self.existing = existing
    }
}

public enum ModalPlacement {
    public static func place(
        proposed: ModalLayoutRect,
        viewport: ModalLayoutRect,
        reserved: [ModalLayoutRect],
        existing: [ModalLayoutRect]
    ) -> ModalPlacementResult {
        let blockers = reserved + existing
        let clamped = proposed.clamped(to: viewport)
        let wasClamped = clamped != proposed

        guard clamped.intersectingBlockers(in: blockers).isEmpty else {
            return placeAroundBlockers(
                startingFrom: clamped,
                proposedWasClamped: wasClamped,
                viewport: viewport,
                blockers: blockers
            )
        }

        return ModalPlacementResult(rect: clamped, status: wasClamped ? .clamped : .placed)
    }

    private static func placeAroundBlockers(
        startingFrom proposed: ModalLayoutRect,
        proposedWasClamped: Bool,
        viewport: ModalLayoutRect,
        blockers: [ModalLayoutRect]
    ) -> ModalPlacementResult {
        let candidates = candidateRects(around: proposed, viewport: viewport, blockers: blockers)

        for candidate in candidates {
            let clampedCandidate = candidate.clamped(to: viewport)
            if clampedCandidate.intersectingBlockers(in: blockers).isEmpty {
                let status: ModalPlacementStatus = proposedWasClamped || clampedCandidate != candidate ? .clamped : .placed
                return ModalPlacementResult(rect: clampedCandidate, status: status)
            }
        }

        return ModalPlacementResult(
            rect: leastOverlapping(candidates: candidates, proposed: proposed, viewport: viewport, blockers: blockers),
            status: .degraded
        )
    }

    private static func candidateRects(
        around proposed: ModalLayoutRect,
        viewport: ModalLayoutRect,
        blockers: [ModalLayoutRect]
    ) -> [ModalLayoutRect] {
        var candidates = [
            proposed,
            ModalLayoutRect(x: viewport.x, y: viewport.y, width: proposed.width, height: proposed.height),
            ModalLayoutRect(x: viewport.maxX - proposed.width, y: viewport.y, width: proposed.width, height: proposed.height),
            ModalLayoutRect(x: viewport.x, y: viewport.maxY - proposed.height, width: proposed.width, height: proposed.height),
            ModalLayoutRect(x: viewport.maxX - proposed.width, y: viewport.maxY - proposed.height, width: proposed.width, height: proposed.height)
        ]

        for blocker in proposed.intersectingBlockers(in: blockers) {
            candidates.append(contentsOf: [
                ModalLayoutRect(x: proposed.x, y: blocker.y - proposed.height, width: proposed.width, height: proposed.height),
                ModalLayoutRect(x: proposed.x, y: blocker.maxY, width: proposed.width, height: proposed.height),
                ModalLayoutRect(x: blocker.x - proposed.width, y: proposed.y, width: proposed.width, height: proposed.height),
                ModalLayoutRect(x: blocker.maxX, y: proposed.y, width: proposed.width, height: proposed.height)
            ])
        }

        return candidates
    }

    private static func leastOverlapping(
        candidates: [ModalLayoutRect],
        proposed: ModalLayoutRect,
        viewport: ModalLayoutRect,
        blockers: [ModalLayoutRect]
    ) -> ModalLayoutRect {
        let clampedCandidates = candidates.map { $0.clamped(to: viewport) }
        return clampedCandidates.min { lhs, rhs in
            let lhsOverlap = lhs.totalOverlap(with: blockers)
            let rhsOverlap = rhs.totalOverlap(with: blockers)
            if lhsOverlap != rhsOverlap {
                return lhsOverlap < rhsOverlap
            }
            return lhs.distanceSquared(to: proposed) < rhs.distanceSquared(to: proposed)
        } ?? proposed.clamped(to: viewport)
    }
}

private extension ModalLayoutRect {
    func intersectingBlockers(in blockers: [ModalLayoutRect]) -> [ModalLayoutRect] {
        blockers.filter { intersects($0) }
    }

    func totalOverlap(with blockers: [ModalLayoutRect]) -> Double {
        blockers.reduce(0) { $0 + overlapArea(with: $1) }
    }

    func distanceSquared(to other: ModalLayoutRect) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx) + (dy * dy)
    }
}

@Observable
@MainActor
public final class EdexModalManager {
    public private(set) var modals = [EdexModalRecord]()
    public private(set) var focusedID: EdexModalID?

    private var idGenerator: EdexModalIdGenerator
    private var focusCounter = 0
    private var callbacks = [EdexModalID: (EdexModalID) -> Void]()

    public init(idGenerator: EdexModalIdGenerator = EdexModalIdGenerator()) {
        self.idGenerator = idGenerator
    }

    public var isKeyboardDetached: Bool {
        modals.contains { $0.detachesKeyboard }
    }

    @discardableResult
    public func present(_ request: EdexModalRequest, onClose: ((EdexModalID) -> Void)? = nil) -> EdexModalID {
        let id = idGenerator.next()
        focusCounter += 1
        let record = EdexModalRecord(
            id: id,
            request: request,
            zIndex: request.zIndexBase + focusCounter,
            offsetX: 0,
            offsetY: 0
        )
        modals.append(record)
        callbacks[id] = onClose
        focusedID = id
        return id
    }

    public func modal(id: EdexModalID) -> EdexModalRecord? {
        modals.first { $0.id == id }
    }

    public func focus(_ id: EdexModalID) {
        guard let index = modals.firstIndex(where: { $0.id == id }) else { return }
        let nextZIndex = (modals.map(\.zIndex).max() ?? modals[index].request.zIndexBase) + 1
        modals[index].zIndex = nextZIndex
        focusedID = id
    }

    public func move(_ id: EdexModalID, dx: Double, dy: Double) {
        guard let index = modals.firstIndex(where: { $0.id == id }) else { return }
        let safeDX = dx.isFinite ? dx : 0
        let safeDY = dy.isFinite ? dy : 0
        modals[index].offsetX += safeDX
        modals[index].offsetY += safeDY
    }

    public func move(_ id: EdexModalID, dx: Double, dy: Double, placement: ModalPlacementContext) {
        guard let index = modals.firstIndex(where: { $0.id == id }) else { return }
        let safeDX = dx.isFinite ? dx : 0
        let safeDY = dy.isFinite ? dy : 0
        let centeredOrigin = ModalLayoutRect.centeredOrigin(
            size: placement.modalSize,
            in: placement.viewport
        )
        let proposed = ModalLayoutRect(
            x: centeredOrigin.x + modals[index].offsetX + safeDX,
            y: centeredOrigin.y + modals[index].offsetY + safeDY,
            width: placement.modalSize.width,
            height: placement.modalSize.height
        )
        let placed = ModalPlacement.place(
            proposed: proposed,
            viewport: placement.viewport,
            reserved: placement.reserved,
            existing: placement.existing
        ).rect

        modals[index].offsetX = placed.x - centeredOrigin.x
        modals[index].offsetY = placed.y - centeredOrigin.y
    }

    @discardableResult
    public func close(_ id: EdexModalID) -> EdexAudioCue? {
        guard let index = modals.firstIndex(where: { $0.id == id }) else { return nil }
        modals.remove(at: index)
        let callback = callbacks.removeValue(forKey: id)
        callback?(id)

        if focusedID == id {
            focusedID = modals.max(by: { $0.zIndex < $1.zIndex })?.id
        }

        return .denied
    }
}

private extension ModalLayoutRect {
    static func centeredOrigin(size: ModalLayoutSize, in viewport: ModalLayoutRect) -> ModalLayoutRect {
        ModalLayoutRect(
            x: viewport.x + (viewport.width - size.width) / 2,
            y: viewport.y + (viewport.height - size.height) / 2,
            width: 0,
            height: 0
        )
    }
}

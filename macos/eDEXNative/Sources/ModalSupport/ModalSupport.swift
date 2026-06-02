import AudioSupport
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

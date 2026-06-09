import Foundation
import Observation

@MainActor
public protocol TerminalSessionProviding: AnyObject {
    var activeCwd: String { get }
    var activeTab: Int { get }

    func sendInput(_ text: String)
    func switchTab(_ index: Int)
}

@Observable
@MainActor
public final class StubTerminalStore: TerminalSessionProviding {
    public private(set) var activeCwd: String
    public private(set) var activeTab: Int
    public private(set) var sentInputs: [String]

    public init(activeCwd: String = NSHomeDirectory(), activeTab: Int = 0, sentInputs: [String] = []) {
        self.activeCwd = activeCwd
        self.activeTab = activeTab
        self.sentInputs = sentInputs
    }

    public func sendInput(_ text: String) {
        sentInputs.append(text)
    }

    public func switchTab(_ index: Int) {
        activeTab = index
    }
}

public enum EdexAction: Equatable, Sendable {
    case keyboardInput(String)
    case openSettings
    case openFuzzyFinder
    case switchTerminal(Int)
    case closeModal
}

@MainActor
public protocol EdexActionHandler {
    func handle(_ action: EdexAction)
}

@MainActor
public struct EdexActionRouter: EdexActionHandler {
    private let terminal: TerminalSessionProviding
    private let openSettings: () -> Void
    private let openFuzzyFinder: () -> Void
    private let closeModal: () -> Void

    public init(
        terminal: TerminalSessionProviding,
        openSettings: @escaping () -> Void,
        openFuzzyFinder: @escaping () -> Void,
        closeModal: @escaping () -> Void
    ) {
        self.terminal = terminal
        self.openSettings = openSettings
        self.openFuzzyFinder = openFuzzyFinder
        self.closeModal = closeModal
    }

    public func handle(_ action: EdexAction) {
        switch action {
        case let .keyboardInput(text):
            terminal.sendInput(text)
        case .openSettings:
            openSettings()
        case .openFuzzyFinder:
            openFuzzyFinder()
        case let .switchTerminal(index):
            terminal.switchTab(index)
        case .closeModal:
            closeModal()
        }
    }
}

@Observable
@MainActor
public final class KeyboardStore {
    public var layout: NativeKeyboardLayout?
    public var status: String
    public var modifiers: KeyboardModifierState
    public var pressedKeyIDs: Set<String>

    public init(
        layout: NativeKeyboardLayout? = nil,
        status: String = "keyboard layout not loaded",
        modifiers: KeyboardModifierState = KeyboardModifierState(),
        pressedKeyIDs: Set<String> = []
    ) {
        self.layout = layout
        self.status = status
        self.modifiers = modifiers
        self.pressedKeyIDs = pressedKeyIDs
    }

    public func toggleModifier(_ modifier: KeyboardModifier) {
        modifiers.toggle(modifier)
    }

    public func pressVisual(id: String, clearAfterNanoseconds: UInt64 = 120_000_000) {
        pressedKeyIDs.insert(id)
        Task { @MainActor [weak self] in
            let delay = min(clearAfterNanoseconds, UInt64(Int64.max))
            try? await Task.sleep(for: .nanoseconds(Int64(delay)))
            self?.pressedKeyIDs.remove(id)
        }
    }
}

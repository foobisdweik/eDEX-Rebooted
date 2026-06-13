import Foundation
import Observation

@MainActor
public protocol TerminalSessionProviding: AnyObject {
    var activeCwd: String { get }
    var activeTab: Int { get }
    var aliveTabs: Set<Int> { get }
    /// Kill the shell in tab `index` (CLOSE affordance). The slot stays and
    /// shows a restart notice; the next keystroke respawns it.
    func closeTab(_ index: Int)

    func sendInput(_ text: String)
    func switchTab(_ index: Int)
    /// Move to the next tab, wrapping past the last (NEXT_TAB shortcut).
    func selectNextTab()
    /// Move to the previous tab, wrapping past the first (PREVIOUS_TAB shortcut).
    func selectPreviousTab()
    /// Copy the active terminal's selection to the system clipboard (COPY).
    func copySelection()
    /// Paste the clipboard into the active terminal as input (PASTE).
    func pasteClipboard()
}

@Observable
@MainActor
public final class StubTerminalStore: TerminalSessionProviding {
    public private(set) var activeCwd: String
    public private(set) var tabs: TerminalTabSet
    public private(set) var sentInputs: [String]
    public private(set) var copyCount = 0
    public private(set) var pasteCount = 0
    public private(set) var aliveTabs: Set<Int> = []
    /// Tabs closed via `closeTab`, in call order (router-forwarding assertions).
    public private(set) var closedTabs: [Int] = []

    public var activeTab: Int { tabs.active }

    public init(
        activeCwd: String = NSHomeDirectory(),
        activeTab: Int = 0,
        sentInputs: [String] = [],
        tabCount: Int = 5
    ) {
        self.activeCwd = activeCwd
        self.tabs = TerminalTabSet(count: tabCount, active: activeTab)
        self.sentInputs = sentInputs
    }

    public func sendInput(_ text: String) {
        sentInputs.append(text)
    }

    public func switchTab(_ index: Int) {
        tabs.select(index)
    }

    public func selectNextTab() {
        tabs.selectNext()
    }

    public func selectPreviousTab() {
        tabs.selectPrevious()
    }

    public func copySelection() {
        copyCount += 1
    }

    public func pasteClipboard() {
        pasteCount += 1
    }

    public func closeTab(_ index: Int) {
        closedTabs.append(index)
        aliveTabs.remove(index)
    }
}

public enum EdexAction: Equatable, Sendable {
    case keyboardInput(String)
    case openSettings
    case openFuzzyFinder
    case switchTerminal(Int)
    case closeTerminal(Int)
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
        case let .closeTerminal(index):
            terminal.closeTab(index)
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
    private var heldKeyIDs: Set<String> = []
    private var visualClearTasks: [String: Task<Void, Never>] = [:]
    /// The dead key armed by the last diacritic press; the next key composes
    /// against it (Phase 8.3). nil when no diacritic is pending.
    public var armedDeadKey: DeadKey?

    public init(
        layout: NativeKeyboardLayout? = nil,
        status: String = "keyboard layout not loaded",
        modifiers: KeyboardModifierState = KeyboardModifierState(),
        pressedKeyIDs: Set<String> = [],
        armedDeadKey: DeadKey? = nil
    ) {
        self.layout = layout
        self.status = status
        self.modifiers = modifiers
        self.pressedKeyIDs = pressedKeyIDs
        self.armedDeadKey = armedDeadKey
    }

    public func toggleModifier(_ modifier: KeyboardModifier) {
        modifiers.toggle(modifier)
    }

    public func pressVisual(id: String, clearAfterNanoseconds: UInt64 = 120_000_000) {
        visualClearTasks[id]?.cancel()
        pressedKeyIDs.insert(id)
        visualClearTasks[id] = Task { @MainActor [weak self] in
            let delay = min(clearAfterNanoseconds, UInt64(Int64.max))
            try? await Task.sleep(for: .nanoseconds(Int64(delay)))
            guard !Task.isCancelled else { return }
            self?.visualClearTasks[id] = nil
            guard self?.heldKeyIDs.contains(id) != true else { return }
            self?.pressedKeyIDs.remove(id)
        }
    }

    public func holdVisual(id: String) {
        visualClearTasks[id]?.cancel()
        visualClearTasks[id] = nil
        heldKeyIDs.insert(id)
        pressedKeyIDs.insert(id)
    }

    public func releaseVisual(id: String) {
        heldKeyIDs.remove(id)
        pressedKeyIDs.remove(id)
    }

    // Finding #3 (List 3): cache the per-layout descriptor index so the event
    // monitor's per-keystroke lookups and the keyboard panel's render reuse one
    // build instead of rebuilding the ~80-key matrix every time. Rebuilt when
    // the layout value changes (same basename can reload edited JSON);
    // `@ObservationIgnored` so the cache fill never triggers a view update.
    @ObservationIgnored private var cachedDescriptorIndex: KeyboardDescriptorIndex?
    @ObservationIgnored private var cachedDescriptorIndexLayout: NativeKeyboardLayout?

    public var descriptorIndex: KeyboardDescriptorIndex? {
        guard let layout else {
            cachedDescriptorIndex = nil
            cachedDescriptorIndexLayout = nil
            return nil
        }
        if cachedDescriptorIndexLayout != layout || cachedDescriptorIndex == nil {
            cachedDescriptorIndex = KeyboardDescriptorIndex(layout: layout)
            cachedDescriptorIndexLayout = layout
        }
        return cachedDescriptorIndex
    }

    public func descriptorID(for combo: KeyCombo) -> String? {
        descriptorIndex?.id(for: combo)
    }

    public func descriptorID(for modifier: KeyboardModifier) -> String? {
        descriptorIndex?.id(for: modifier)
    }

    public func descriptorID(for physicalModifier: KeyboardPhysicalModifier) -> String? {
        descriptorIndex?.id(for: physicalModifier)
    }
}

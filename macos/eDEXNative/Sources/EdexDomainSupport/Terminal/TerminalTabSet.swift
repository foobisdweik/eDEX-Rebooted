import Foundation

/// Pure model of the five-tab terminal selector: which tab is active and how
/// selection moves. The legacy on-screen tabs wrap (NEXT_TAB past the last tab
/// returns to the first); out-of-range selections are ignored rather than
/// clamped so a stray shortcut index can't silently retarget a different tab.
public struct TerminalTabSet: Equatable, Sendable {
    public let count: Int
    public private(set) var active: Int

    public init(count: Int = 5, active: Int = 0) {
        precondition(count >= 1, "a terminal tab set needs at least one tab")
        self.count = count
        self.active = Self.clamp(active, count: count)
    }

    /// Valid tab range for this set.
    public var indices: Range<Int> { 0..<count }

    /// Returns `index` if it addresses a real tab, otherwise nil.
    public func valid(_ index: Int) -> Int? {
        indices.contains(index) ? index : nil
    }

    /// Selects an explicit tab. Out-of-range indices are ignored (no-op) so a
    /// bad shortcut payload can't move the selection somewhere unexpected.
    public mutating func select(_ index: Int) {
        guard let index = valid(index) else { return }
        active = index
    }

    /// Advances to the next tab, wrapping past the last back to the first.
    public mutating func selectNext() {
        active = (active + 1) % count
    }

    /// Steps to the previous tab, wrapping past the first to the last.
    public mutating func selectPrevious() {
        active = (active - 1 + count) % count
    }

    private static func clamp(_ index: Int, count: Int) -> Int {
        min(max(index, 0), count - 1)
    }
}

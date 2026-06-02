import Foundation

/// The colour tier of one dot in the memory grid.
public enum RamCellState: Equatable, Sendable {
    case active
    case available
    case free
}

/// Pure logic for the native ramwatcher panel — the 440-dot grid partition, the
/// "USING x OUT OF y GiB" header, and the swap bar/text — mirroring
/// `src/classes/ramwatcher.class.js`. FFI-free so it unit-tests without the Rust
/// dylib. The grid shuffle and rendering live in the view.
public struct EdexRamwatcherFormatter: Sendable {
    /// 40 columns × 11 rows.
    public static let gridCellCount = 440

    /// 1 Gibibyte in bytes, per the legacy's literal divisor.
    private static let bytesPerGiB = 1_073_742_000.0

    public init() {}

    /// `round(440 * active / total)` — the count of "active" dots.
    public func activeCount(active: UInt64, total: UInt64) -> Int {
        scaledCount(numerator: Double(active), total: total)
    }

    /// `round(440 * (available - free) / total)` — the count of "available"
    /// (cached/reclaimable) dots. `available - free` is clamped at 0.
    public func availableCount(available: UInt64, free: UInt64, total: UInt64) -> Int {
        let delta = max(0, Double(available) - Double(free))
        return scaledCount(numerator: delta, total: total)
    }

    /// The tier for a dot at the given shuffled rank: the first `activeCount`
    /// ranks are active, the next `availableCount` are available, the rest free.
    public func cellState(rank: Int, activeCount: Int, availableCount: Int) -> RamCellState {
        if rank < activeCount { return .active }
        if rank < activeCount + availableCount { return .available }
        return .free
    }

    /// MEMORY header: `USING {activeGiB} OUT OF {totalGiB} GiB`.
    public func infoText(active: UInt64, total: UInt64) -> String {
        "USING \(gibText(active)) OUT OF \(gibText(total)) GiB"
    }

    /// SWAP progress value 0–100: `round(100 * used / total)`, 0 when no swap.
    public func swapPercent(used: UInt64, total: UInt64) -> Int {
        guard total > 0 else { return 0 }
        return Self.safeInt((100.0 * Double(used) / Double(total)).rounded()) ?? 0
    }

    /// SWAP caption: `{usedGiB} GiB`.
    public func swapText(used: UInt64) -> String {
        "\(gibText(used)) GiB"
    }

    private func scaledCount(numerator: Double, total: UInt64) -> Int {
        guard total > 0 else { return 0 }
        return Self.safeInt((Double(Self.gridCellCount) * numerator / Double(total)).rounded()) ?? 0
    }

    /// Bytes → GiB rounded to one decimal, JS-style (whole numbers drop `.0`).
    private func gibText(_ bytes: UInt64) -> String {
        let gib = (Double(bytes) / Self.bytesPerGiB * 10).rounded() / 10
        if let whole = Self.safeInt(gib), Double(whole) == gib { return String(whole) }
        return String(gib)
    }

    /// Safe `Double` → `Int`: `nil` if non-finite or outside `Int`'s range, so a
    /// garbage memory reading can't crash the cast.
    private static func safeInt(_ value: Double) -> Int? {
        guard value.isFinite, value >= Double(Int.min), value <= Double(Int.max) else { return nil }
        return Int(value)
    }
}

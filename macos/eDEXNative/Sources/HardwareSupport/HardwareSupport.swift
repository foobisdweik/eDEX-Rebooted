import Foundation

/// Formats the three hardware-inspector cells (manufacturer / model / chassis)
/// to match the legacy `src/classes/hardwareInspector.class.js` exactly,
/// including its `_trimDataString` word-filtering. Pure and FFI-free so it can
/// be unit-tested without the Rust dylib, mirroring `SysinfoSupport`.
public struct EdexHardwareFormatter: Sendable {
    public init() {}

    public func format(manufacturer: String, model: String, chassisType: String) -> EdexHardwareInfo {
        EdexHardwareInfo(
            // No filters → first two space-split words.
            manufacturer: trim(manufacturer, filters: []),
            // Strip any word equal to the manufacturer or chassis-type string,
            // then keep the first two words.
            model: trim(model, filters: [manufacturer, chassisType]),
            // CHASSIS is used raw — no trimming.
            chassis: chassisType
        )
    }

    /// Port of `_trimDataString`: trim, split on a single space (keeping empty
    /// substrings, like JS `String.split(" ")`), drop words present in `filters`,
    /// keep the first two, rejoin with a space.
    private func trim(_ value: String, filters: [String]) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: " ")
            .filter { !filters.contains($0) }
            .prefix(2)
            .joined(separator: " ")
    }
}

public struct EdexHardwareInfo: Equatable, Sendable {
    public let manufacturer: String
    public let model: String
    public let chassis: String

    public init(manufacturer: String, model: String, chassis: String) {
        self.manufacturer = manufacturer
        self.model = model
        self.chassis = chassis
    }
}

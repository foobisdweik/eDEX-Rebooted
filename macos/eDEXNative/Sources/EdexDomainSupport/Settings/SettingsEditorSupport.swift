import Foundation

// Phase 6.3 settings editor — pure, FFI-free support module.
//
// Replaces the legacy `renderer.js` settings modal. The legacy modal rebuilt the
// settings object from scratch on save, silently dropping any key it did not know
// about. This native port instead keeps the full parsed document and overlays only
// the edited keys, so `forceFullscreen`, `port`, and the `experimental*` flags
// survive a save round-trip (a deliberate robustness improvement over legacy).

/// A minimal JSON value model so the full settings document round-trips losslessly,
/// including keys the editor does not surface.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(foundation object: Any) {
        switch object {
        case is NSNull:
            self = .null
        case let num as NSNumber:
            // JSONSerialization yields NSNumber for both booleans and numbers;
            // distinguish booleans by their CoreFoundation type id.
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                self = .bool(num.boolValue)
            } else {
                self = .number(num.doubleValue)
            }
        case let str as String:
            self = .string(str)
        case let arr as [Any]:
            self = .array(arr.map(JSONValue.init(foundation:)))
        case let obj as [String: Any]:
            self = .object(obj.mapValues(JSONValue.init(foundation:)))
        default:
            self = .null
        }
    }

    var foundationObject: Any {
        switch self {
        case .null: return NSNull()
        case let .bool(value): return value
        case let .number(value): return value
        case let .string(value): return value
        case let .array(values): return values.map(\.foundationObject)
        case let .object(values): return values.mapValues(\.foundationObject)
        }
    }
}

public enum EdexSettingsKey: String, CaseIterable, Sendable {
    case shell, shellArgs, cwd, username, keyboard, theme, termFontSize
    case audio, audioVolume, disableFeedbackAudio, pingAddr, clockHours, monitor
    case nointro, nocursor, iface, allowWindowed, keepGeometry
    case excludeThreadsFromToplist, hideDotfiles, fsListView
}

public enum EdexSettingsControl: Equatable, Sendable {
    case text
    case integer
    case decimal
    case toggle
    /// Fixed option set. Dynamic option sets (theme/keyboard) use an empty list
    /// here; the view fills options from the FFI listings at present time.
    case choice([String])
}

public struct EdexSettingsField: Equatable, Sendable, Identifiable {
    public let key: EdexSettingsKey
    public let label: String
    public let help: String
    public let control: EdexSettingsControl

    public var id: String { key.rawValue }

    public static let all: [EdexSettingsField] = [
        .init(key: .shell, label: "shell", help: "The program to run as a terminal emulator", control: .text),
        .init(key: .shellArgs, label: "shellArgs", help: "Shell args (whitespace-separated, e.g. --login -i)", control: .text),
        .init(key: .cwd, label: "cwd", help: "Working directory to start in", control: .text),
        .init(key: .username, label: "username", help: "Custom username to display at boot", control: .text),
        .init(key: .keyboard, label: "keyboard", help: "On-screen keyboard layout code", control: .choice([])),
        .init(key: .theme, label: "theme", help: "Name of the theme to load", control: .choice([])),
        .init(key: .termFontSize, label: "termFontSize", help: "Size of the terminal text in pixels", control: .integer),
        .init(key: .audio, label: "audio", help: "Activate audio sound effects", control: .toggle),
        .init(key: .audioVolume, label: "audioVolume", help: "Default volume for sound effects (0.0 – 1.0)", control: .decimal),
        .init(key: .disableFeedbackAudio, label: "disableFeedbackAudio", help: "Disable recurring feedback sound FX", control: .toggle),
        .init(key: .pingAddr, label: "pingAddr", help: "IPv4 address to test Internet connectivity", control: .text),
        .init(key: .clockHours, label: "clockHours", help: "Clock format (12 / 24 hours)", control: .choice(["24", "12"])),
        .init(key: .monitor, label: "monitor", help: "Which monitor to spawn the UI in", control: .integer),
        .init(key: .nointro, label: "nointro", help: "Skip the intro boot log and logo", control: .toggle),
        .init(key: .nocursor, label: "nocursor", help: "Hide the mouse cursor", control: .toggle),
        .init(key: .iface, label: "iface", help: "Network interface for monitoring (Netstat deferred to v0.2; setting persists)", control: .text),
        .init(key: .allowWindowed, label: "allowWindowed", help: "Allow F11 to enter windowed mode", control: .toggle),
        .init(key: .keepGeometry, label: "keepGeometry", help: "Keep 16:10 aspect ratio in windowed mode", control: .toggle),
        .init(key: .excludeThreadsFromToplist, label: "excludeThreadsFromToplist", help: "Collapse threads in the top processes list", control: .toggle),
        .init(key: .hideDotfiles, label: "hideDotfiles", help: "Hide files starting with a dot", control: .toggle),
        .init(key: .fsListView, label: "fsListView", help: "Show files in a detailed list", control: .toggle),
    ]
}

public struct EdexSettingsDocument: Equatable, Sendable {
    public private(set) var raw: [String: JSONValue]

    /// Defaults mirror `edex_core::settings::default_settings` for the editable keys.
    private static let defaults: [EdexSettingsKey: JSONValue] = [
        .shell: .string("zsh"),
        .shellArgs: .string(""),
        .cwd: .string(""),
        .username: .string(""),
        .keyboard: .string("en-US"),
        .theme: .string("tron"),
        .termFontSize: .number(15),
        .audio: .bool(true),
        .audioVolume: .number(1.0),
        .disableFeedbackAudio: .bool(false),
        .pingAddr: .string("1.1.1.1"),
        .clockHours: .number(24),
        .monitor: .number(0),
        .nointro: .bool(false),
        .nocursor: .bool(false),
        .iface: .string(""),
        .allowWindowed: .bool(true),
        .keepGeometry: .bool(true),
        .excludeThreadsFromToplist: .bool(true),
        .hideDotfiles: .bool(false),
        .fsListView: .bool(false),
    ]

    /// Reboot-sensitive keys (legacy `writeSettingsFile` order). `forceFullscreen`
    /// is reboot-sensitive but not editor-surfaced; it is still diffed from `raw`.
    public static let rebootKeys = [
        "shell", "shellArgs", "cwd", "username", "monitor",
        "nointro", "forceFullscreen", "allowWindowed", "keepGeometry", "theme", "keyboard",
    ]

    /// An empty document (all editable keys resolve to their canonical defaults).
    public init() {
        raw = [:]
    }

    public init(jsonString: String) throws {
        let data = Data(jsonString.utf8)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        // A valid-but-non-object top level (array/scalar) is a structural error,
        // not an empty document — surface it so callers don't silently overwrite
        // a malformed settings.json with defaults on the next save.
        guard let dictionary = object as? [String: Any] else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Top-level settings JSON is not an object."))
        }
        raw = dictionary.mapValues(JSONValue.init(foundation:))
    }

    // MARK: Typed access (raw value, else the canonical default)

    public func string(_ key: EdexSettingsKey) -> String? {
        if case let .string(value)? = effective(key) { return value }
        return nil
    }

    public func int(_ key: EdexSettingsKey) -> Int? {
        // `Double(Int.max)` rounds up to 2^63 (unrepresentable as Int), so the
        // upper bound must be strict to keep `Int(value)` from trapping.
        guard case let .number(value)? = effective(key), value.isFinite,
            value >= Double(Int.min), value < Double(Int.max)
        else { return nil }
        return Int(value)
    }

    public func bool(_ key: EdexSettingsKey) -> Bool? {
        if case let .bool(value)? = effective(key) { return value }
        return nil
    }

    public func double(_ key: EdexSettingsKey) -> Double? {
        if case let .number(value)? = effective(key) { return value }
        return nil
    }

    private func effective(_ key: EdexSettingsKey) -> JSONValue? {
        raw[key.rawValue] ?? Self.defaults[key]
    }

    // MARK: Edits (normalized to keep settings.json well-formed)

    public mutating func setString(_ value: String, for key: EdexSettingsKey) {
        raw[key.rawValue] = .string(value)
    }

    public mutating func setBool(_ value: Bool, for key: EdexSettingsKey) {
        raw[key.rawValue] = .bool(value)
    }

    public mutating func setInt(_ value: Int, for key: EdexSettingsKey) {
        raw[key.rawValue] = .number(Double(normalizeInt(value, for: key)))
    }

    public mutating func setDouble(_ value: Double, for key: EdexSettingsKey) {
        raw[key.rawValue] = .number(normalizeDouble(value, for: key))
    }

    private func normalizeInt(_ value: Int, for key: EdexSettingsKey) -> Int {
        switch key {
        case .clockHours: return value == 12 ? 12 : 24
        case .termFontSize: return max(1, value)
        case .monitor: return max(0, value)
        default: return value
        }
    }

    private func normalizeDouble(_ value: Double, for key: EdexSettingsKey) -> Double {
        guard value.isFinite else { return key == .audioVolume ? 1.0 : 0 }
        switch key {
        case .audioVolume: return min(1.0, max(0.0, value))
        default: return value
        }
    }

    // MARK: Persistence

    public func jsonString() throws -> String {
        let object = raw.mapValues(\.foundationObject)
        let data = try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Restart-required diff

    public static func restartRequiredKeys(
        from old: EdexSettingsDocument, to new: EdexSettingsDocument
    ) -> [String] {
        rebootKeys.filter { old.rawOrDefault($0) != new.rawOrDefault($0) }
    }

    private func rawOrDefault(_ key: String) -> JSONValue {
        if let value = raw[key] { return value }
        if let settingsKey = EdexSettingsKey(rawValue: key), let value = Self.defaults[settingsKey] {
            return value
        }
        if key == "forceFullscreen" { return .bool(false) }
        return .null
    }
}

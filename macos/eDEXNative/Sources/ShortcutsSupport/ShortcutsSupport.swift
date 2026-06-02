import Foundation

// Phase 6.4 shortcuts support — pure, FFI-free module.
//
// Parses and models the shortcuts.json schema used by both the legacy renderer
// and the native app. Provides trigger-string parsing (KeyCombo) so the
// AppDelegate's NSEvent monitor can dispatch app and shell shortcuts without
// importing AppKit here.

// MARK: - Modifier flags

public struct ShortcutModifiers: OptionSet, Equatable, Sendable, CustomStringConvertible {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let control = ShortcutModifiers(rawValue: 1 << 0)
    public static let shift   = ShortcutModifiers(rawValue: 1 << 1)
    public static let option  = ShortcutModifiers(rawValue: 1 << 2)   // Alt on legacy
    public static let command = ShortcutModifiers(rawValue: 1 << 3)

    public var description: String {
        var parts: [String] = []
        if contains(.control) { parts.append("Ctrl") }
        if contains(.shift)   { parts.append("Shift") }
        if contains(.option)  { parts.append("Alt") }
        if contains(.command) { parts.append("Cmd") }
        return parts.joined(separator: "+")
    }
}

// MARK: - Key

public enum ShortcutKey: Equatable, Sendable {
    case character(Character)
    case function(Int)        // F1-F15
    case special(SpecialKey)

    public enum SpecialKey: String, Equatable, Sendable {
        case tab = "Tab"
        case space = "Space"
    }
}

// MARK: - KeyCombo

/// A parsed keyboard shortcut: modifier flags + key.
/// Parsed from trigger strings like "Ctrl+Shift+C", "Ctrl+Tab", "F11".
public struct KeyCombo: Equatable, Sendable {
    public let modifiers: ShortcutModifiers
    public let key: ShortcutKey

    public init(modifiers: ShortcutModifiers, key: ShortcutKey) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Failable init from a trigger string.
    /// Returns nil if the trigger cannot be parsed (empty, no key component, etc.)
    public init?(trigger: String) {
        guard !trigger.isEmpty else { return nil }
        var mods: ShortcutModifiers = []
        let keyToken: String

        // Special-case: bare "+" or "<modifiers>++" — the key is the plus character.
        // A normal split on "+" would drop the empty token and lose the key.
        if trigger == "+" {
            keyToken = "+"
        } else if trigger.hasSuffix("++") {
            let modsString = String(trigger.dropLast(2))
            for part in modsString.split(separator: "+", omittingEmptySubsequences: true).map(String.init) {
                switch part.lowercased() {
                case "ctrl", "control": mods.insert(.control)
                case "shift":           mods.insert(.shift)
                case "alt", "option":   mods.insert(.option)
                case "cmd", "command":  mods.insert(.command)
                default: break
                }
            }
            keyToken = "+"
        } else {
            // Standard path: split on "+", first N tokens are modifiers, last is the key.
            var parts = trigger.split(separator: "+", omittingEmptySubsequences: true).map(String.init)
            guard !parts.isEmpty else { return nil }

            var remaining: [String] = []
            for part in parts {
                switch part.lowercased() {
                case "ctrl", "control": mods.insert(.control)
                case "shift":           mods.insert(.shift)
                case "alt", "option":   mods.insert(.option)
                case "cmd", "command":  mods.insert(.command)
                default:                remaining.append(part)
                }
            }
            parts = remaining
            guard let last = parts.last, parts.count == 1 else { return nil }
            keyToken = last
        }

        // Function keys: F1 … F15
        if keyToken.lowercased().hasPrefix("f"), let n = Int(keyToken.dropFirst()),
           (1...15).contains(n) {
            self.modifiers = mods
            self.key = .function(n)
            return
        }

        // Special named keys
        switch keyToken {
        case "Tab":   self.modifiers = mods; self.key = .special(.tab); return
        case "Space": self.modifiers = mods; self.key = .special(.space); return
        default: break
        }

        // Single character (normalised to lowercase)
        let lowered = keyToken.lowercased()
        if lowered.count == 1, let ch = lowered.first {
            self.modifiers = mods
            self.key = .character(ch)
            return
        }

        return nil
    }
}

// MARK: - App shortcut actions

public enum AppShortcutAction: String, Equatable, Sendable, CaseIterable {
    case copy         = "COPY"
    case paste        = "PASTE"
    case nextTab      = "NEXT_TAB"
    case previousTab  = "PREVIOUS_TAB"
    case tabTemplate  = "TAB_X"
    case settings     = "SETTINGS"
    case shortcuts    = "SHORTCUTS"
    case fuzzySearch  = "FUZZY_SEARCH"
    case fsListView   = "FS_LIST_VIEW"
    case fsDotfiles   = "FS_DOTFILES"
    case kbPassmode   = "KB_PASSMODE"
    case devDebug     = "DEV_DEBUG"
    case devReload    = "DEV_RELOAD"
}

// MARK: - Shortcut entry

public struct EdexShortcutEntry: Equatable, Sendable, Identifiable {
    public enum ShortcutType: String, Equatable, Sendable { case app, shell }

    public let id: UUID
    public let type: ShortcutType
    public let trigger: String
    /// Pre-parsed combo. nil when the trigger string cannot be parsed (e.g.
    /// the TAB_X template "Ctrl+X" where "X" is the tab-index placeholder, not
    /// the literal character — this entry is expanded via expandedTabCombos()).
    public let combo: KeyCombo?
    public let action: String
    public let enabled: Bool
    public let linebreak: Bool

    public init(
        id: UUID = UUID(), type: ShortcutType, trigger: String,
        action: String, enabled: Bool, linebreak: Bool = false
    ) {
        self.id = id
        self.type = type
        self.trigger = trigger
        // TAB_X template: store the raw parse but don't treat it as a dispatchable combo
        self.combo = (action == AppShortcutAction.tabTemplate.rawValue) ? nil : KeyCombo(trigger: trigger)
        self.action = action
        self.enabled = enabled
        self.linebreak = linebreak
    }
}

// MARK: - Shortcuts document

public struct EdexShortcutsDocument: Equatable, Sendable {
    public let entries: [EdexShortcutEntry]

    /// Throws if the JSON string is not a top-level array.
    public init(jsonString: String) throws {
        let data = Data(jsonString.utf8)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let array = object as? [[String: Any]] else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Top-level shortcuts JSON is not an array of objects."))
        }
        self.entries = array.compactMap { EdexShortcutsDocument.parse(entry: $0) }
    }

    private static func parse(entry dict: [String: Any]) -> EdexShortcutEntry? {
        guard let typeRaw = dict["type"] as? String,
              let type = EdexShortcutEntry.ShortcutType(rawValue: typeRaw),
              let trigger = dict["trigger"] as? String,
              let action = dict["action"] as? String,
              let enabled = dict["enabled"] as? Bool
        else { return nil }
        let linebreak = (dict["linebreak"] as? Bool) ?? false
        return EdexShortcutEntry(type: type, trigger: trigger, action: action,
                                  enabled: enabled, linebreak: linebreak)
    }

    // MARK: Filtered views

    public func appEntries() -> [EdexShortcutEntry] {
        entries.filter { $0.type == .app }
    }

    public func shellEntries() -> [EdexShortcutEntry] {
        entries.filter { $0.type == .shell }
    }

    /// All entries with enabled == true.
    public func enabledEntries() -> [EdexShortcutEntry] {
        entries.filter { $0.enabled }
    }

    // MARK: TAB_X expansion

    /// Expands the TAB_X template entry ("Ctrl+X") into five combos for
    /// Ctrl+1 … Ctrl+5, returning (combo, tabIndex) pairs.
    public func expandedTabCombos() -> [(KeyCombo, Int)] {
        guard let template = entries.first(where: { $0.action == AppShortcutAction.tabTemplate.rawValue }),
              template.enabled
        else { return [] }

        // Validate that the trigger ends exactly with "+x" or "+X" before expanding.
        // Without this guard, a misconfigured empty or non-X trigger would expand
        // to bare digit strings ("1"…"5"), swallowing terminal number keystrokes.
        let baseTrigger = template.trigger
        guard baseTrigger.lowercased().hasSuffix("+x") else { return [] }
        let prefix = baseTrigger.dropLast(2) // drop "+X", e.g. "Ctrl+X" → "Ctrl"
        return (1...5).compactMap { n -> (KeyCombo, Int)? in
            let expanded = "\(prefix)+\(n)"
            guard let combo = KeyCombo(trigger: expanded) else { return nil }
            return (combo, n)
        }
    }
}

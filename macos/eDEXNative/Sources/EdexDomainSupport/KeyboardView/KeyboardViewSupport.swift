import Foundation

/// The visual shape a key takes in the on-screen keyboard band. Drives sizing
/// in `EdexKeyboardPanel`; independent of the key's modifier identity.
public enum KeyboardKeyRole: Equatable, Sendable {
    /// A normal square key.
    case standard
    /// A wider edge key (legacy 8.33vh treatment — first key of every row and
    /// the trailing key of the first three rows).
    case wide
    /// The space bar (`cmd == " "`).
    case spacebar
    /// The primary, named Enter key (`cmd == "\r"`, non-empty name).
    case enter
    /// The empty-named lower half of the legacy L-shaped Enter key.
    case enterContinuation
    /// A glyph key (arrows, etc.) — carries the legacy icon name.
    case icon(String)
    /// A key whose width is a multiplier of the fitted key side.
    case unit(Double)
}

/// A toggleable modifier on the on-screen keyboard.
public enum KeyboardModifier: String, Equatable, Sendable, CaseIterable {
    case shift
    case capsLock
    case alt
    case fn
    case ctrl
}

public enum KeyboardPhysicalModifier: Equatable, Sendable {
    case leftShift
    case rightShift
    case capsLock
    case leftControl
    case rightControl
    case leftOption
    case rightOption
    case leftCommand
    case rightCommand
    case fn
}

/// The *visual* modifier state of the keyboard band. Phase 8.2 uses this purely
/// for rendering (label emphasis, key highlight, password dimming); Phase 8.3
/// will drive it from real physical/on-screen input and route the result.
public struct KeyboardModifierState: Equatable, Sendable {
    public var shift: Bool
    public var capsLock: Bool
    public var alt: Bool
    public var fn: Bool
    public var ctrl: Bool
    public var passwordMode: Bool

    public init(
        shift: Bool = false,
        capsLock: Bool = false,
        alt: Bool = false,
        fn: Bool = false,
        ctrl: Bool = false,
        passwordMode: Bool = false
    ) {
        self.shift = shift
        self.capsLock = capsLock
        self.alt = alt
        self.fn = fn
        self.ctrl = ctrl
        self.passwordMode = passwordMode
    }

    /// Whether the given modifier is currently engaged.
    public func isOn(_ modifier: KeyboardModifier) -> Bool {
        switch modifier {
        case .shift: return shift
        case .capsLock: return capsLock
        case .alt: return alt
        case .fn: return fn
        case .ctrl: return ctrl
        }
    }

    public mutating func toggle(_ modifier: KeyboardModifier) {
        switch modifier {
        case .shift: shift.toggle()
        case .capsLock: capsLock.toggle()
        case .alt: alt.toggle()
        case .fn: fn.toggle()
        case .ctrl: ctrl.toggle()
        }
    }
}

/// A render-ready description of one on-screen key: its source model, the
/// visual role that sizes it, the legacy label tiers, and (if it is a
/// modifier) which modifier it toggles.
public struct KeyboardKeyDescriptor: Equatable, Sendable, Identifiable {
    public let id: String
    public let key: NativeKeyboardKey
    public let role: KeyboardKeyRole
    public let modifier: KeyboardModifier?

    public init(id: String, key: NativeKeyboardKey, role: KeyboardKeyRole, modifier: KeyboardModifier?) {
        self.id = id
        self.key = key
        self.role = role
        self.modifier = modifier
    }

    /// Legacy `<h1>` — primary label. Icon keys render a glyph, not text.
    public var mainLabel: String {
        if case .icon = role { return "" }
        return key.name
    }

    /// Legacy `<h2>` — shift label (top-left).
    public var shiftLabel: String? { key.shiftName }
    /// Legacy `<h3>` — alternate label (bottom-right).
    public var altLabel: String? { key.alternateName }
    /// Legacy `<h4>` — function label (hidden until Fn).
    public var fnLabel: String? { key.functionName }
    /// Legacy `<h5>` — alt+shift label (top-right).
    public var altShiftLabel: String? { key.alternateShiftName }

    public var iconName: String? {
        if case .icon(let name) = role { return name }
        return nil
    }

    /// The label that should be emphasized given the current modifier state,
    /// mirroring `keyboard.css`: Fn promotes the function label; Shift or Caps
    /// Lock promote the shift label; otherwise the primary label shows.
    public func prominentLabel(modifiers: KeyboardModifierState) -> String {
        if modifiers.fn, let fnLabel, !fnLabel.isEmpty {
            return fnLabel
        }
        if modifiers.shift || modifiers.capsLock, let shiftLabel, !shiftLabel.isEmpty {
            return shiftLabel
        }
        return mainLabel
    }

    /// Whether this key should be highlighted as the active modifier (Caps Lock
    /// and Fn light up when engaged, per the legacy CSS).
    public func isHighlighted(modifiers: KeyboardModifierState) -> Bool {
        guard let modifier else { return false }
        switch modifier {
        case .capsLock, .fn:
            return modifiers.isOn(modifier)
        default:
            return false
        }
    }
}

/// Per-key geometry after fitting a keyboard layout into the current panel.
public struct KeyboardRowLayoutMetrics: Equatable, Sendable {
    public let keySide: Double
    public let spacebarWidth: Double
    public let rowHeight: Double
    public let rowGap: Double
    public let keyGap: Double
    public let clusterGap: Double

    public init(
        keySide: Double,
        spacebarWidth: Double,
        rowHeight: Double,
        rowGap: Double,
        keyGap: Double,
        clusterGap: Double = 0
    ) {
        self.keySide = keySide.finiteNonNegative
        self.spacebarWidth = spacebarWidth.finiteNonNegative
        self.rowHeight = rowHeight.finiteNonNegative
        self.rowGap = rowGap.finiteNonNegative
        self.keyGap = keyGap.finiteNonNegative
        self.clusterGap = clusterGap.finiteNonNegative
    }

    public static func fit(
        rows: [[KeyboardKeyDescriptor]],
        availableWidth: Double,
        availableHeight: Double,
        preferredKeySide: Double,
        preferredSpacebarWidth: Double,
        preferredRowHeight: Double,
        preferredRowGap: Double,
        preferredKeyGap: Double
    ) -> KeyboardRowLayoutMetrics {
        let preferred = KeyboardRowLayoutMetrics(
            keySide: preferredKeySide,
            spacebarWidth: preferredSpacebarWidth,
            rowHeight: preferredRowHeight,
            rowGap: preferredRowGap,
            keyGap: preferredKeyGap
        )
        let maxWidth = rows.map { preferred.rowWidth(for: $0) }.max() ?? 0
        let horizontalScale = scaleToFit(available: availableWidth, desired: maxWidth)
        let desiredHeight = preferred.totalHeight(rowCount: rows.count)
        let verticalScale = scaleToFit(available: availableHeight, desired: desiredHeight)
        let rowHeight = preferred.rowHeight * verticalScale

        return KeyboardRowLayoutMetrics(
            keySide: min(preferred.keySide * horizontalScale, rowHeight * 0.85),
            spacebarWidth: preferred.spacebarWidth * horizontalScale,
            rowHeight: rowHeight,
            rowGap: preferred.rowGap * verticalScale,
            keyGap: preferred.keyGap * horizontalScale
        )
    }

    public static func fit(
        primaryRows: [[KeyboardKeyDescriptor]],
        numpadRows: [[KeyboardKeyDescriptor]],
        availableWidth: Double,
        availableHeight: Double,
        preferredKeySide: Double,
        preferredSpacebarWidth: Double,
        preferredRowHeight: Double,
        preferredRowGap: Double,
        preferredKeyGap: Double,
        preferredClusterGap: Double
    ) -> KeyboardRowLayoutMetrics {
        let preferred = KeyboardRowLayoutMetrics(
            keySide: preferredKeySide,
            spacebarWidth: preferredSpacebarWidth,
            rowHeight: preferredRowHeight,
            rowGap: preferredRowGap,
            keyGap: preferredKeyGap,
            clusterGap: preferredClusterGap
        )
        let rowCount = max(primaryRows.count, numpadRows.count)
        let horizontalScale = (0..<rowCount).reduce(1.0) { scale, index in
            let primaryRow = primaryRows.indices.contains(index) ? primaryRows[index] : []
            let numpadRow = numpadRows.indices.contains(index) ? numpadRows[index] : []
            let primaryKeysWidth = primaryRow.reduce(0) { $0 + preferred.keyWidth(for: $1) }
            let numpadKeysWidth = numpadRow.reduce(0) { $0 + preferred.keyWidth(for: $1) }
            let primaryGaps = max(0, primaryRow.count - 1)
            let numpadGaps = max(0, numpadRow.count - 1)
            let fixedWidth = (Double(primaryGaps + numpadGaps) * preferred.keyGap)
                + (primaryRow.isEmpty || numpadRow.isEmpty ? 0 : preferred.clusterGap)
            let scalableWidth = primaryKeysWidth + numpadKeysWidth
            let availableForKeys = max(0, availableWidth.finiteNonNegative - fixedWidth)
            return min(scale, scaleToFit(available: availableForKeys, desired: scalableWidth))
        }
        let desiredHeight = preferred.totalHeight(rowCount: rowCount)
        let verticalScale = scaleToFit(available: availableHeight, desired: desiredHeight)
        let rowHeight = preferred.rowHeight * verticalScale

        return KeyboardRowLayoutMetrics(
            keySide: min(preferred.keySide * horizontalScale, rowHeight * 0.85),
            spacebarWidth: preferred.spacebarWidth * horizontalScale,
            rowHeight: rowHeight,
            rowGap: preferred.rowGap * verticalScale,
            keyGap: preferred.keyGap,
            clusterGap: preferred.clusterGap
        )
    }

    public func keyWidth(for descriptor: KeyboardKeyDescriptor) -> Double {
        switch descriptor.role {
        case .spacebar:
            return spacebarWidth
        case .enter:
            return max(keySide * 1.8, 0)
        case .enterContinuation:
            return max(keySide * 1.4, 0)
        case .wide:
            return keySide * 1.7
        case let .unit(multiplier):
            return keySide * max(0, multiplier)
        case .standard, .icon:
            return keySide
        }
    }

    public func rowWidth(for row: [KeyboardKeyDescriptor]) -> Double {
        let keysWidth = row.reduce(0) { $0 + keyWidth(for: $1) }
        let gaps = max(0, row.count - 1)
        return keysWidth + (Double(gaps) * keyGap)
    }

    public func totalHeight(rowCount: Int) -> Double {
        let rows = max(0, rowCount)
        let gaps = max(0, rows - 1)
        return (Double(rows) * rowHeight) + (Double(gaps) * rowGap)
    }

    private static func scaleToFit(available: Double, desired: Double) -> Double {
        let available = available.finiteNonNegative
        let desired = desired.finiteNonNegative
        guard desired > 0 else { return 1 }
        return min(1, available / desired)
    }
}

/// Turns a decoded `NativeKeyboardLayout` into render-ready descriptors and
/// exposes the band-level display logic. Pure and FFI-free.
public enum KeyboardViewModel {
    /// Rows of render-ready descriptors, preserving layout order.
    public static func descriptors(for layout: NativeKeyboardLayout) -> [[KeyboardKeyDescriptor]] {
        layout.rows.enumerated().map { rowIndex, row in
            let count = row.keys.count
            return row.keys.enumerated().map { keyIndex, key in
                KeyboardKeyDescriptor(
                    id: "\(row.id.rawValue)_\(keyIndex)",
                    key: key,
                    role: role(for: key, rowIndex: rowIndex, keyIndex: keyIndex, count: count),
                    modifier: modifier(for: key)
                )
            }
        }
    }

    public static func macBookDescriptors(for layout: NativeKeyboardLayout) -> [[KeyboardKeyDescriptor]] {
        [
            [
                makeKey(id: "mac_escape", name: "ESC", sourceName: "ESC", layout: layout, role: .unit(1.65)),
                functionKey(1, sourceName: "1", layout: layout),
                functionKey(2, sourceName: "2", layout: layout),
                functionKey(3, sourceName: "3", layout: layout),
                functionKey(4, sourceName: "4", layout: layout),
                functionKey(5, sourceName: "5", layout: layout),
                functionKey(6, sourceName: "6", layout: layout),
                functionKey(7, sourceName: "7", layout: layout),
                functionKey(8, sourceName: "8", layout: layout),
                functionKey(9, sourceName: "9", layout: layout),
                functionKey(10, sourceName: "0", layout: layout),
                functionKey(11, sourceName: "-", layout: layout),
                functionKey(12, sourceName: "=", layout: layout)
            ],
            [
                makeKey(id: "mac_backtick", name: "`", layout: layout),
                makeKey(id: "mac_1", name: "1", layout: layout),
                makeKey(id: "mac_2", name: "2", layout: layout),
                makeKey(id: "mac_3", name: "3", layout: layout),
                makeKey(id: "mac_4", name: "4", layout: layout),
                makeKey(id: "mac_5", name: "5", layout: layout),
                makeKey(id: "mac_6", name: "6", layout: layout),
                makeKey(id: "mac_7", name: "7", layout: layout),
                makeKey(id: "mac_8", name: "8", layout: layout),
                makeKey(id: "mac_9", name: "9", layout: layout),
                makeKey(id: "mac_0", name: "0", layout: layout),
                makeKey(id: "mac_minus", name: "-", layout: layout),
                makeKey(id: "mac_equals", name: "=", layout: layout),
                makeKey(id: "mac_delete", name: "DELETE", sourceName: "BACK", layout: layout, role: .unit(1.95))
            ],
            [
                makeKey(id: "mac_tab", name: "TAB", layout: layout, role: .unit(1.65)),
                makeKey(id: "mac_q", name: "Q", layout: layout),
                makeKey(id: "mac_w", name: "W", layout: layout),
                makeKey(id: "mac_e", name: "E", layout: layout),
                makeKey(id: "mac_r", name: "R", layout: layout),
                makeKey(id: "mac_t", name: "T", layout: layout),
                makeKey(id: "mac_y", name: "Y", layout: layout),
                makeKey(id: "mac_u", name: "U", layout: layout),
                makeKey(id: "mac_i", name: "I", layout: layout),
                makeKey(id: "mac_o", name: "O", layout: layout),
                makeKey(id: "mac_p", name: "P", layout: layout),
                makeKey(id: "mac_left_bracket", name: "[", layout: layout),
                makeKey(id: "mac_right_bracket", name: "]", layout: layout),
                makeKey(id: "mac_backslash", name: "\\", sourceName: "\\\\", layout: layout, role: .unit(1.45))
            ],
            [
                makeKey(id: "mac_caps", name: "CAPS", sourceName: "CAPS", layout: layout, role: .unit(1.95)),
                makeKey(id: "mac_a", name: "A", layout: layout),
                makeKey(id: "mac_s", name: "S", layout: layout),
                makeKey(id: "mac_d", name: "D", layout: layout),
                makeKey(id: "mac_f", name: "F", layout: layout),
                makeKey(id: "mac_g", name: "G", layout: layout),
                makeKey(id: "mac_h", name: "H", layout: layout),
                makeKey(id: "mac_j", name: "J", layout: layout),
                makeKey(id: "mac_k", name: "K", layout: layout),
                makeKey(id: "mac_l", name: "L", layout: layout),
                makeKey(id: "mac_semicolon", name: ";", layout: layout),
                makeKey(id: "mac_quote", name: "'", layout: layout),
                makeKey(id: "mac_return", name: "RETURN", sourceName: "ENTER", layout: layout, role: .unit(2.25))
            ],
            [
                makeKey(id: "mac_shift_left", name: "SHIFT", sourceName: "SHIFT", layout: layout, role: .unit(2.35)),
                makeKey(id: "mac_z", name: "Z", layout: layout),
                makeKey(id: "mac_x", name: "X", layout: layout),
                makeKey(id: "mac_c", name: "C", layout: layout),
                makeKey(id: "mac_v", name: "V", layout: layout),
                makeKey(id: "mac_b", name: "B", layout: layout),
                makeKey(id: "mac_n", name: "N", layout: layout),
                makeKey(id: "mac_m", name: "M", layout: layout),
                makeKey(id: "mac_comma", name: ",", layout: layout),
                makeKey(id: "mac_period", name: ".", layout: layout),
                makeKey(id: "mac_slash", name: "/", layout: layout),
                makeKey(id: "mac_shift_right", name: "SHIFT", sourceName: "SHIFT", layout: layout, role: .unit(2.75))
            ],
            [
                makeKey(id: "mac_fn", name: "FN", sourceName: "FN", layout: layout, role: .unit(1.2)),
                makeKey(id: "mac_ctrl_left", name: "CTRL", sourceName: "CTRL", layout: layout, role: .unit(1.35)),
                makeKey(id: "mac_option_left", name: "OPTION", sourceName: "ALT GR", layout: layout, role: .unit(1.55)),
                synthesizedKey(id: "mac_command_left", name: "COMMAND", command: "ESCAPED|-- COMMAND: LEFT", role: .unit(1.7)),
                makeKey(id: "mac_space", name: "SPACE", sourceName: "", layout: layout, role: .spacebar),
                synthesizedKey(id: "mac_command_right", name: "COMMAND", command: "ESCAPED|-- COMMAND: RIGHT", role: .unit(1.7)),
                makeKey(id: "mac_option_right", name: "OPTION", sourceName: "ALT GR", layout: layout, role: .unit(1.55)),
                arrowKey(id: "mac_arrow_left", name: "LEFT", iconName: "ARROW_LEFT", layout: layout),
                arrowKey(id: "mac_arrow_up", name: "UP", iconName: "ARROW_UP", layout: layout),
                arrowKey(id: "mac_arrow_down", name: "DOWN", iconName: "ARROW_DOWN", layout: layout),
                arrowKey(id: "mac_arrow_right", name: "RIGHT", iconName: "ARROW_RIGHT", layout: layout)
            ]
        ]
    }

    /// Supplemental render-only numpad rows. These do not come from the legacy
    /// keyboard JSON, so duplicate digits keep independent visual IDs and do not
    /// interfere with physical-key highlighting for the primary keyboard.
    public static func numpadDescriptors() -> [[KeyboardKeyDescriptor]] {
        [
            [
                numpadKey(row: 0, column: 0, name: "NUM", command: "ESCAPED|-- NUMLOCK"),
                numpadKey(row: 0, column: 1, name: "HOME", command: "\u{001B}[H"),
                numpadKey(row: 0, column: 2, name: "INS", command: "\u{001B}[2~"),
                numpadKey(row: 0, column: 3, name: "DEL", command: "\u{001B}[3~")
            ],
            [
                numpadKey(row: 1, column: 0, name: "7", command: "7", alternateName: "HOME"),
                numpadKey(row: 1, column: 1, name: "8", command: "8", alternateName: "UP"),
                numpadKey(row: 1, column: 2, name: "9", command: "9", alternateName: "PGUP"),
                numpadKey(row: 1, column: 3, name: "/", command: "/")
            ],
            [
                numpadKey(row: 2, column: 0, name: "4", command: "4", alternateName: "LEFT"),
                numpadKey(row: 2, column: 1, name: "5", command: "5"),
                numpadKey(row: 2, column: 2, name: "6", command: "6", alternateName: "RIGHT"),
                numpadKey(row: 2, column: 3, name: "*", command: "*")
            ],
            [
                numpadKey(row: 3, column: 0, name: "1", command: "1", alternateName: "END"),
                numpadKey(row: 3, column: 1, name: "2", command: "2", alternateName: "DOWN"),
                numpadKey(row: 3, column: 2, name: "3", command: "3", alternateName: "PGDN"),
                numpadKey(row: 3, column: 3, name: "-", command: "-")
            ],
            [
                numpadKey(row: 4, column: 0, name: "0", command: "0", alternateName: "INS", role: .wide),
                numpadKey(row: 4, column: 1, name: ".", command: "."),
                numpadKey(row: 4, column: 2, name: "+", command: "+"),
                numpadKey(row: 4, column: 3, name: "ENTER", command: "\r", role: .enter)
            ]
        ]
    }

    /// Whole-band opacity: password mode dims to 0.5 (legacy
    /// `[data-password-mode]`), otherwise a detached keyboard dims to 0.18.
    public static func bandOpacity(modifiers: KeyboardModifierState, isDetached: Bool) -> Double {
        if modifiers.passwordMode { return 0.5 }
        if isDetached { return 0.18 }
        return 1.0
    }

    private static func numpadKey(
        row: Int,
        column: Int,
        name: String,
        command: String,
        alternateName: String? = nil,
        role: KeyboardKeyRole = .standard
    ) -> KeyboardKeyDescriptor {
        KeyboardKeyDescriptor(
            id: "numpad_\(row)_\(column)",
            key: NativeKeyboardKey(
                name: name,
                command: command,
                alternateName: alternateName
            ),
            role: role,
            modifier: nil
        )
    }

    private static func functionKey(_ number: Int, sourceName: String, layout: NativeKeyboardLayout) -> KeyboardKeyDescriptor {
        let source = layout.key(name: sourceName)
        return KeyboardKeyDescriptor(
            id: "mac_f\(number)",
            key: NativeKeyboardKey(
                name: "F\(number)",
                command: source?.functionCommand ?? "",
                functionName: "F\(number)",
                functionCommand: source?.functionCommand
            ),
            role: .standard,
            modifier: nil
        )
    }

    private static func makeKey(
        id: String,
        name: String,
        sourceName: String? = nil,
        layout: NativeKeyboardLayout,
        role: KeyboardKeyRole = .standard
    ) -> KeyboardKeyDescriptor {
        let source = layout.key(name: sourceName ?? name)
        let key = source.map { relabeled($0, name: name) }
            ?? NativeKeyboardKey(name: name, command: name.lowercased())
        return KeyboardKeyDescriptor(id: id, key: key, role: role, modifier: modifier(for: key))
    }

    private static func synthesizedKey(
        id: String,
        name: String,
        command: String,
        role: KeyboardKeyRole
    ) -> KeyboardKeyDescriptor {
        let key = NativeKeyboardKey(name: name, command: command)
        return KeyboardKeyDescriptor(id: id, key: key, role: role, modifier: modifier(for: key))
    }

    private static func arrowKey(
        id: String,
        name: String,
        iconName: String,
        layout: NativeKeyboardLayout
    ) -> KeyboardKeyDescriptor {
        let source = layout.key(iconName: iconName)
        let key = source.map { relabeled($0, name: name) }
            ?? NativeKeyboardKey(name: name, command: "", iconName: iconName)
        return KeyboardKeyDescriptor(id: id, key: key, role: .icon(iconName), modifier: nil)
    }

    private static func relabeled(_ source: NativeKeyboardKey, name: String) -> NativeKeyboardKey {
        NativeKeyboardKey(
            name: name,
            command: source.command,
            shiftName: source.shiftName,
            shiftCommand: source.shiftCommand,
            controlCommand: source.controlCommand,
            alternateName: source.alternateName,
            alternateCommand: source.alternateCommand,
            alternateShiftName: source.alternateShiftName,
            alternateShiftCommand: source.alternateShiftCommand,
            functionName: source.functionName,
            functionCommand: source.functionCommand,
            capsLockCommand: source.capsLockCommand,
            iconName: source.iconName
        )
    }

    private static func role(
        for key: NativeKeyboardKey,
        rowIndex: Int,
        keyIndex: Int,
        count: Int
    ) -> KeyboardKeyRole {
        if key.command == " " {
            return .spacebar
        }
        if key.command == "\r" {
            return key.name.isEmpty ? .enterContinuation : .enter
        }
        if let iconName = key.iconName {
            return .icon(iconName)
        }
        // First key of every row, and the trailing key of the first three rows
        // (number row, row_1, row_2), take the wide edge treatment.
        let isFirst = keyIndex == 0
        let isTrailingWideRow = keyIndex == count - 1 && rowIndex <= 2
        if isFirst || isTrailingWideRow {
            return .wide
        }
        return .standard
    }

    private static func modifier(for key: NativeKeyboardKey) -> KeyboardModifier? {
        let prefix = "ESCAPED|-- "
        guard key.command.hasPrefix(prefix) else { return nil }
        let body = key.command.dropFirst(prefix.count)
        if body.hasPrefix("CTRL") { return .ctrl }
        if body.hasPrefix("SHIFT") { return .shift }
        if body.hasPrefix("ALT") { return .alt }
        if body.hasPrefix("CAPSLCK") { return .capsLock }
        if body.hasPrefix("FN") { return .fn }
        return nil
    }
}

/// Maps physical-key shortcut models to the matching on-screen key descriptor.
/// This keeps the AppKit event monitor thin: it can translate `NSEvent` into a
/// `KeyCombo`, then ask this pure mapper which key should light visually.
public enum KeyboardPhysicalKeyMapper {
    public static func descriptorID(for combo: KeyCombo, in layout: NativeKeyboardLayout) -> String? {
        let descriptors = KeyboardViewModel.macBookDescriptors(for: layout).flatMap { $0 }
        switch combo.key {
        case .special(.space):
            return descriptors.first { $0.role == .spacebar }?.id
        case .special(.tab):
            return descriptors.first { $0.key.name.caseInsensitiveCompare("TAB") == .orderedSame }?.id
        case .function(let number):
            return descriptors.first { $0.key.functionName == "F\(number)" }?.id
        case .character(let character):
            return descriptorID(forCharacter: character, in: descriptors)
        }
    }

    public static func descriptorID(for modifier: KeyboardModifier, in layout: NativeKeyboardLayout) -> String? {
        KeyboardViewModel.macBookDescriptors(for: layout)
            .flatMap { $0 }
            .first { $0.modifier == modifier }?
            .id
    }

    public static func descriptorID(for physicalModifier: KeyboardPhysicalModifier, in layout: NativeKeyboardLayout) -> String? {
        let descriptors = KeyboardViewModel.macBookDescriptors(for: layout).flatMap { $0 }
        switch physicalModifier {
        case .leftShift:
            return "mac_shift_left"
        case .rightShift:
            return "mac_shift_right"
        case .capsLock:
            return descriptors.first { $0.modifier == .capsLock }?.id
        case .leftControl:
            return "mac_ctrl_left"
        case .rightControl:
            return descriptors.first { $0.id != "mac_ctrl_left" && $0.modifier == .ctrl }?.id ?? "mac_ctrl_left"
        case .leftOption:
            return "mac_option_left"
        case .rightOption:
            return "mac_option_right"
        case .leftCommand:
            return "mac_command_left"
        case .rightCommand:
            return "mac_command_right"
        case .fn:
            return descriptors.first { $0.modifier == .fn }?.id
        }
    }

    private static func descriptorID(
        forCharacter character: Character,
        in descriptors: [KeyboardKeyDescriptor]
    ) -> String? {
        let value = String(character).lowercased()
        switch value {
        case "\r", "\n":
            return descriptors.first { $0.role == .enter }?.id
                ?? descriptors.first { $0.id == "mac_return" }?.id
        case "\u{1B}":
            return descriptors.first { $0.key.name.caseInsensitiveCompare("ESC") == .orderedSame }?.id
        case "\u{8}", "\u{7F}":
            return descriptors.first {
                $0.key.name.caseInsensitiveCompare("DELETE") == .orderedSame
                    || $0.key.name.caseInsensitiveCompare("BACK") == .orderedSame
            }?.id
        case "\u{F700}":
            return descriptors.first { $0.role == .icon("ARROW_UP") }?.id
        case "\u{F701}":
            return descriptors.first { $0.role == .icon("ARROW_DOWN") }?.id
        case "\u{F702}":
            return descriptors.first { $0.role == .icon("ARROW_LEFT") }?.id
        case "\u{F703}":
            return descriptors.first { $0.role == .icon("ARROW_RIGHT") }?.id
        default:
            return descriptors.first {
                $0.key.command.lowercased() == value || $0.key.name.lowercased() == value
            }?.id
        }
    }
}

/// Finding #3 (List 3): `KeyboardPhysicalKeyMapper` rebuilds the full ~80-key
/// descriptor matrix (`macBookDescriptors(...).flatMap`) and linearly scans it
/// on *every* keystroke (keyDown/keyUp) and modifier change. The on-screen
/// keyboard panel rebuilds the same matrix on every render. This index builds
/// the matrix and the lookup tables once per layout so both paths become O(1).
/// Every lookup is byte-for-byte equivalent to the matching
/// `KeyboardPhysicalKeyMapper` method (see `KeyboardDescriptorIndexTests`).
public struct KeyboardDescriptorIndex: Sendable {
    /// The full descriptor matrix, cached so the on-screen keyboard render and
    /// the per-keystroke lookups share a single build per layout.
    public let rows: [[KeyboardKeyDescriptor]]

    private let spacebarID: String?
    private let tabID: String?
    private let enterID: String?
    private let escID: String?
    private let deleteID: String?
    private let arrowUpID: String?
    private let arrowDownID: String?
    private let arrowLeftID: String?
    private let arrowRightID: String?
    private let functionIDs: [String: String]
    /// Lowercased `command`/`name` → id, first-writer-wins to mirror `.first`.
    private let charIDs: [String: String]
    private let modifierIDs: [KeyboardModifier: String]
    private let capsLockID: String?
    private let fnID: String?
    private let rightCtrlID: String?

    public init(layout: NativeKeyboardLayout) {
        let matrix = KeyboardViewModel.macBookDescriptors(for: layout)
        rows = matrix

        var spacebar: String?
        var tab: String?
        var enterRole: String?
        var hasMacReturn = false
        var esc: String?
        var del: String?
        var up: String?
        var down: String?
        var left: String?
        var right: String?
        var fns = [String: String]()
        var chars = [String: String]()
        var mods = [KeyboardModifier: String]()
        var caps: String?
        var fn: String?
        var rightCtrl: String?

        for descriptor in matrix.flatMap({ $0 }) {
            let key = descriptor.key
            if spacebar == nil, descriptor.role == .spacebar { spacebar = descriptor.id }
            if tab == nil, key.name.caseInsensitiveCompare("TAB") == .orderedSame { tab = descriptor.id }
            if enterRole == nil, descriptor.role == .enter { enterRole = descriptor.id }
            if descriptor.id == "mac_return" { hasMacReturn = true }
            if esc == nil, key.name.caseInsensitiveCompare("ESC") == .orderedSame { esc = descriptor.id }
            if del == nil,
               key.name.caseInsensitiveCompare("DELETE") == .orderedSame
                || key.name.caseInsensitiveCompare("BACK") == .orderedSame {
                del = descriptor.id
            }
            if up == nil, descriptor.role == .icon("ARROW_UP") { up = descriptor.id }
            if down == nil, descriptor.role == .icon("ARROW_DOWN") { down = descriptor.id }
            if left == nil, descriptor.role == .icon("ARROW_LEFT") { left = descriptor.id }
            if right == nil, descriptor.role == .icon("ARROW_RIGHT") { right = descriptor.id }
            if let fname = key.functionName, fns[fname] == nil { fns[fname] = descriptor.id }
            let cmd = key.command.lowercased()
            if chars[cmd] == nil { chars[cmd] = descriptor.id }
            let nm = key.name.lowercased()
            if chars[nm] == nil { chars[nm] = descriptor.id }
            if let modifier = descriptor.modifier {
                if mods[modifier] == nil { mods[modifier] = descriptor.id }
                if caps == nil, modifier == .capsLock { caps = descriptor.id }
                if fn == nil, modifier == .fn { fn = descriptor.id }
                if rightCtrl == nil, descriptor.id != "mac_ctrl_left", modifier == .ctrl {
                    rightCtrl = descriptor.id
                }
            }
        }

        spacebarID = spacebar
        tabID = tab
        enterID = enterRole ?? (hasMacReturn ? "mac_return" : nil)
        escID = esc
        deleteID = del
        arrowUpID = up
        arrowDownID = down
        arrowLeftID = left
        arrowRightID = right
        functionIDs = fns
        charIDs = chars
        modifierIDs = mods
        capsLockID = caps
        fnID = fn
        rightCtrlID = rightCtrl
    }

    public func id(for combo: KeyCombo) -> String? {
        switch combo.key {
        case .special(.space):
            return spacebarID
        case .special(.tab):
            return tabID
        case .function(let number):
            return functionIDs["F\(number)"]
        case .character(let character):
            return id(forCharacter: character)
        }
    }

    public func id(for modifier: KeyboardModifier) -> String? {
        modifierIDs[modifier]
    }

    public func id(for physicalModifier: KeyboardPhysicalModifier) -> String? {
        switch physicalModifier {
        case .leftShift:
            return "mac_shift_left"
        case .rightShift:
            return "mac_shift_right"
        case .capsLock:
            return capsLockID
        case .leftControl:
            return "mac_ctrl_left"
        case .rightControl:
            return rightCtrlID ?? "mac_ctrl_left"
        case .leftOption:
            return "mac_option_left"
        case .rightOption:
            return "mac_option_right"
        case .leftCommand:
            return "mac_command_left"
        case .rightCommand:
            return "mac_command_right"
        case .fn:
            return fnID
        }
    }

    private func id(forCharacter character: Character) -> String? {
        let value = String(character).lowercased()
        switch value {
        case "\r", "\n":
            return enterID
        case "\u{1B}":
            return escID
        case "\u{8}", "\u{7F}":
            return deleteID
        case "\u{F700}":
            return arrowUpID
        case "\u{F701}":
            return arrowDownID
        case "\u{F702}":
            return arrowLeftID
        case "\u{F703}":
            return arrowRightID
        default:
            return charIDs[value]
        }
    }
}

private extension Double {
    var finiteNonNegative: Double {
        isFinite ? max(0, self) : 0
    }
}

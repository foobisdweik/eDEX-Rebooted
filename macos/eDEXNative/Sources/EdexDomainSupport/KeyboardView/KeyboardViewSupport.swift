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
}

/// A toggleable modifier on the on-screen keyboard.
public enum KeyboardModifier: String, Equatable, Sendable, CaseIterable {
    case shift
    case capsLock
    case alt
    case fn
    case ctrl
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

    public init(keySide: Double, spacebarWidth: Double, rowHeight: Double, rowGap: Double, keyGap: Double) {
        self.keySide = keySide.finiteNonNegative
        self.spacebarWidth = spacebarWidth.finiteNonNegative
        self.rowHeight = rowHeight.finiteNonNegative
        self.rowGap = rowGap.finiteNonNegative
        self.keyGap = keyGap.finiteNonNegative
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

        return KeyboardRowLayoutMetrics(
            keySide: preferred.keySide * horizontalScale,
            spacebarWidth: preferred.spacebarWidth * horizontalScale,
            rowHeight: preferred.rowHeight * verticalScale,
            rowGap: preferred.rowGap * verticalScale,
            keyGap: preferred.keyGap * horizontalScale
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

    /// Whole-band opacity: password mode dims to 0.5 (legacy
    /// `[data-password-mode]`), otherwise a detached keyboard dims to 0.18.
    public static func bandOpacity(modifiers: KeyboardModifierState, isDetached: Bool) -> Double {
        if modifiers.passwordMode { return 0.5 }
        if isDetached { return 0.18 }
        return 1.0
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

private extension Double {
    var finiteNonNegative: Double {
        isFinite ? max(0, self) : 0
    }
}

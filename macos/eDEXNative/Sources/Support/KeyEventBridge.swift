import AppKit
import EdexDomainSupport

// Maps NSEvent key-down events to the EdexDomainSupport KeyCombo model so the
// ShellState monitor can match events against shortcuts.json entries without
// importing AppKit inside the pure EdexDomainSupport module.

extension NSEvent {
    /// EdexDomainSupport modifier flags extracted from the event's modifierFlags,
    /// ignoring capsLock, numericPad, function, and help bits.
    var shortcutModifiers: ShortcutModifiers {
        var mods: ShortcutModifiers = []
        if modifierFlags.contains(.control) { mods.insert(.control) }
        if modifierFlags.contains(.shift)   { mods.insert(.shift) }
        if modifierFlags.contains(.option)  { mods.insert(.option) }
        if modifierFlags.contains(.command) { mods.insert(.command) }
        return mods
    }

    /// EdexDomainSupport key derived from keyCode, falling back to
    /// charactersIgnoringModifiers for printable characters.
    var shortcutKey: ShortcutKey? {
        switch keyCode {
        case 36, 76: return .character("\r")
        case 48: return .special(.tab)
        case 49: return .special(.space)
        case 51: return .character("\u{8}")
        case 53: return .character("\u{1B}")
        case 117: return .character("\u{7F}")
        case 123: return .character("\u{F702}")
        case 124: return .character("\u{F703}")
        case 125: return .character("\u{F701}")
        case 126: return .character("\u{F700}")
        // Function keys — virtual key codes from Carbon HIToolbox
        case 122: return .function(1)
        case 120: return .function(2)
        case  99: return .function(3)
        case 118: return .function(4)
        case  96: return .function(5)
        case  97: return .function(6)
        case  98: return .function(7)
        case 100: return .function(8)
        case 101: return .function(9)
        case 109: return .function(10)
        case 103: return .function(11)
        case 111: return .function(12)
        case 105: return .function(13)
        case 107: return .function(14)
        case 113: return .function(15)
        default:
            guard let chars = charactersIgnoringModifiers?.lowercased(),
                  chars.count == 1,
                  let ch = chars.first
            else { return nil }
            return .character(ch)
        }
    }

    /// A KeyCombo synthesised from this event, or nil if the key cannot be
    /// represented (e.g. dead keys, composed sequences, modifier-only presses).
    var keyCombo: KeyCombo? {
        guard let key = shortcutKey else { return nil }
        return KeyCombo(modifiers: shortcutModifiers, key: key)
    }

    var keyboardModifier: KeyboardModifier? {
        switch keyCode {
        case 56, 60:
            return .shift
        case 59, 62:
            return .ctrl
        case 58, 61:
            return .alt
        case 57:
            return .capsLock
        case 63:
            return .fn
        default:
            return nil
        }
    }

    var keyboardPhysicalModifier: KeyboardPhysicalModifier? {
        switch keyCode {
        case 56:
            return .leftShift
        case 60:
            return .rightShift
        case 59:
            return .leftControl
        case 62:
            return .rightControl
        case 58:
            return .leftOption
        case 61:
            return .rightOption
        case 55:
            return .leftCommand
        case 54:
            return .rightCommand
        case 57:
            return .capsLock
        case 63:
            return .fn
        default:
            return nil
        }
    }

    func isActiveModifier(_ modifier: KeyboardModifier) -> Bool {
        switch modifier {
        case .shift:
            return modifierFlags.contains(.shift)
        case .ctrl:
            return modifierFlags.contains(.control)
        case .alt:
            return modifierFlags.contains(.option)
        case .capsLock:
            return modifierFlags.contains(.capsLock)
        case .fn:
            return modifierFlags.contains(.function)
        }
    }

    func isActivePhysicalModifier(_ modifier: KeyboardPhysicalModifier) -> Bool {
        switch modifier {
        case .leftShift, .rightShift:
            return modifierFlags.contains(.shift)
        case .leftControl, .rightControl:
            return modifierFlags.contains(.control)
        case .leftOption, .rightOption:
            return modifierFlags.contains(.option)
        case .leftCommand, .rightCommand:
            return modifierFlags.contains(.command)
        case .capsLock:
            return modifierFlags.contains(.capsLock)
        case .fn:
            return modifierFlags.contains(.function)
        }
    }
}

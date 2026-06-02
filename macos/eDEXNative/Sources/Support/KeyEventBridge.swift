import AppKit
import ShortcutsSupport

// Maps NSEvent key-down events to the ShortcutsSupport KeyCombo model so the
// ShellState monitor can match events against shortcuts.json entries without
// importing AppKit inside the pure ShortcutsSupport module.

extension NSEvent {
    /// ShortcutsSupport modifier flags extracted from the event's modifierFlags,
    /// ignoring capsLock, numericPad, function, and help bits.
    var shortcutModifiers: ShortcutModifiers {
        var mods: ShortcutModifiers = []
        if modifierFlags.contains(.control) { mods.insert(.control) }
        if modifierFlags.contains(.shift)   { mods.insert(.shift) }
        if modifierFlags.contains(.option)  { mods.insert(.option) }
        if modifierFlags.contains(.command) { mods.insert(.command) }
        return mods
    }

    /// ShortcutsSupport key derived from keyCode, falling back to
    /// charactersIgnoringModifiers for printable characters.
    var shortcutKey: ShortcutKey? {
        switch keyCode {
        case 48: return .special(.tab)
        case 49: return .special(.space)
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
}

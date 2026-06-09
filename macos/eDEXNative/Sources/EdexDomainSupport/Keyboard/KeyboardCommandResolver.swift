import Foundation

/// The result of resolving an on-screen key press. `ShellState` applies the
/// effect: firing the shortcut, emitting text to the active sink, arming a dead
/// key, or toggling Caps/Fn. Pure and FFI-free.
public enum KeyboardOutcome: Equatable, Sendable {
    /// An on-screen modifier combo matched a shortcut; fire it.
    case shortcut(ShortcutMatch)
    /// Text to send to the active sink (terminal or detached field).
    case emit(String)
    /// A dead key was pressed; compose the next key against it.
    case armDeadKey(DeadKey)
    /// Escaped "CAPSLCK: ON/OFF".
    case setCapsLock(Bool)
    /// Escaped "FN: ON/OFF".
    case setFn(Bool)
    /// Nothing to do (e.g. an unrecognised escaped command).
    case none

    /// Legacy `pressKey` returns before dead-key handling only when an app shortcut
    /// sets `shortcutsTriggered`; shell shortcuts continue and consume the dead key.
    public var preservesArmedDeadKey: Bool {
        if case .shortcut(.app(_, _)) = self { return true }
        return false
    }
}

/// Resolves an on-screen key press into a `KeyboardOutcome`, mirroring the
/// legacy `keyboard.class.js` `pressKey` decision tree. Pure; FFI-free. State
/// mutation (clearing the dead key, toggling Caps/Fn, releasing transient
/// modifiers, routing the emit) is the caller's responsibility.
public enum KeyboardCommandResolver {
    private static let escapedPrefix = "ESCAPED|-- "

    public static func resolve(
        key: NativeKeyboardKey,
        modifiers: KeyboardModifierState,
        armedDeadKey: DeadKey?,
        shortcuts: EdexShortcutsDocument?
    ) -> KeyboardOutcome {
        // 1. Shortcut interception. Legacy gates on `shortcutsCat.length > 1`,
        //    which is true whenever any transient modifier (Ctrl/Alt/Shift) is
        //    held, and matches against the key's *base* command.
        if modifiers.shift || modifiers.ctrl || modifiers.alt,
           let shortcuts,
           let combo = shortcutCombo(baseCommand: key.command, modifiers: modifiers),
           let match = shortcuts.match(combo) {
            return .shortcut(match)
        }

        // 2. Modifier command selection (legacy pressKey 419-424, in order).
        var command = key.command
        if modifiers.shift || modifiers.capsLock, let shiftCommand = key.shiftCommand {
            command = shiftCommand
        }
        if modifiers.capsLock, let capsLockCommand = key.capsLockCommand {
            command = capsLockCommand
        }
        if modifiers.ctrl, let controlCommand = key.controlCommand {
            command = controlCommand
        }
        if modifiers.alt, let alternateCommand = key.alternateCommand {
            command = alternateCommand
        }
        if modifiers.alt, modifiers.shift, let alternateShiftCommand = key.alternateShiftCommand {
            command = alternateShiftCommand
        }
        if modifiers.fn, let functionCommand = key.functionCommand {
            command = functionCommand
        }

        // 3. Dead-key composition (legacy 425-476).
        if let armedDeadKey {
            command = KeyboardDiacritics.compose(armedDeadKey, command)
        }

        // 4. Escaped command classification (legacy 479-534).
        if command.hasPrefix(escapedPrefix) {
            let body = String(command.dropFirst(escapedPrefix.count))
            switch body {
            case "CAPSLCK: ON": return .setCapsLock(true)
            case "CAPSLCK: OFF": return .setCapsLock(false)
            case "FN: ON": return .setFn(true)
            case "FN: OFF": return .setFn(false)
            default:
                if let deadKey = DeadKey(escapedName: body) { return .armDeadKey(deadKey) }
                return .none
            }
        }

        // 5. Emit.
        return .emit(command)
    }

    /// Builds a `KeyCombo` from the on-screen transient modifiers and the key's
    /// base command. Returns nil when the base command can't form a shortcut key.
    private static func shortcutCombo(baseCommand: String, modifiers: KeyboardModifierState) -> KeyCombo? {
        var mods: ShortcutModifiers = []
        if modifiers.ctrl { mods.insert(.control) }
        if modifiers.shift { mods.insert(.shift) }
        if modifiers.alt { mods.insert(.option) }
        guard let key = shortcutKey(forBaseCommand: baseCommand) else { return nil }
        return KeyCombo(modifiers: mods, key: key)
    }

    private static func shortcutKey(forBaseCommand command: String) -> ShortcutKey? {
        switch command {
        case "\t": return .special(.tab)
        case " ": return .special(.space)
        default:
            let lowered = command.lowercased()
            guard lowered.count == 1, let character = lowered.first else { return nil }
            return .character(character)
        }
    }
}

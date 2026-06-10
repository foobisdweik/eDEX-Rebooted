import Foundation

/// How an emitted command edits a detached native text field (legacy
/// `document.activeElement` branch of `pressKey`). Pure and FFI-free.
public enum KeyboardFieldEdit: Equatable, Sendable {
    /// The field's full text after the edit.
    case replace(String)
    /// Enter was pressed; the field should submit (legacy "change"/"enter").
    case submit
    /// A control sequence with no field meaning; leave the field untouched.
    case ignore
}

/// Applies an on-screen key's emitted command to a detached text field.
public enum KeyboardDetachedEditor {
    public struct State: Equatable, Sendable {
        public let text: String
        public let caret: Int

        public init(text: String, caret: Int) {
            self.text = text
            self.caret = min(max(0, caret), text.count)
        }
    }

    public enum Edit: Equatable, Sendable {
        /// The field's full text and on-screen-keyboard caret after the edit.
        case replace(State)
        /// Enter was pressed; the field should submit.
        case submit
        /// A control sequence with no field meaning; leave the field untouched.
        case ignore
    }

    public static func apply(command: String, to text: String) -> KeyboardFieldEdit {
        if command == "\u{7f}" {
            return .replace(String(text.dropLast()))
        }
        switch apply(command: command, to: State(text: text, caret: text.count)) {
        case let .replace(state):
            return .replace(state.text)
        case .submit:
            return .submit
        case .ignore:
            return .ignore
        }
    }

    public static func apply(command: String, to state: State) -> Edit {
        // Enter → submit.
        if command == "\r" || command == "\n" { return .submit }

        if command == "\u{001B}OD" || command == "\u{001B}[D" {
            return .replace(State(text: state.text, caret: state.caret - 1))
        }
        if command == "\u{001B}OC" || command == "\u{001B}[C" {
            return .replace(State(text: state.text, caret: state.caret + 1))
        }

        // The on-screen BACK key emits BS (\u{8}). Legacy keyboard JSON also uses
        // an empty command for backspace-like keys in some layouts.
        if command.isEmpty || command == "\u{8}" {
            guard state.caret > 0 else { return .replace(state) }
            var text = state.text
            text.remove(at: text.indexForCharacterOffset(state.caret - 1))
            return .replace(State(text: text, caret: state.caret - 1))
        }

        // DEL removes the character under the caret.
        if command == "\u{7f}" {
            guard state.caret < state.text.count else { return .replace(state) }
            var text = state.text
            text.remove(at: text.indexForCharacterOffset(state.caret))
            return .replace(State(text: text, caret: state.caret))
        }

        // Any other leading C0 control character (e.g. Ctrl sequences, arrow
        // escape codes) has no field meaning.
        if let first = command.unicodeScalars.first, first.value < 0x20 { return .ignore }

        var text = state.text
        text.insert(contentsOf: command, at: text.indexForCharacterOffset(state.caret))
        return .replace(State(text: text, caret: state.caret + command.count))
    }
}

private extension String {
    func indexForCharacterOffset(_ offset: Int) -> Index {
        index(startIndex, offsetBy: min(max(0, offset), count))
    }
}

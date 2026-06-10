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
        /// Caret offset in UTF-16 code units (matches AppKit `NSRange.location`).
        public let caret: Int

        public init(text: String, caret: Int) {
            self.text = text
            self.caret = min(max(0, caret), text.utf16.count)
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
        switch apply(command: command, to: State(text: text, caret: text.utf16.count)) {
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

        let text = state.text
        let currentIndex = text.index(atUTF16Offset: state.caret)

        if command == "\u{001B}OD" || command == "\u{001B}[D" {
            let newIndex = currentIndex > text.startIndex ? text.index(before: currentIndex) : text.startIndex
            return .replace(State(text: text, caret: text.utf16Offset(of: newIndex)))
        }
        if command == "\u{001B}OC" || command == "\u{001B}[C" {
            let newIndex = currentIndex < text.endIndex ? text.index(after: currentIndex) : text.endIndex
            return .replace(State(text: text, caret: text.utf16Offset(of: newIndex)))
        }

        // The on-screen BACK key emits BS (\u{8}). Legacy keyboard JSON also uses
        // an empty command for backspace-like keys in some layouts.
        if command.isEmpty || command == "\u{8}" {
            guard currentIndex > text.startIndex else { return .replace(state) }
            var newText = text
            let deleteIndex = text.index(before: currentIndex)
            newText.remove(at: deleteIndex)
            return .replace(State(text: newText, caret: newText.utf16Offset(of: deleteIndex)))
        }

        // DEL removes the character under the caret.
        if command == "\u{7f}" {
            guard currentIndex < text.endIndex else { return .replace(state) }
            var newText = text
            newText.remove(at: currentIndex)
            return .replace(State(text: newText, caret: newText.utf16Offset(of: currentIndex)))
        }

        // Any other leading C0 control character (e.g. Ctrl sequences, arrow
        // escape codes) has no field meaning.
        if let first = command.unicodeScalars.first, first.value < 0x20 { return .ignore }

        var textWithInsertion = text
        textWithInsertion.insert(contentsOf: command, at: currentIndex)
        let newIndex = textWithInsertion.index(currentIndex, offsetBy: command.count)
        return .replace(State(text: textWithInsertion, caret: textWithInsertion.utf16Offset(of: newIndex)))
    }
}

public extension String {
    func index(atUTF16Offset offset: Int) -> Index {
        Index(utf16Offset: min(max(0, offset), utf16.count), in: self)
    }

    func utf16Offset(of index: Index) -> Int {
        index.utf16Offset(in: self)
    }
}

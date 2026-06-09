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
///
/// Caret movement (legacy `OD`/`OC` on `selectionStart`) is intentionally not
/// modelled — SwiftUI's plain `TextField` exposes no caret seam without an
/// AppKit escape hatch, so arrows degrade to `.ignore`. Append, backspace, and
/// submit cover the realistic on-screen-keyboard-into-search-box flow.
public enum KeyboardDetachedEditor {
    public static func apply(command: String, to text: String) -> KeyboardFieldEdit {
        // Enter → submit.
        if command == "\r" || command == "\n" { return .submit }
        // Empty command (Backspace/Escape key) → drop the last character.
        if command.isEmpty { return .replace(String(text.dropLast())) }
        // A leading C0 control character (e.g. Ctrl sequences, arrows) has no
        // field meaning.
        if let first = command.unicodeScalars.first, first.value < 0x20 { return .ignore }
        return .replace(text + command)
    }
}

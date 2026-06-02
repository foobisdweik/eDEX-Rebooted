import FilesystemSupport
import Foundation

// Phase 7.3 text editor support — pure, FFI-free module.
//
// Models the nano-style editor that replaces FilesystemDisplay.openFile: an
// in-memory document tracking its on-disk baseline (for the dirty marker), with
// line/byte metrics and the status-line text. ShellState reads/writes the file
// through the FFI; this layer holds no I/O.

/// An open text file being edited. `text` is the live buffer; `savedText` is the
/// last on-disk baseline used for the dirty check.
public struct EdexTextDocument: Equatable, Sendable {
    public let path: String
    public private(set) var savedText: String
    public var text: String

    public init(path: String, text: String) {
        self.path = path
        self.savedText = text
        self.text = text
    }

    /// True when the buffer differs from the last-saved baseline.
    public var isDirty: Bool { text != savedText }

    /// Rebaselines after a successful write so the buffer is no longer dirty.
    public mutating func markSaved() {
        savedText = text
    }

    /// Editor line count: 0 for an empty buffer, otherwise the number of
    /// newline-separated segments (a trailing newline yields a trailing line).
    public var lineCount: Int {
        text.isEmpty ? 0 : text.components(separatedBy: "\n").count
    }

    /// On-disk size of the current buffer in bytes (UTF-8).
    public var byteCount: Int {
        text.utf8.count
    }

    /// Display name (basename of the path).
    public var fileName: String {
        PathUtils.basename(path)
    }

    /// Idle status line under the editor: "N lines · SIZE[ • modified]".
    public var statusLine: String {
        let size = FilesystemFormatter.formatBytes(UInt64(byteCount))
        let dirty = isDirty ? " • modified" : ""
        return "\(lineCount) lines · \(size)\(dirty)"
    }
}

/// Status text for save outcomes (mirrors the legacy `#fedit-status` line).
public enum EdexTextEditorStatus {
    public static func saved(_ document: EdexTextDocument) -> String {
        "Saved \(FilesystemFormatter.formatBytes(UInt64(document.byteCount))) to disk."
    }

    public static func failed(_ error: String) -> String {
        "Save failed: \(error)"
    }
}

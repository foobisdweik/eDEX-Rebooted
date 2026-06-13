import AppKit
import EdexRenderingSupport
import SwiftUI

private struct DetachedTextThemeToken: Equatable {
    let terminalFont: String
    let foregroundHex: String
    let backgroundHex: String
    let selectionHex: String
    let fontSize: CGFloat

    init(theme: NativeTheme, fontSize: CGFloat) {
        terminalFont = theme.fonts.terminal
        foregroundHex = theme.palette.terminalForeground.hexRGB
        backgroundHex = theme.palette.terminalBackground.hexRGB
        selectionHex = theme.palette.terminalSelection.hexRGB
        self.fontSize = fontSize
    }
}

struct EdexDetachedSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var caret: Int

    let placeholder: String
    let theme: NativeTheme
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, caret: $caret, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.caret = $caret
        context.coordinator.onSubmit = onSubmit
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = placeholder

        let token = DetachedTextThemeToken(theme: theme, fontSize: 13)
        if context.coordinator.appliedThemeToken != token {
            context.coordinator.appliedThemeToken = token
            field.font = NSFont(name: theme.fonts.terminal, size: 13)
                ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            field.textColor = nsColor(theme.palette.terminalForeground)
        }

        let isFocused = field.window != nil && field.window?.firstResponder === field.currentEditor()
        let currentCaret = field.currentEditor()?.selectedRange.location
        if isFocused, currentCaret == caret, field.stringValue == text {
            return
        }

        DispatchQueue.main.async {
            if field.window?.firstResponder !== field.currentEditor() {
                field.window?.makeFirstResponder(field)
            }
            if let editor = field.currentEditor() {
                (editor as? NSTextView)?.insertionPointColor = nsColor(theme.palette.terminalForeground)
                let location = min(max(0, caret), field.stringValue.utf16.count)
                editor.selectedRange = NSRange(location: location, length: 0)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var caret: Binding<Int>
        var onSubmit: () -> Void
        fileprivate var appliedThemeToken: DetachedTextThemeToken?

        init(text: Binding<String>, caret: Binding<Int>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.caret = caret
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
            caret.wrappedValue = field.currentEditor()?.selectedRange.location ?? field.stringValue.utf16.count
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            DispatchQueue.main.async {
                self.caret.wrappedValue = textView.selectedRange.location
            }
            return false
        }
    }
}

struct EdexDetachedTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var caret: Int

    let theme: NativeTheme

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, caret: $caret)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.caret = $caret

        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }

        let token = DetachedTextThemeToken(theme: theme, fontSize: 12)
        if context.coordinator.appliedThemeToken != token {
            context.coordinator.appliedThemeToken = token
            textView.font = NSFont(name: theme.fonts.terminal, size: 12)
                ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            textView.textColor = nsColor(theme.palette.terminalForeground)
            textView.backgroundColor = nsColor(theme.palette.terminalBackground).withAlphaComponent(0.72)
            textView.insertionPointColor = nsColor(theme.palette.terminalForeground)
            textView.selectedTextAttributes = [
                .backgroundColor: nsColor(theme.palette.terminalSelection)
            ]
        }

        let isFocused = textView.window != nil && textView.window?.firstResponder === textView
        let currentCaret = textView.selectedRange.location
        if isFocused, currentCaret == caret, textView.string == text {
            return
        }

        DispatchQueue.main.async {
            if textView.window?.firstResponder !== textView {
                textView.window?.makeFirstResponder(textView)
            }
            let location = min(max(0, caret), textView.string.utf16.count)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            textView.scrollRangeToVisible(NSRange(location: location, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var caret: Binding<Int>
        fileprivate var appliedThemeToken: DetachedTextThemeToken?

        init(text: Binding<String>, caret: Binding<Int>) {
            self.text = text
            self.caret = caret
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            caret.wrappedValue = textView.selectedRange.location
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            caret.wrappedValue = textView.selectedRange.location
        }
    }
}

private func nsColor(_ color: NativeColor) -> NSColor {
    NSColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
}

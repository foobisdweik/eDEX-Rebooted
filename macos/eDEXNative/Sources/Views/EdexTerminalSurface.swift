import EdexRenderingSupport
import SwiftUI
import SwiftTerm

/// Mounts the store-owned SwiftTerm `TerminalView` inside SwiftUI shell chrome.
struct EdexTerminalSurface: NSViewRepresentable {
    let terminalView: TerminalView
    let theme: NativeTheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TerminalView {
        terminalView
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        let token = TerminalThemeToken(theme: theme)
        guard context.coordinator.appliedThemeToken != token else { return }
        context.coordinator.appliedThemeToken = token

        let bg = theme.palette.terminalBackground
        nsView.nativeBackgroundColor = NSColor(
            red: bg.red,
            green: bg.green,
            blue: bg.blue,
            alpha: bg.alpha
        )
        let fg = theme.palette.terminalForeground
        nsView.nativeForegroundColor = NSColor(
            red: fg.red,
            green: fg.green,
            blue: fg.blue,
            alpha: fg.alpha
        )
        nsView.font = NSFont(name: theme.fonts.terminal, size: 13)
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        nsView.caretColor = NSColor(red: fg.red, green: fg.green, blue: fg.blue, alpha: 1)
        let sel = theme.palette.terminalSelection
        nsView.selectedTextBackgroundColor = NSColor(
            red: sel.red,
            green: sel.green,
            blue: sel.blue,
            alpha: max(sel.alpha, 0.001)
        )
    }

    final class Coordinator {
        fileprivate var appliedThemeToken: TerminalThemeToken?
    }
}

private struct TerminalThemeToken: Equatable {
    let terminalFont: String
    let backgroundHex: String
    let foregroundHex: String
    let selectionHex: String

    init(theme: NativeTheme) {
        terminalFont = theme.fonts.terminal
        backgroundHex = theme.palette.terminalBackground.hexRGB
        foregroundHex = theme.palette.terminalForeground.hexRGB
        selectionHex = theme.palette.terminalSelection.hexRGB
    }
}

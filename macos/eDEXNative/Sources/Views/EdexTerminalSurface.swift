import EdexRenderingSupport
import SwiftUI
import SwiftTerm

/// Mounts the store-owned SwiftTerm `TerminalView` inside SwiftUI shell chrome.
struct EdexTerminalSurface: NSViewRepresentable {
    let terminalView: TerminalView
    let theme: NativeTheme

    func makeNSView(context: Context) -> TerminalView {
        terminalView
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
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
    }
}

import AppKit
import EdexCoreBridge
import EdexDomainSupport
import EdexRenderingSupport
import Observation
import SwiftTerm

@Observable
@MainActor
final class TerminalStore: TerminalSessionProviding, @preconcurrency TerminalViewDelegate {
    private let terminalClient: TerminalClient
    private let outputBox: PtyOutputBufferBox
    private var ptyId: UInt32?
    private var spawned = false
    private var storedActiveTab = 0

    @ObservationIgnored private(set) var terminalView: TerminalView

    var activeCwd: String {
        outputBox.cwd ?? NSHomeDirectory()
    }

    var activeTab: Int { storedActiveTab }

    init(core: EdexCore) {
        terminalClient = TerminalClient(core: core)
        outputBox = PtyOutputBufferBox()
        let view = TerminalView()
        terminalView = view
        view.terminalDelegate = self
    }

    /// Spawns the in-process PTY once settings and theme are available (post-bootstrap).
    func start(settings: SettingsSummary, theme: NativeTheme) {
        guard !spawned else { return }

        applyTheme(theme)

        outputBox.onDataAvailable = { [weak self] in
            self?.drainToTerminal()
        }

        let cols = terminalView.terminal.cols
        let rows = terminalView.terminal.rows
        let spawnCols = cols > 0 ? Double(cols) : Double(TerminalSpawnRequest.defaultCols)
        let spawnRows = rows > 0 ? Double(rows) : Double(TerminalSpawnRequest.defaultRows)
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"

        // SettingsSummary has no shell/cwd fields yet — use TerminalSpawnRequest defaults.
        // 9.x TODO: read shell/cwd from settings when exposed by bootstrap FFI.
        let request = TerminalSpawnRequest.make(
            env: env,
            cols: spawnCols,
            rows: spawnRows
        )

        do {
            ptyId = try terminalClient.spawn(request: request, output: outputBox)
            spawned = true
        } catch {
            print("eDEXNative terminal spawn failed: \(error.localizedDescription)")
        }
    }

    func applyTheme(_ theme: NativeTheme) {
        let bg = theme.palette.terminalBackground
        terminalView.nativeBackgroundColor = NSColor(
            red: bg.red,
            green: bg.green,
            blue: bg.blue,
            alpha: bg.alpha
        )
        let fg = theme.palette.terminalForeground
        terminalView.nativeForegroundColor = NSColor(
            red: fg.red,
            green: fg.green,
            blue: fg.blue,
            alpha: fg.alpha
        )
        let fontName = theme.fonts.terminal
        terminalView.font = NSFont(name: fontName, size: 13)
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    func sendInput(_ text: String) {
        guard let ptyId else { return }
        try? terminalClient.writePty(id: ptyId, data: text)
    }

    func switchTab(_ index: Int) {
        guard (0..<5).contains(index) else { return }
        storedActiveTab = index
        // Single active PTY for now; multi-tab spawn/switch lands in 9.4.
    }

    private func drainToTerminal() {
        let bytes = outputBox.drain()
        guard !bytes.isEmpty else { return }
        terminalView.feed(byteArray: bytes[...])
    }

    private func clampedDimension(_ value: Int, default defaultValue: UInt16) -> UInt16 {
        guard value >= 1 else {
            return max(1, defaultValue)
        }
        if value > Int(UInt16.max) {
            return UInt16.max
        }
        return UInt16(value)
    }

    // MARK: - TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard let ptyId else { return }
        try? terminalClient.writePty(id: ptyId, data: String(decoding: data, as: UTF8.self))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        guard newCols > 0, newRows > 0 else { return }
        guard let ptyId else { return }
        let cols = clampedDimension(newCols, default: TerminalSpawnRequest.defaultCols)
        let rows = clampedDimension(newRows, default: TerminalSpawnRequest.defaultRows)
        try? terminalClient.resizePty(id: ptyId, cols: cols, rows: rows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}

    func clipboardCopy(source: TerminalView, content: Data) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

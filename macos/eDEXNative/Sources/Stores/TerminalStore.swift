import AppKit
import EdexCoreBridge
import EdexDomainSupport
import EdexRenderingSupport
import Observation
import SwiftTerm

@MainActor private final class TerminalSession {
    let index: Int
    let view: TerminalView
    let outputBox: PtyOutputBufferBox
    var ptyId: UInt32?
    var exited = false

    init(index: Int) {
        self.index = index
        self.view = TerminalView()
        self.outputBox = PtyOutputBufferBox()
    }
}

@Observable
@MainActor
final class TerminalStore: TerminalSessionProviding, @preconcurrency TerminalViewDelegate {
    private let terminalClient: TerminalClient
    private var sessions: [TerminalSession]
    private(set) var tabs = TerminalTabSet()
    private var started = false

    var terminalView: TerminalView { sessions[tabs.active].view }

    var activeCwd: String {
        sessions[tabs.active].outputBox.cwd ?? NSHomeDirectory()
    }

    var activeTab: Int { tabs.active }

    init(core: EdexCore) {
        terminalClient = TerminalClient(core: core)
        sessions = (0..<5).map { TerminalSession(index: $0) }
        for session in sessions {
            session.view.terminalDelegate = self
        }
    }

    /// Spawns the in-process PTY once settings and theme are available (post-bootstrap).
    func start(settings: SettingsSummary, theme: NativeTheme) {
        guard !started else { return }
        started = true

        applyTheme(theme)

        for session in sessions {
            session.outputBox.onDataAvailable = { [weak self, session] in
                self?.drain(session)
            }
            session.outputBox.onExit = { [weak self, session] in
                self?.handleExit(session)
            }
        }

        spawnIfNeeded(sessions[tabs.active])
    }

    func applyTheme(_ theme: NativeTheme) {
        for session in sessions {
            let view = session.view
            let bg = theme.palette.terminalBackground
            view.nativeBackgroundColor = NSColor(
                red: bg.red,
                green: bg.green,
                blue: bg.blue,
                alpha: bg.alpha
            )
            let fg = theme.palette.terminalForeground
            view.nativeForegroundColor = NSColor(
                red: fg.red,
                green: fg.green,
                blue: fg.blue,
                alpha: fg.alpha
            )
            let fontName = theme.fonts.terminal
            view.font = NSFont(name: fontName, size: 13)
                ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        }
    }

    func sendInput(_ text: String) {
        let s = sessions[tabs.active]
        if s.exited {
            respawn(s)
            guard let id = s.ptyId else { return }
            try? terminalClient.writePty(id: id, data: text)
            return
        }
        guard let id = s.ptyId else { return }
        try? terminalClient.writePty(id: id, data: text)
    }

    func switchTab(_ index: Int) {
        tabs.select(index)
        spawnIfNeeded(sessions[tabs.active])
    }

    func selectNextTab() {
        tabs.selectNext()
        spawnIfNeeded(sessions[tabs.active])
    }

    func selectPreviousTab() {
        tabs.selectPrevious()
        spawnIfNeeded(sessions[tabs.active])
    }

    func copySelection() {
        let view = sessions[tabs.active].view
        view.copy(view)
    }

    func pasteClipboard() {
        let view = sessions[tabs.active].view
        view.paste(view)
    }

    private func spawnIfNeeded(_ s: TerminalSession) {
        guard s.ptyId == nil, !s.exited else { return }

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"

        let cols = s.view.terminal.cols
        let rows = s.view.terminal.rows
        let spawnCols = cols > 0 ? Double(cols) : Double(TerminalSpawnRequest.defaultCols)
        let spawnRows = rows > 0 ? Double(rows) : Double(TerminalSpawnRequest.defaultRows)

        let request = TerminalSpawnRequest.make(
            env: env,
            cols: spawnCols,
            rows: spawnRows
        )

        do {
            s.ptyId = try terminalClient.spawn(request: request, output: s.outputBox)
            s.exited = false
        } catch {
            print("eDEXNative terminal spawn failed: \(error.localizedDescription)")
        }
    }

    private func drain(_ s: TerminalSession) {
        let bytes = s.outputBox.drain()
        guard !bytes.isEmpty else { return }
        s.view.feed(byteArray: bytes[...])
    }

    private func handleExit(_ s: TerminalSession) {
        drain(s)
        s.exited = true
        if let id = s.ptyId {
            try? terminalClient.killPty(id: id)
        }
        s.ptyId = nil
        s.view.feed(text: "\r\n\u{001B}[38;5;245m[process exited — press any key to restart]\u{001B}[0m\r\n")
    }

    private func respawn(_ s: TerminalSession) {
        s.exited = false
        spawnIfNeeded(s)
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
        guard let session = sessions.first(where: { $0.view === source }) else { return }
        // The shell has exited and shows the "press any key to restart" notice;
        // a physical keystroke into the focused view restarts it (mirrors the
        // on-screen path in sendInput) rather than vanishing against a dead PTY.
        if session.exited {
            respawn(session)
            guard let id = session.ptyId else { return }
            try? terminalClient.writePty(id: id, data: String(decoding: data, as: UTF8.self))
            return
        }
        guard let id = session.ptyId else { return }
        try? terminalClient.writePty(id: id, data: String(decoding: data, as: UTF8.self))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        guard newCols > 0, newRows > 0 else { return }
        let session = sessions.first { $0.view === source }
        guard let id = session?.ptyId else { return }
        let cols = clampedDimension(newCols, default: TerminalSpawnRequest.defaultCols)
        let rows = clampedDimension(newRows, default: TerminalSpawnRequest.defaultRows)
        try? terminalClient.resizePty(id: id, cols: cols, rows: rows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}

    func clipboardCopy(source: TerminalView, content: Data) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

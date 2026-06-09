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
    /// Last-observed working directory and foreground process of this tab's
    /// shell (Phase 9.5). Updated by metadata polls; nil until first read.
    var cwd: String?
    var process: String?

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
    private(set) var aliveTabs: Set<Int> = []
    private var started = false

    var onStdout: (() -> Void)?

    var terminalView: TerminalView { sessions[tabs.active].view }

    /// The active tab's working directory and foreground process, mirrored into
    /// observable storage so SwiftUI (and the filesystem-panel follow logic)
    /// re-evaluate when a metadata poll or tab switch changes them.
    ///
    /// `activeCwd` coerces an unknown cwd to home for display/`TerminalSessionProviding`;
    /// `activeCwdRaw` preserves nil so the cwd-follow can ignore a poll that
    /// couldn't read the shell's cwd instead of treating it as a `cd ~`.
    private(set) var activeCwd: String = NSHomeDirectory()
    private(set) var activeCwdRaw: String?
    private(set) var activeProcess: String?

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
            // Weak-capture the session: outputBox is owned by the session, so a
            // strong capture here would form a session → box → closure → session
            // retain cycle and leak the TerminalView even after store teardown.
            session.outputBox.onDataAvailable = { [weak self, weak session] in
                guard let self, let session else { return }
                self.drain(session)
            }
            session.outputBox.onExit = { [weak self, weak session] in
                guard let self, let session else { return }
                self.handleExit(session)
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
            view.caretColor = NSColor(red: fg.red, green: fg.green, blue: fg.blue, alpha: 1)
            let sel = theme.palette.terminalSelection
            view.selectedTextBackgroundColor = NSColor(
                red: sel.red,
                green: sel.green,
                blue: sel.blue,
                alpha: max(sel.alpha, 0.001)
            )
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
        syncActiveMetadata()
    }

    func selectNextTab() {
        tabs.selectNext()
        spawnIfNeeded(sessions[tabs.active])
        syncActiveMetadata()
    }

    func selectPreviousTab() {
        tabs.selectPrevious()
        spawnIfNeeded(sessions[tabs.active])
        syncActiveMetadata()
    }

    /// Polls the active session's live PTY metadata (the shell's current working
    /// directory tracks `cd`; the foreground process is the newest PID in the
    /// shell's process group). The FFI read hits libproc, so it is offloaded off
    /// the MainActor per the project's FFI rule. Drives the filesystem-panel cwd
    /// follow (see `ShellState.refreshTerminalMetadata`).
    func refreshActiveMetadata() async {
        let active = sessions[tabs.active]
        guard let id = active.ptyId, !active.exited else { return }
        let client = terminalClient
        let metadata = await Task.detached(priority: .background) {
            try? client.ptyMetadata(id: id)
        }.value
        guard let metadata else { return }
        active.cwd = metadata.cwd
        active.process = metadata.process
        // The user may have switched tabs while the read was in flight; only
        // publish if this is still the active session.
        if sessions[tabs.active] === active {
            syncActiveMetadata()
        }
    }

    /// Republishes the active session's last-known metadata into the observable
    /// `activeCwd`/`activeProcess`. Called on tab switch (so the panel follows
    /// the newly-active tab) and after each successful poll.
    private func syncActiveMetadata() {
        let active = sessions[tabs.active]
        activeCwdRaw = active.cwd
        activeCwd = active.cwd ?? NSHomeDirectory()
        activeProcess = active.process
    }

    func copySelection() {
        let view = sessions[tabs.active].view
        view.copy(view)
    }

    func pasteClipboard() {
        let view = sessions[tabs.active].view
        view.paste(view)
    }

    func closeTab(_ index: Int) {
        guard sessions.indices.contains(index) else { return }
        let s = sessions[index]
        if let id = s.ptyId { try? terminalClient.killPty(id: id) }
        s.ptyId = nil
        s.exited = true
        aliveTabs.remove(index)
        s.view.feed(text: "\r\n\u{001B}[38;5;245m[tab closed — press any key to restart]\u{001B}[0m\r\n")
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
            aliveTabs.insert(s.index)
        } catch {
            // A failed spawn leaves no PTY. Mark the session exited and surface
            // the error so the dead tab isn't silent — this covers the initial
            // lazy spawn (start/switchTab) as well as respawn, and the next
            // keystroke then routes through respawn() to retry.
            print("eDEXNative terminal spawn failed: \(error.localizedDescription)")
            s.exited = true
            aliveTabs.remove(s.index)
            s.view.feed(text: "\r\n\u{001B}[31m[terminal spawn failed: \(error.localizedDescription)]\u{001B}[0m\r\n\u{001B}[38;5;245m[press any key to retry]\u{001B}[0m\r\n")
        }
    }

    private func drain(_ s: TerminalSession) {
        let bytes = s.outputBox.drain()
        guard !bytes.isEmpty else { return }
        s.view.feed(byteArray: bytes[...])
        if s === sessions[tabs.active] { onStdout?() }
    }

    private func handleExit(_ s: TerminalSession) {
        drain(s)
        s.exited = true
        aliveTabs.remove(s.index)
        if let id = s.ptyId {
            try? terminalClient.killPty(id: id)
        }
        s.ptyId = nil
        s.view.feed(text: "\r\n\u{001B}[38;5;245m[process exited — press any key to restart]\u{001B}[0m\r\n")
    }

    private func respawn(_ s: TerminalSession) {
        // Clear `exited` so spawnIfNeeded's guard lets it through; if the spawn
        // fails, spawnIfNeeded's catch re-sets `exited` (and shows the retry
        // notice), so a failed restart stays retryable on the next keystroke.
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

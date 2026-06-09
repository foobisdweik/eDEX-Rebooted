import Foundation
import EdexCoreBridge
import EdexDomainSupport

/// PTY façade over an `EdexCore` instance.
///
/// `PtyManager` state lives on whichever `EdexCore` spawned the session. Slice 9.2
/// will inject the app's shared `EdexCore` here so terminal I/O uses one core.
struct TerminalClient: Sendable {
    private let core: EdexCore

    init(core: EdexCore = EdexCore()) {
        self.core = core
    }

    func spawn(request: TerminalSpawnRequest, output: PtyOutputBufferBox) throws -> UInt32 {
        // 9.2: inject TERM=xterm-256color (and COLORTERM) into env for SwiftTerm/full-screen apps.
        let sink = PtyOutputSinkAdapter(box: output)
        return try core.spawnPty(opts: ffiSpawnOptions(from: request), sink: sink)
    }

    func writePty(id: UInt32, data: String) throws {
        try core.writePty(id: id, data: data)
    }

    func resizePty(id: UInt32, cols: UInt16, rows: UInt16) throws {
        try core.resizePty(id: id, cols: cols, rows: rows)
    }

    func killPty(id: UInt32) throws {
        try core.killPty(id: id)
    }

    func ptyMetadata(id: UInt32) throws -> FfiPtyMetadata {
        try core.ptyMetadata(id: id)
    }
}

/// Thread-safe PTY output accumulator. Append stays synchronous on the reader
/// thread for byte ordering; only the optional drain notification hops to MainActor.
final class PtyOutputBufferBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = PtyOutputBuffer()
    private var notifyScheduled = false

    /// Called on MainActor after each synchronous append. Multiple coalesced
    /// notifications are safe because `drain()` atomically returns all pending bytes.
    var onDataAvailable: (@MainActor () -> Void)?

    /// Called on MainActor after pending output has been drained.
    var onExit: (@MainActor () -> Void)?

    private var exitScheduled = false

    /// Coalesce drain notifications to at most one pending MainActor hop.
    func scheduleNotify() {
        lock.lock()
        defer { lock.unlock() }
        guard onDataAvailable != nil, !notifyScheduled else { return }
        notifyScheduled = true
        Task { @MainActor in
            self.fireNotify()
        }
    }

    @MainActor
    private func fireNotify() {
        let callback: (@MainActor () -> Void)?
        lock.lock()
        notifyScheduled = false
        callback = onDataAvailable
        lock.unlock()
        callback?()
    }

    /// Schedules a single MainActor exit callback. Call after `scheduleNotify()`
    /// so any buffered bytes drain before `onExit` fires.
    func scheduleExit() {
        lock.lock()
        defer { lock.unlock() }
        guard onExit != nil, !exitScheduled else { return }
        exitScheduled = true
        Task { @MainActor in
            self.fireExit()
        }
    }

    @MainActor
    private func fireExit() {
        let callback: (@MainActor () -> Void)?
        lock.lock()
        exitScheduled = false
        callback = onExit
        lock.unlock()
        callback?()
    }

    func append(_ bytes: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(bytes)
    }

    func markExited(status: Int32?) {
        lock.lock()
        defer { lock.unlock() }
        buffer.markExited(status: status)
    }

    func updateMetadata(cwd: String?, process: String?) {
        lock.lock()
        defer { lock.unlock() }
        buffer.updateMetadata(cwd: cwd, process: process)
    }

    func drain() -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        return buffer.drain()
    }

    var lifecycle: PtyLifecycle {
        lock.lock()
        defer { lock.unlock() }
        return buffer.lifecycle
    }

    var cwd: String? {
        lock.lock()
        defer { lock.unlock() }
        return buffer.cwd
    }

    var process: String? {
        lock.lock()
        defer { lock.unlock() }
        return buffer.process
    }
}

private func ffiSpawnOptions(from request: TerminalSpawnRequest) -> FfiPtySpawnOptions {
    let keys = request.env.keys.sorted()
    let values = keys.map { request.env[$0]! }
    return FfiPtySpawnOptions(
        shell: request.shell,
        args: request.args,
        cwd: request.cwd,
        envKeys: keys,
        envValues: values,
        cols: request.cols,
        rows: request.rows
    )
}

private final class PtyOutputSinkAdapter: PtyOutputSink, @unchecked Sendable {
    private let box: PtyOutputBufferBox

    init(box: PtyOutputBufferBox) {
        self.box = box
    }

    func onOutput(id: UInt32, bytes: Data) {
        // Synchronous append: Rust's single reader thread calls onOutput in strict order;
        // unstructured Tasks onto MainActor are not resumed in creation order under load.
        box.append(Array(bytes))
        // Only the drain notification hops to main; append ordering is preserved above.
        box.scheduleNotify()
    }

    func onExit(id: UInt32, status: Int32?) {
        box.markExited(status: status)
        box.scheduleNotify()
        box.scheduleExit()
    }

    func onMetadata(id: UInt32, cwd: String?, process: String?) {
        box.updateMetadata(cwd: cwd, process: process)
    }
}

import Foundation

public enum PtyLifecycle: Equatable, Sendable {
    case running
    case exited(status: Int32?)
}

/// Pure in-memory PTY output and lifecycle state for renderer consumption.
public struct PtyOutputBuffer: Sendable {
    private var pending: [UInt8]
    private(set) public var lifecycle: PtyLifecycle
    private(set) public var cwd: String?
    private(set) public var process: String?

    public init() {
        pending = []
        lifecycle = .running
        cwd = nil
        process = nil
    }

    public var pendingByteCount: Int {
        pending.count
    }

    public mutating func append(_ bytes: [UInt8]) {
        pending.append(contentsOf: bytes)
    }

    /// Returns accumulated bytes and clears the pending buffer for the next frame.
    public mutating func drain() -> [UInt8] {
        let drained = pending
        pending.removeAll(keepingCapacity: true)
        return drained
    }

    public mutating func markExited(status: Int32?) {
        lifecycle = .exited(status: status)
    }

    public mutating func updateMetadata(cwd: String?, process: String?) {
        self.cwd = cwd
        self.process = process
    }
}

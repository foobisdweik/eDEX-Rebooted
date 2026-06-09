import Foundation

public struct TerminalSpawnRequest: Equatable, Sendable {
    public static let defaultCols: UInt16 = 80
    public static let defaultRows: UInt16 = 24
    private static let fallbackShell = "/bin/zsh"

    public var shell: String
    public var args: [String]
    public var cwd: String
    public var env: [String: String]
    public var cols: UInt16
    public var rows: UInt16

    public init(
        shell: String,
        args: [String],
        cwd: String,
        env: [String: String],
        cols: UInt16,
        rows: UInt16
    ) {
        self.shell = shell
        self.args = args
        self.cwd = cwd
        self.env = env
        self.cols = cols
        self.rows = rows
    }

    /// Builds spawn options with macOS defaults. Empty `args` means the Rust PTY
    /// layer adds `--login` for a login shell (`crates/edex-core/src/pty.rs`).
    public static func make(
        shell: String? = nil,
        args: [String]? = nil,
        cwd: String? = nil,
        env: [String: String]? = nil,
        cols: Double? = nil,
        rows: Double? = nil,
        environment processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TerminalSpawnRequest {
        let resolvedShell: String
        if let shell, !shell.isEmpty {
            resolvedShell = shell
        } else if let envShell = processEnvironment["SHELL"], !envShell.isEmpty {
            resolvedShell = envShell
        } else {
            resolvedShell = fallbackShell
        }

        let resolvedCwd: String
        if let cwd, !cwd.isEmpty {
            resolvedCwd = cwd
        } else {
            resolvedCwd = NSHomeDirectory()
        }

        return TerminalSpawnRequest(
            shell: resolvedShell,
            args: args ?? [],
            cwd: resolvedCwd,
            env: env ?? [:],
            cols: TerminalNumericSupport.clampedDimension(cols, default: defaultCols),
            rows: TerminalNumericSupport.clampedDimension(rows, default: defaultRows)
        )
    }
}

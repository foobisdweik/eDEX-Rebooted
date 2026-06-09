import XCTest
@testable import EdexDomainSupport

final class NativeTerminalTests: XCTestCase {
    // MARK: - TerminalSpawnRequest

    func testDefaultShellUsesEnvShellWhenSet() {
        let request = TerminalSpawnRequest.make(
            environment: ["SHELL": "/bin/custom-shell"]
        )
        XCTAssertEqual(request.shell, "/bin/custom-shell")
    }

    func testDefaultShellFallsBackToZsh() {
        let request = TerminalSpawnRequest.make(environment: [:])
        XCTAssertEqual(request.shell, "/bin/zsh")
    }

    func testDefaultCwdIsHomeDirectory() {
        let home = NSHomeDirectory()
        let request = TerminalSpawnRequest.make()
        XCTAssertEqual(request.cwd, home)
    }

    func testDefaultArgsAreEmptyForLoginShell() {
        let request = TerminalSpawnRequest.make()
        XCTAssertTrue(request.args.isEmpty)
    }

    func testExplicitSpawnValuesArePreserved() {
        let request = TerminalSpawnRequest.make(
            shell: "/bin/bash",
            args: ["-i"],
            cwd: "/tmp",
            env: ["FOO": "bar"],
            cols: 120,
            rows: 40
        )
        XCTAssertEqual(request.shell, "/bin/bash")
        XCTAssertEqual(request.args, ["-i"])
        XCTAssertEqual(request.cwd, "/tmp")
        XCTAssertEqual(request.env, ["FOO": "bar"])
        XCTAssertEqual(request.cols, 120)
        XCTAssertEqual(request.rows, 40)
    }

    func testColsRowsClampToMinimumOne() {
        let request = TerminalSpawnRequest.make(cols: 0, rows: -5)
        XCTAssertEqual(request.cols, 1)
        XCTAssertEqual(request.rows, 1)
    }

    func testColsRowsRejectNonFiniteAndUseDefaults() {
        let request = TerminalSpawnRequest.make(cols: .infinity, rows: .nan)
        XCTAssertEqual(request.cols, TerminalSpawnRequest.defaultCols)
        XCTAssertEqual(request.rows, TerminalSpawnRequest.defaultRows)
    }

    func testColsRowsRejectOutOfRangeAndUseDefaults() {
        let request = TerminalSpawnRequest.make(cols: 100_000, rows: -Double.infinity)
        XCTAssertEqual(request.cols, TerminalSpawnRequest.defaultCols)
        XCTAssertEqual(request.rows, 1)
    }

    func testEmptyEnvShellFallsBackToZsh() {
        let request = TerminalSpawnRequest.make(environment: ["SHELL": ""])
        XCTAssertEqual(request.shell, "/bin/zsh")
    }

    func testEmptyExplicitShellUsesEnvThenFallback() {
        let fromEnv = TerminalSpawnRequest.make(shell: "", environment: ["SHELL": "/bin/bash"])
        XCTAssertEqual(fromEnv.shell, "/bin/bash")

        let fallback = TerminalSpawnRequest.make(shell: "", environment: [:])
        XCTAssertEqual(fallback.shell, "/bin/zsh")
    }

    func testEmptyCwdFallsBackToHome() {
        let request = TerminalSpawnRequest.make(cwd: "")
        XCTAssertEqual(request.cwd, NSHomeDirectory())
    }

    // MARK: - PtyOutputBuffer

    func testInitialStateIsRunningWithEmptyBuffer() {
        var buffer = PtyOutputBuffer()
        XCTAssertEqual(buffer.lifecycle, .running)
        XCTAssertTrue(buffer.drain().isEmpty)
        XCTAssertNil(buffer.cwd)
        XCTAssertNil(buffer.process)
    }

    func testAppendAndDrainReturnsBytesAndClears() {
        var buffer = PtyOutputBuffer()
        buffer.append([0x48, 0x69])
        buffer.append([0x21])

        XCTAssertEqual(buffer.drain(), [0x48, 0x69, 0x21])
        XCTAssertTrue(buffer.drain().isEmpty)
    }

    func testMultipleAppendsCoalesceBeforeDrain() {
        var buffer = PtyOutputBuffer()
        buffer.append([1, 2])
        buffer.append([3])

        XCTAssertEqual(buffer.pendingByteCount, 3)
        XCTAssertEqual(buffer.drain(), [1, 2, 3])
    }

    func testMarkExitedRecordsStatus() {
        var buffer = PtyOutputBuffer()
        buffer.markExited(status: 42)

        XCTAssertEqual(buffer.lifecycle, .exited(status: 42))
    }

    func testMarkExitedAllowsNilStatus() {
        var buffer = PtyOutputBuffer()
        buffer.markExited(status: nil)

        XCTAssertEqual(buffer.lifecycle, .exited(status: nil))
    }

    func testUpdateMetadataStoresCwdAndProcess() {
        var buffer = PtyOutputBuffer()
        buffer.updateMetadata(cwd: "/Users/test", process: "zsh")

        XCTAssertEqual(buffer.cwd, "/Users/test")
        XCTAssertEqual(buffer.process, "zsh")
    }

    func testAppendAfterExitStillAccumulatesBytes() {
        var buffer = PtyOutputBuffer()
        buffer.markExited(status: 0)
        buffer.append([0x0A])

        XCTAssertEqual(buffer.lifecycle, .exited(status: 0))
        XCTAssertEqual(buffer.drain(), [0x0A])
    }
}

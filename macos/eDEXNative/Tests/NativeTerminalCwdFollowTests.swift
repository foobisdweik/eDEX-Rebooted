import XCTest
@testable import EdexDomainSupport

final class NativeTerminalCwdFollowTests: XCTestCase {
    func testNilCwdIsIgnored() {
        XCTAssertEqual(
            TerminalCwdFollow.decide(newCwd: nil, lastFollowedCwd: "/home", isDiskView: false),
            .ignore
        )
    }

    func testEmptyCwdIsIgnored() {
        XCTAssertEqual(
            TerminalCwdFollow.decide(newCwd: "", lastFollowedCwd: nil, isDiskView: false),
            .ignore
        )
    }

    func testDiskViewSuppressesFollow() {
        XCTAssertEqual(
            TerminalCwdFollow.decide(newCwd: "/etc", lastFollowedCwd: "/home", isDiskView: true),
            .ignore
        )
    }

    func testUnchangedCwdIsIgnored() {
        XCTAssertEqual(
            TerminalCwdFollow.decide(newCwd: "/home/user", lastFollowedCwd: "/home/user", isDiskView: false),
            .ignore
        )
    }

    func testFirstObservationNavigates() {
        XCTAssertEqual(
            TerminalCwdFollow.decide(newCwd: "/home/user", lastFollowedCwd: nil, isDiskView: false),
            .navigate("/home/user")
        )
    }

    func testChangedCwdNavigatesToNewPath() {
        XCTAssertEqual(
            TerminalCwdFollow.decide(newCwd: "/var/log", lastFollowedCwd: "/home/user", isDiskView: false),
            .navigate("/var/log")
        )
    }
}

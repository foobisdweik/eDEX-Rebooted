import XCTest
@testable import SysinfoSupport

final class NativeSysinfoTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    // MARK: - Date (mirrors sysinfo.class.js updateDate)

    func testDateProducesYearAndUppercaseMonthAbbreviation() {
        let instant = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 6,
            day: 1
        ).date!

        let value = EdexSysinfoFormatter(timeZone: utc).date(instant)
        XCTAssertEqual(value.year, "2026")
        XCTAssertEqual(value.monthDay, "JUN 1")
    }

    func testDateDoesNotZeroPadDayOfMonth() {
        let instant = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 1,
            day: 9
        ).date!

        let value = EdexSysinfoFormatter(timeZone: utc).date(instant)
        XCTAssertEqual(value.monthDay, "JAN 9")
    }

    // MARK: - Uptime (mirrors sysinfo.class.js updateUptime)

    func testUptimeSplitsDaysHoursMinutesAndZeroPadsTime() {
        // 2 days, 3 hours, 5 minutes, 40 seconds
        let seconds: UInt64 = (2 * 86400) + (3 * 3600) + (5 * 60) + 40
        let value = EdexSysinfoFormatter().uptime(seconds: seconds)
        XCTAssertEqual(value.days, 2)
        XCTAssertEqual(value.hours, "03")
        XCTAssertEqual(value.minutes, "05")
        XCTAssertEqual(value.text, "2d03:05")
    }

    func testUptimeDoesNotZeroPadDaysAndDropsSeconds() {
        // 12 days, 0 hours, 9 minutes, 59 seconds -> seconds dropped
        let seconds: UInt64 = (12 * 86400) + (9 * 60) + 59
        let value = EdexSysinfoFormatter().uptime(seconds: seconds)
        XCTAssertEqual(value.text, "12d00:09")
    }

    // MARK: - Power (mirrors sysinfo.class.js updateBattery)

    func testPowerChargingTakesPrecedence() {
        let state = EdexPowerState(hasBattery: true, isCharging: true, acConnected: true, percent: 80)
        XCTAssertEqual(EdexSysinfoFormatter().power(state), "CHARGE")
    }

    func testPowerWiredWhenAcConnectedButNotCharging() {
        let state = EdexPowerState(hasBattery: true, isCharging: false, acConnected: true, percent: 100)
        XCTAssertEqual(EdexSysinfoFormatter().power(state), "WIRED")
    }

    func testPowerShowsPercentWhenOnBattery() {
        let state = EdexPowerState(hasBattery: true, isCharging: false, acConnected: false, percent: 77)
        XCTAssertEqual(EdexSysinfoFormatter().power(state), "77%")
    }

    func testPowerShowsOnWhenNoBattery() {
        let state = EdexPowerState(hasBattery: false, isCharging: false, acConnected: true, percent: 0)
        XCTAssertEqual(EdexSysinfoFormatter().power(state), "ON")
    }

    // MARK: - Type

    func testSystemTypeIsMacOS() {
        XCTAssertEqual(EdexSysinfoFormatter().systemType, "macOS")
    }
}

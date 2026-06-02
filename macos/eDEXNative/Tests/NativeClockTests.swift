import XCTest
@testable import ClockSupport

final class NativeClockTests: XCTestCase {
    func testTwentyFourHourClockZeroPadsComponents() {
        let instant = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 6,
            day: 1,
            hour: 9,
            minute: 5,
            second: 7
        ).date!

        XCTAssertEqual(
            EdexClockFormatter(clockHours: 24, timeZone: TimeZone(secondsFromGMT: 0)!).format(instant).text,
            "09:05:07"
        )
    }

    func testTwelveHourClockHandlesMidnightNoonAndAfternoon() {
        let formatter = EdexClockFormatter(clockHours: 12, timeZone: TimeZone(secondsFromGMT: 0)!)
        let calendar = Calendar(identifier: .gregorian)
        let base = DateComponents(calendar: calendar, timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 6, day: 1)

        XCTAssertEqual(formatter.format(base.date(hour: 0, minute: 1, second: 2)).text, "12:01:02 AM")
        XCTAssertEqual(formatter.format(base.date(hour: 12, minute: 0, second: 0)).text, "12:00:00 PM")
        XCTAssertEqual(formatter.format(base.date(hour: 15, minute: 4, second: 5)).text, "03:04:05 PM")
    }

    func testInvalidClockHoursFallsBackToTwentyFourHourMode() {
        let instant = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 6,
            day: 1,
            hour: 23,
            minute: 59,
            second: 58
        ).date!

        XCTAssertFalse(EdexClockFormatter(clockHours: 13).usesTwelveHourClock)
        XCTAssertEqual(
            EdexClockFormatter(clockHours: 13, timeZone: TimeZone(secondsFromGMT: 0)!).format(instant).text,
            "23:59:58"
        )
    }
}

private extension DateComponents {
    func date(hour: Int, minute: Int, second: Int) -> Date {
        var copy = self
        copy.hour = hour
        copy.minute = minute
        copy.second = second
        return copy.date!
    }
}

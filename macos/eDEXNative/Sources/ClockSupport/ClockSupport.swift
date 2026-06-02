import Foundation

public struct EdexClockFormatter: Sendable {
    public let clockHours: Int
    public let timeZone: TimeZone

    public init(clockHours: Int, timeZone: TimeZone = .current) {
        self.clockHours = clockHours == 12 ? 12 : 24
        self.timeZone = timeZone
    }

    public var usesTwelveHourClock: Bool {
        clockHours == 12
    }

    public func format(_ date: Date) -> EdexClockValue {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let rawHour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0

        if usesTwelveHourClock {
            let meridiem = rawHour >= 12 ? "PM" : "AM"
            var hour = rawHour
            if hour > 12 {
                hour -= 12
            } else if hour == 0 {
                hour = 12
            }
            return EdexClockValue(
                time: "\(hour.twoDigits):\(minute.twoDigits):\(second.twoDigits)",
                meridiem: meridiem
            )
        }

        return EdexClockValue(
            time: "\(rawHour.twoDigits):\(minute.twoDigits):\(second.twoDigits)",
            meridiem: nil
        )
    }
}

public struct EdexClockValue: Equatable, Sendable {
    public let time: String
    public let meridiem: String?

    public init(time: String, meridiem: String?) {
        self.time = time
        self.meridiem = meridiem
    }

    public var text: String {
        if let meridiem {
            return "\(time) \(meridiem)"
        }
        return time
    }
}

private extension Int {
    var twoDigits: String {
        self < 10 ? "0\(self)" : "\(self)"
    }
}

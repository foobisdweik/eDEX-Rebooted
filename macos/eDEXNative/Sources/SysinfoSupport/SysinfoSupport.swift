import Foundation

/// Formats the four sysinfo panel cells (date / uptime / type / power) to match
/// the legacy `src/classes/sysinfo.class.js` exactly. Pure and FFI-free so it can
/// be unit-tested without the Rust dylib, mirroring `ClockSupport`.
public struct EdexSysinfoFormatter: Sendable {
    public let timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    /// The OS label. The Tauri port targets aarch64-apple-darwin exclusively,
    /// so this is a constant — matching the JS panel's hard-coded "macOS".
    public var systemType: String { "macOS" }

    public func date(_ date: Date) -> EdexSysinfoDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let monthIndex = (components.month ?? 1) - 1
        let day = components.day ?? 1

        let month = Self.monthAbbreviations.indices.contains(monthIndex)
            ? Self.monthAbbreviations[monthIndex]
            : ""

        return EdexSysinfoDate(year: "\(year)", monthDay: "\(month) \(day)")
    }

    public func uptime(seconds: UInt64) -> EdexUptimeValue {
        var raw = seconds
        let days = raw / 86400
        raw -= days * 86400
        let hours = raw / 3600
        raw -= hours * 3600
        let minutes = raw / 60

        return EdexUptimeValue(
            days: Int(days),
            hours: hours.twoDigits,
            minutes: minutes.twoDigits
        )
    }

    public func power(_ state: EdexPowerState) -> String {
        guard state.hasBattery else { return "ON" }
        if state.isCharging { return "CHARGE" }
        if state.acConnected { return "WIRED" }
        return "\(state.percent)%"
    }

    private static let monthAbbreviations = [
        "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
        "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"
    ]
}

public struct EdexSysinfoDate: Equatable, Sendable {
    public let year: String
    public let monthDay: String

    public init(year: String, monthDay: String) {
        self.year = year
        self.monthDay = monthDay
    }
}

public struct EdexUptimeValue: Equatable, Sendable {
    public let days: Int
    public let hours: String
    public let minutes: String

    public init(days: Int, hours: String, minutes: String) {
        self.days = days
        self.hours = hours
        self.minutes = minutes
    }

    public var text: String {
        "\(days)d\(hours):\(minutes)"
    }
}

public struct EdexPowerState: Equatable, Sendable {
    public let hasBattery: Bool
    public let isCharging: Bool
    public let acConnected: Bool
    public let percent: Int

    public init(hasBattery: Bool, isCharging: Bool, acConnected: Bool, percent: Int) {
        self.hasBattery = hasBattery
        self.isCharging = isCharging
        self.acConnected = acConnected
        self.percent = percent
    }
}

private extension UInt64 {
    var twoDigits: String {
        self < 10 ? "0\(self)" : "\(self)"
    }
}

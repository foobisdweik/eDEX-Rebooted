import Foundation

public struct EdexTopProcessRow: Equatable, Sendable, Identifiable {
    public let pid: UInt32
    public let name: String
    public let cpu: Double
    public let mem: Double

    public init(pid: UInt32, name: String, cpu: Double, mem: Double) {
        self.pid = pid
        self.name = name
        self.cpu = cpu
        self.mem = mem
    }

    public var id: UInt32 { pid }
}

public struct EdexProcessRow: Equatable, Sendable, Identifiable {
    public let pid: UInt32
    public let name: String
    public let user: String
    public let cpu: Double
    public let mem: Double
    public let state: String
    public let started: String

    public init(pid: UInt32, name: String, user: String, cpu: Double, mem: Double, state: String, started: String) {
        self.pid = pid
        self.name = name
        self.user = user
        self.cpu = cpu
        self.mem = mem
        self.state = state
        self.started = started
    }

    public var id: UInt32 { pid }
}

public enum EdexProcessSortField: String, CaseIterable, Equatable, Sendable {
    case pid = "PID"
    case name = "Name"
    case user = "User"
    case cpu = "CPU"
    case memory = "Memory"
    case state = "State"
    case started = "Started"
    case runtime = "Runtime"
}

public enum EdexProcessSort: Equatable, Sendable {
    case `default`
    case field(EdexProcessSortField, ascending: Bool)

    public func toggled(_ field: EdexProcessSortField) -> Self {
        switch self {
        case .default:
            return .field(field, ascending: false)
        case let .field(currentField, ascending) where currentField == field:
            return ascending ? .default : .field(field, ascending: true)
        case .field:
            return .field(field, ascending: false)
        }
    }
}

public struct EdexToplistFormatter: Sendable {
    public init() {}

    public func percentText(_ value: Double) -> String {
        guard value.isFinite else { return "0%" }
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))%"
        }
        return "\(rounded)%"
    }

    public func sorted(_ rows: [EdexProcessRow], sort: EdexProcessSort, now: Date = Date()) -> [EdexProcessRow] {
        rows.sorted { lhs, rhs in
            switch sort {
            case .default:
                return score(lhs) > score(rhs)
            case let .field(field, ascending):
                return compare(lhs, rhs, by: field, ascending: ascending, now: now)
            }
        }
    }

    public func runtimeText(started: Date, now: Date = Date()) -> String {
        let totalSeconds = max(0, Int(now.timeIntervalSince(started)))
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return "\(pad(days)):\(pad(hours)):\(pad(minutes)):\(pad(seconds))"
    }

    public func runtimeText(started: String, now: Date = Date()) -> String {
        guard let date = Self.date(from: started) else {
            return "00:00:00:00"
        }
        return runtimeText(started: date, now: now)
    }

    private func compare(
        _ lhs: EdexProcessRow,
        _ rhs: EdexProcessRow,
        by field: EdexProcessSortField,
        ascending: Bool,
        now: Date
    ) -> Bool {
        switch field {
        case .pid:
            return ordered(Double(lhs.pid), Double(rhs.pid), ascending: ascending)
        case .name:
            return ordered(lhs.name, rhs.name, ascending: ascending)
        case .user:
            return ordered(lhs.user, rhs.user, ascending: ascending)
        case .cpu:
            return ordered(safe(lhs.cpu), safe(rhs.cpu), ascending: ascending)
        case .memory:
            return ordered(safe(lhs.mem), safe(rhs.mem), ascending: ascending)
        case .state:
            return ordered(lhs.state, rhs.state, ascending: ascending)
        case .started:
            return ordered(dateSeconds(lhs.started), dateSeconds(rhs.started), ascending: ascending)
        case .runtime:
            return ordered(runtimeSeconds(lhs.started, now: now), runtimeSeconds(rhs.started, now: now), ascending: ascending)
        }
    }

    private func score(_ row: EdexProcessRow) -> Double {
        safe(row.cpu) * 100 + safe(row.mem)
    }

    private func safe(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    private func ordered(_ lhs: Double, _ rhs: Double, ascending: Bool) -> Bool {
        ascending ? lhs < rhs : lhs > rhs
    }

    private func ordered(_ lhs: String, _ rhs: String, ascending: Bool) -> Bool {
        let comparison = lhs.localizedCaseInsensitiveCompare(rhs)
        return ascending ? comparison == .orderedDescending : comparison == .orderedAscending
    }

    private func dateSeconds(_ value: String) -> Double {
        Self.date(from: value)?.timeIntervalSince1970 ?? 0
    }

    private func runtimeSeconds(_ value: String, now: Date) -> Double {
        guard let started = Self.date(from: value) else { return 0 }
        return max(0, now.timeIntervalSince(started))
    }

    private static func date(from value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

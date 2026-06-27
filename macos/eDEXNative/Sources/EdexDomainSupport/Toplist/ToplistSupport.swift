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

/// Finding #4 (List 3): a process row with its `started` date parsed once and
/// its CPU/MEM percentages pre-formatted, so the table's per-second
/// `TimelineView` ticks no longer re-parse ISO8601 strings (per comparison
/// during a started/runtime sort, and per visible row for the runtime column).
public struct EdexPreparedProcessRow: Equatable, Sendable, Identifiable {
    public let pid: UInt32
    public let name: String
    public let user: String
    public let cpuText: String
    public let memText: String
    public let state: String
    public let started: String
    public let startDate: Date?

    public init(
        pid: UInt32,
        name: String,
        user: String,
        cpuText: String,
        memText: String,
        state: String,
        started: String,
        startDate: Date?
    ) {
        self.pid = pid
        self.name = name
        self.user = user
        self.cpuText = cpuText
        self.memText = memText
        self.state = state
        self.started = started
        self.startDate = startDate
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
        guard rounded.isFinite else { return "0%" }
        if rounded.rounded() == rounded, rounded >= Double(Int.min), rounded < Double(Int.max) {
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

    /// Finding #4: parse every `started` once, sort, and pre-format CPU/MEM —
    /// equivalent to `sorted(_:sort:now:)` followed by per-cell formatting, but
    /// without re-parsing dates inside the sort comparator. `now` fixes the
    /// runtime ordering at preparation time (runtime order is invariant as the
    /// clock advances, so this matches the per-tick `sorted` ordering).
    public func prepared(
        _ rows: [EdexProcessRow],
        sort: EdexProcessSort,
        now: Date = Date()
    ) -> [EdexPreparedProcessRow] {
        let dated = rows.map { (row: $0, date: Self.date(from: $0.started)) }
        let sorted = dated.sorted { lhs, rhs in
            switch sort {
            case .default:
                return score(lhs.row) > score(rhs.row)
            case let .field(field, ascending):
                return comparePrepared(lhs, rhs, by: field, ascending: ascending, now: now)
            }
        }
        return sorted.map { entry in
            EdexPreparedProcessRow(
                pid: entry.row.pid,
                name: entry.row.name,
                user: entry.row.user,
                cpuText: percentText(entry.row.cpu),
                memText: percentText(entry.row.mem),
                state: entry.row.state,
                started: entry.row.started,
                startDate: entry.date
            )
        }
    }

    private func comparePrepared(
        _ lhs: (row: EdexProcessRow, date: Date?),
        _ rhs: (row: EdexProcessRow, date: Date?),
        by field: EdexProcessSortField,
        ascending: Bool,
        now: Date
    ) -> Bool {
        switch field {
        case .pid:
            return ordered(Double(lhs.row.pid), Double(rhs.row.pid), ascending: ascending)
        case .name:
            return ordered(lhs.row.name, rhs.row.name, ascending: ascending)
        case .user:
            return ordered(lhs.row.user, rhs.row.user, ascending: ascending)
        case .cpu:
            return ordered(safe(lhs.row.cpu), safe(rhs.row.cpu), ascending: ascending)
        case .memory:
            return ordered(safe(lhs.row.mem), safe(rhs.row.mem), ascending: ascending)
        case .state:
            return ordered(lhs.row.state, rhs.row.state, ascending: ascending)
        case .started:
            return ordered(seconds(lhs.date), seconds(rhs.date), ascending: ascending)
        case .runtime:
            return ordered(runtime(lhs.date, now: now), runtime(rhs.date, now: now), ascending: ascending)
        }
    }

    private func seconds(_ date: Date?) -> Double {
        date?.timeIntervalSince1970 ?? 0
    }

    private func runtime(_ date: Date?, now: Date) -> Double {
        guard let date else { return 0 }
        return max(0, now.timeIntervalSince(date))
    }

    public func runtimeText(started: Date, now: Date = Date()) -> String {
        let diff = now.timeIntervalSince(started)
        guard diff.isFinite, diff >= Double(Int.min), diff < Double(Int.max) else {
            return "00:00:00:00"
        }
        let totalSeconds = max(0, Int(diff))
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
        return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
    }

    private func dateSeconds(_ value: String) -> Double {
        Self.date(from: value)?.timeIntervalSince1970 ?? 0
    }

    private func runtimeSeconds(_ value: String, now: Date) -> Double {
        guard let started = Self.date(from: value) else { return 0 }
        return max(0, now.timeIntervalSince(started))
    }

    private static let iso8601Formatter = ISO8601DateFormatter()

    private static func date(from value: String) -> Date? {
        iso8601Formatter.date(from: value)
    }

    private func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

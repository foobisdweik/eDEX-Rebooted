import Foundation

/// Pure logic for the native cpuinfo panel — CPU name, the lower/upper core
/// split, rolling averages, and footer cell formatting — mirroring
/// `src/classes/cpuinfo.class.js`. FFI-free so it unit-tests without the Rust
/// dylib, like `SysinfoSupport`. The live-graph rendering lives in the view.
public struct EdexCpuinfoFormatter: Sendable {
    public init() {}

    /// `cpu.manufacturer + cpu.brand`, truncated to 30 characters (legacy
    /// `cpuName.substr(0, 30)`; the legacy's follow-up `substr` is a discarded
    /// no-op, so the effective behaviour is a hard 30-char cap).
    public func cpuName(manufacturer: String, brand: String) -> String {
        String((manufacturer + brand).prefix(30))
    }

    /// `Math.floor(cores / 2)` — the index splitting the lower and upper graphs.
    public func divide(cores: Int) -> Int {
        cores / 2
    }

    /// Which graph a logical core belongs to: lower half → 0, upper half → 1
    /// (legacy `i < divide ? charts[0] : charts[1]`).
    public func chartIndex(forCore core: Int, divide: Int) -> Int {
        core < divide ? 0 : 1
    }

    /// Rounded mean of a graph half's per-core loads (legacy
    /// `Math.round(sum / length)`). Empty → 0 (the legacy would yield `NaN`).
    public func average(loads: [Double]) -> Int {
        guard !loads.isEmpty else { return 0 }
        let mean = loads.reduce(0, +) / Double(loads.count)
        return Int(mean.rounded())
    }

    /// TEMP cell: the number (integers without a decimal point) + `°C`.
    public func temperatureText(_ celsius: Double) -> String {
        "\(Self.number(celsius))°C"
    }

    /// SPD / MAX cells: the backend already provides a formatted GHz string.
    public func speedText(_ ghz: String) -> String {
        "\(ghz)GHz"
    }

    /// TASKS cell: the raw process count.
    public func tasksText(_ count: Int) -> String {
        "\(count)"
    }

    /// JS-style number stringification: whole numbers print without a trailing
    /// `.0`, fractional values keep their decimals.
    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// Fixed-capacity per-core sample history feeding the two scrolling graphs.
/// Oldest samples are evicted once a series exceeds `capacity` (FIFO).
public struct CpuSeriesBuffer: Sendable {
    public let coreCount: Int
    public let capacity: Int
    public private(set) var series: [[Double]]

    public init(coreCount: Int, capacity: Int) {
        self.coreCount = max(0, coreCount)
        self.capacity = max(1, capacity)
        self.series = Array(repeating: [], count: self.coreCount)
    }

    /// Append one sample per core. Cores missing from `loads` get a 0 sample so
    /// every series stays the same length (legacy appends per reported CPU).
    public mutating func append(loads: [Double]) {
        guard coreCount > 0 else { return }
        for index in 0..<coreCount {
            let value = index < loads.count ? loads[index] : 0
            series[index].append(value)
            if series[index].count > capacity {
                series[index].removeFirst(series[index].count - capacity)
            }
        }
    }
}

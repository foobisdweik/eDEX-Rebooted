import EdexCoreBridge
import EdexDomainSupport
import EdexRenderingSupport
import SwiftUI

// Finding #5: the CPU, RAM, and TOPLIST panels used to be `private func`s on
// ContentView, so their high-frequency telemetry reads (`state.cpu` 1 Hz,
// `state.mem` ~1.5 Hz, `state.topProcesses` 5 s) were attributed to
// `ContentView.body` — every sample re-evaluated the entire shell (layout,
// terminal, keyboard, every other panel). Extracting them into dedicated
// `View` structs gives each one its own observation boundary: a CPU sample now
// invalidates only `CpuPanel`, a memory sample only `RamPanel`, etc. The render
// bodies are unchanged, so the visual output is identical.

struct CpuPanel: View {
    let state: ShellState
    let vh: Double
    private let cpuFormatter = EdexCpuinfoFormatter()

    var body: some View {
        let snapshot = state.cpu
        let cores = Int(snapshot?.cores ?? 0)
        let divide = cpuFormatter.divide(cores: cores)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("CPU USAGE")
                    .font(.custom(state.theme.fonts.main, size: 12))
                Text(snapshot.map { cpuFormatter.cpuName(manufacturer: $0.manufacturer, brand: $0.brand) } ?? "")
                    .font(.custom(state.theme.fonts.terminal, size: 10))
                    .foregroundStyle(state.theme.accent70)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            cpuGraphBlock(chart: 0, rangeStart: 1, rangeEnd: divide, divide: divide, cores: cores, snapshot: snapshot, sampleDate: state.cpuLastSampleDate)
            cpuGraphBlock(chart: 1, rangeStart: divide + 1, rangeEnd: cores, divide: divide, cores: cores, snapshot: snapshot, sampleDate: state.cpuLastSampleDate)
            HStack(spacing: 0) {
                cpuFooterCell("TEMP", snapshot.map { cpuFormatter.temperatureText($0.temperatureMax) } ?? "--°C")
                cpuFooterCell("SPD", snapshot.map { cpuFormatter.speedText($0.speed) } ?? "--GHz")
                cpuFooterCell("MAX", snapshot.map { cpuFormatter.speedText($0.speedMax) } ?? "--GHz")
                cpuFooterCell("TASKS", snapshot.map { cpuFormatter.tasksText(Int($0.processCount)) } ?? "---")
            }
            .padding(.top, 3)
            .overlay(alignment: .top) {
                Rectangle().fill(state.theme.accent30).frame(height: 1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .augmentedSurface(
            style: .panel(vh: vh),
            fill: state.theme.terminalBackground72,
            stroke: state.theme.accent
        )
        .task {
            // cpuinfo.class.js polls panelSnapshot every 1s.
            while !Task.isCancelled {
                await state.refreshCpu()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func cpuGraphBlock(
        chart: Int,
        rangeStart: Int,
        rangeEnd: Int,
        divide: Int,
        cores: Int,
        snapshot: FfiCpuSnapshot?,
        sampleDate: Date
    ) -> some View {
        CpuGraphHalfBlock(
            theme: state.theme,
            chart: chart,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            divide: divide,
            cores: cores,
            snapshot: snapshot,
            sampleDate: sampleDate,
            state: state
        )
    }

    private func cpuFooterCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.custom(state.theme.fonts.main, size: 9))
                .foregroundStyle(state.theme.accent70)
            Text(value)
                .font(.custom(state.theme.fonts.terminal, size: 11))
                .foregroundStyle(state.theme.terminalForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CpuGraphHalfBlock: View {
    let theme: NativeTheme
    let chart: Int
    let rangeStart: Int
    let rangeEnd: Int
    let divide: Int
    let cores: Int
    let snapshot: FfiCpuSnapshot?
    let sampleDate: Date
    let state: ShellState

    @State private var memoKey = ""
    @State private var memoAvg: Int?

    private let cpuFormatter = EdexCpuinfoFormatter()

    var body: some View {
        let loads = snapshot?.loads ?? []
        let key = Self.avgMemoKey(loads: loads, sampleDate: sampleDate, chart: chart, divide: divide, cores: cores)
        let avg: Int? = {
            if key == memoKey { return memoAvg }
            guard snapshot != nil else { return nil }
            let halfLoads = loads.enumerated()
                .filter { cpuFormatter.chartIndex(forCore: $0.offset, divide: divide) == chart }
                .map(\.element)
            return cpuFormatter.average(loads: halfLoads)
        }()

        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(cores > 0 ? "# \(rangeStart) - \(rangeEnd)" : "# --")
                Spacer(minLength: 4)
                Text(avg.map { "Avg. \($0)%" } ?? "Avg. --%")
            }
            .font(.custom(theme.fonts.terminal, size: 10))
            .foregroundStyle(theme.accent72)
            CpuScrollingGraph(state: state, chart: chart, divide: divide, cores: cores)
        }
        .onChange(of: key, initial: true) { _, newKey in
            guard newKey != memoKey else { return }
            memoKey = newKey
            if snapshot != nil {
                let halfLoads = loads.enumerated()
                    .filter { cpuFormatter.chartIndex(forCore: $0.offset, divide: divide) == chart }
                    .map(\.element)
                memoAvg = cpuFormatter.average(loads: halfLoads)
            } else {
                memoAvg = nil
            }
        }
    }

    private static func avgMemoKey(
        loads: [Double],
        sampleDate: Date,
        chart: Int,
        divide: Int,
        cores: Int
    ) -> String {
        let tail = loads.last.map { String($0) } ?? "nil"
        return "\(sampleDate.timeIntervalSinceReferenceDate)|\(loads.count)|\(tail)|\(chart)|\(divide)|\(cores)"
    }
}

/// Scrolling CPU graph for one core half; polyline rebuilds at the 1 Hz sample cadence.
private struct CpuScrollingGraph: View {
    let state: ShellState
    let chart: Int
    let divide: Int
    let cores: Int

    @State private var memoKey = ""
    @State private var memoChartSeries: [[Double]] = []

    private let cpuFormatter = EdexCpuinfoFormatter()

    var body: some View {
        let series = state.cpuSeries
        let accent = state.theme.accent
        let key = Self.seriesMemoKey(
            sampleDate: state.cpuLastSampleDate,
            series: series,
            cores: cores,
            chart: chart,
            divide: divide
        )
        let chartSeries: [[Double]] = key == memoKey && !memoChartSeries.isEmpty
            ? memoChartSeries
            : Self.filteredSeries(series: series, cores: cores, chart: chart, divide: divide, cpuFormatter: cpuFormatter)

        return CpuGraphLayerView(
            series: chartSeries,
            sampleDate: state.cpuLastSampleDate,
            accent: NSColor(accent),
            reducedMotion: state.settingsSummary.reducedMotion
        )
            .frame(height: 34)
            .overlay {
                CpuGraphFrameShape()
                    .stroke(state.theme.accent30, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
            .onChange(of: key, initial: true) { _, newKey in
                guard newKey != memoKey else { return }
                memoKey = newKey
                memoChartSeries = Self.filteredSeries(
                    series: series,
                    cores: cores,
                    chart: chart,
                    divide: divide,
                    cpuFormatter: cpuFormatter
                )
            }
    }

    private static func seriesMemoKey(
        sampleDate: Date,
        series: [[Double]],
        cores: Int,
        chart: Int,
        divide: Int
    ) -> String {
        let depth = series.first?.count ?? 0
        let tail = series.first?.last.map { String($0) } ?? "nil"
        return "\(sampleDate.timeIntervalSinceReferenceDate)|\(series.count)|\(depth)|\(tail)|\(chart)|\(divide)|\(cores)"
    }

    private static func filteredSeries(
        series: [[Double]],
        cores: Int,
        chart: Int,
        divide: Int,
        cpuFormatter: EdexCpuinfoFormatter
    ) -> [[Double]] {
        (0..<cores)
            .filter { cpuFormatter.chartIndex(forCore: $0, divide: divide) == chart && $0 < series.count }
            .map { series[$0] }
    }
}

/// Narrow AppKit escape hatch for the graph scroll: a `CAShapeLayer` whose
/// path is rebuilt at the 1 Hz sample cadence and panned by animating
/// `transform.translation.x` on the render server — zero main-thread and zero
/// rasterization work per frame.
private struct CpuGraphLayerView: NSViewRepresentable {
    let series: [[Double]]
    let sampleDate: Date
    let accent: NSColor
    let reducedMotion: Bool

    func makeNSView(context: Context) -> CpuGraphNSView {
        CpuGraphNSView()
    }

    func updateNSView(_ view: CpuGraphNSView, context: Context) {
        view.apply(
            series: series,
            sampleDate: sampleDate,
            accent: accent,
            reducedMotion: reducedMotion
        )
    }
}

private final class CpuGraphNSView: NSView {
    private let lineLayer = CAShapeLayer()
    private var series = [[Double]]()
    private var lastPannedSampleDate: Date?
    private var panTimer: Timer?
    private var panStart: CFTimeInterval = 0
    private var isReducedMotion = false

    deinit {
        panTimer?.invalidate()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        lineLayer.fillColor = nil
        lineLayer.lineWidth = 1.7
        lineLayer.lineJoin = .round
        layer?.addSublayer(lineLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CpuGraphNSView is code-only")
    }

    /// `CpuGraphScrollGeometry` produces top-left-origin coordinates.
    override var isFlipped: Bool { true }

    func apply(series: [[Double]], sampleDate: Date, accent: NSColor, reducedMotion: Bool) {
        self.series = series
        lineLayer.strokeColor = accent.cgColor
        rebuildPath()
        if reducedMotion {
            // Step once per sample: rest at the fully-panned position (where a
            // completed pan would land) with no inter-sample commits at all.
            isReducedMotion = true
            panTimer?.invalidate()
            panTimer = nil
            lastPannedSampleDate = sampleDate
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            lineLayer.transform = CATransform3DMakeTranslation(
                -CpuGraphScrollGeometry.scrollDistance, 0, 0
            )
            CATransaction.commit()
            return
        }
        let resumedMotion = isReducedMotion
        isReducedMotion = false
        if resumedMotion || lastPannedSampleDate != sampleDate {
            // On resume with an unchanged sample, rejoin the pan mid-flight
            // (elapsed time since the sample landed) instead of snapping the
            // fully-panned layer back to zero.
            let elapsed = resumedMotion && lastPannedSampleDate == sampleDate
                ? max(0, Date.now.timeIntervalSince(sampleDate))
                : 0
            lastPannedSampleDate = sampleDate
            startPan(elapsed: elapsed)
        }
    }

    override func layout() {
        super.layout()
        // Disable implicit actions: a bare frame assignment here would animate
        // (0.25 s default), letting the line visibly lag the borders on resize.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer.frame = bounds
        rebuildPath()
        CATransaction.commit()
    }

    private func rebuildPath() {
        let path = CGMutablePath()
        for samples in series {
            let points = CpuGraphScrollGeometry.points(
                samples: samples, width: bounds.width, height: bounds.height
            )
            guard points.count >= 2 else { continue }
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer.path = path
        CATransaction.commit()
    }

    /// Pan by stepping the layer transform from a 10 Hz timer instead of a
    /// render-server `CABasicAnimation`. A continuous CAAnimation keeps
    /// WindowServer compositing the (blended, translucent) window at the
    /// display's max refresh for as long as the app is visible — measured at a
    /// steady ~25% extra WindowServer CPU at idle, enough to make the rest of
    /// the macOS UI feel sluggish (`preferredFrameRateRange` is not honored
    /// here). Ten explicit transform commits per second keep the scroll
    /// visually smooth while letting the compositor (and ProMotion) idle
    /// between steps; each tick is a single transform set — no layout, no
    /// rasterization, no SwiftUI.
    private func startPan(elapsed: TimeInterval = 0) {
        panStart = CACurrentMediaTime() - elapsed
        if panTimer == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.panTick()
            }
            timer.tolerance = 0.02
            RunLoop.main.add(timer, forMode: .common)
            panTimer = timer
        }
        panTick()
    }

    private func panTick() {
        let progress = min(1, max(0, CACurrentMediaTime() - panStart))
        let isVisible = window?.occlusionState.contains(.visible) ?? false
        // Skip intermediate commits when nothing would be seen, but always
        // land the final transform so an occluded pan does not stall mid-scroll.
        if isVisible || progress >= 1 {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            lineLayer.transform = CATransform3DMakeTranslation(
                -CpuGraphScrollGeometry.scrollDistance * progress, 0, 0
            )
            CATransaction.commit()
        }
        // The pan rests fully panned once complete (a late sample holds it
        // there); stop ticking so an idle graph costs zero wakeups/commits.
        // The next sample's startPan() recreates the timer.
        if progress >= 1 {
            panTimer?.invalidate()
            panTimer = nil
        }
    }
}

/// The graph's dashed top/bottom frame lines as a single shape — replaces two
/// alignment overlays of nested `Rectangle`s, which added measurable
/// alignment-resolution work to every layout pass.
private struct CpuGraphFrameShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for y in CpuGraphScrollGeometry.borderLineYs(height: rect.height, lineWidth: 1) {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + y))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + y))
        }
        return path
    }
}

struct RamPanel: View {
    let state: ShellState
    let vh: Double
    private let ramFormatter = EdexRamwatcherFormatter()

    var body: some View {
        let mem = state.mem
        let active = mem.map { ramFormatter.activeCount(active: $0.active, total: $0.total) } ?? 0
        let available = mem.map { ramFormatter.availableCount(available: $0.available, free: $0.free, total: $0.total) } ?? 0
        let swapPct = mem.map { ramFormatter.swapPercent(used: $0.swapUsed, total: $0.swapTotal) } ?? 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("MEMORY")
                    .font(.custom(state.theme.fonts.main, size: 12))
                Spacer(minLength: 4)
                Text(mem.map { ramFormatter.infoText(active: $0.active, total: $0.total) } ?? "")
                    .font(.custom(state.theme.fonts.terminal, size: 9))
                    .foregroundStyle(state.theme.accent70)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            ramGrid(active: active, available: available)
            HStack(spacing: 8) {
                Text("SWAP")
                    .font(.custom(state.theme.fonts.main, size: 10))
                    .foregroundStyle(state.theme.accent70)
                ramSwapBar(percent: swapPct)
                Text(mem.map { ramFormatter.swapText(used: $0.swapUsed) } ?? "0 GiB")
                    .font(.custom(state.theme.fonts.terminal, size: 10))
                    .foregroundStyle(state.theme.terminalForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .augmentedSurface(
            style: .panel(vh: vh),
            fill: state.theme.terminalBackground72,
            stroke: state.theme.accent
        )
        .task {
            // ramwatcher.class.js polls every 1500ms.
            while !Task.isCancelled {
                await state.refreshMem()
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
    }

    private func ramGrid(active: Int, available: Int) -> some View {
        let cols = 40
        let rows = EdexRamwatcherFormatter.gridCellCount / 40 // 11
        return Canvas { ctx, size in
            guard size.width.isFinite, size.width > 0,
                  size.height.isFinite, size.height > 0 else { return }
            let ranks = state.ramGridRanks
            guard ranks.count == cols * rows else { return }
            let cellW = size.width / Double(cols)
            let cellH = size.height / Double(rows)
            let pad = min(cellW, cellH) * 0.16
            var activePath = Path()
            var availablePath = Path()
            var freePath = Path()
            for position in 0..<(cols * rows) {
                let column = position % cols
                let row = position / cols
                let tier = ramFormatter.cellState(rank: ranks[position], activeCount: active, availableCount: available)
                let rect = CGRect(
                    x: Double(column) * cellW + pad,
                    y: Double(row) * cellH + pad,
                    width: max(0.5, cellW - 2 * pad),
                    height: max(0.5, cellH - 2 * pad)
                )
                let cellPath = Path(roundedRect: rect, cornerRadius: 0.5)
                switch tier {
                case .active: activePath.addPath(cellPath)
                case .available: availablePath.addPath(cellPath)
                case .free: freePath.addPath(cellPath)
                }
            }
            ctx.fill(activePath, with: .color(state.theme.ramGridActive))
            ctx.fill(availablePath, with: .color(state.theme.ramGridAvailable))
            ctx.fill(freePath, with: .color(state.theme.ramGridFree))
        }
        .frame(height: 60)
    }

    private func ramSwapBar(percent: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(state.theme.accent20)
                Rectangle()
                    .fill(state.theme.accent)
                    .frame(width: geo.size.width * Double(min(max(percent, 0), 100)) / 100.0)
            }
        }
        .frame(height: 4)
    }
}

struct ToplistPanel: View {
    let state: ShellState
    let vh: Double
    private let toplistFormatter = EdexToplistFormatter()

    var body: some View {
        Button {
            state.openProcessListModal()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("TOP PROCESSES")
                        .font(.custom(state.theme.fonts.main, size: 12))
                    Spacer(minLength: 4)
                    Text("PID | NAME | CPU | MEM")
                        .font(.custom(state.theme.fonts.main, size: 9))
                        .foregroundStyle(state.theme.accent48)
                }
                VStack(spacing: 2) {
                    ForEach(state.topProcesses, id: \.pid) { row in
                        toplistMiniRow(row)
                    }
                    if state.topProcesses.isEmpty {
                        Text("NO PROCESS DATA")
                            .font(.custom(state.theme.fonts.terminal, size: 10))
                            .foregroundStyle(state.theme.terminalForeground52)
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
            .augmentedSurface(
                style: .panel(vh: vh),
                fill: state.theme.terminalBackground72,
                stroke: state.theme.accent
            )
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .task {
            // Compact top-five table. Polled every 5s (Finding #3): this panel is
            // the single producer of process-table data, and a 5s cadence keeps
            // OS process refreshes to 12/min while the modal is closed. The
            // expanded modal still polls at 1s while visible.
            while !Task.isCancelled {
                await state.refreshToplist()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func toplistMiniRow(_ row: FfiTopProcessRow) -> some View {
        HStack(spacing: 5) {
            Text("\(row.pid)")
                .frame(width: 42, alignment: .leading)
            Text(row.name)
                .foregroundStyle(state.theme.terminalForeground)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(toplistFormatter.percentText(row.cpu))
                .frame(width: 42, alignment: .trailing)
            Text(toplistFormatter.percentText(row.mem))
                .frame(width: 42, alignment: .trailing)
        }
        .font(.custom(state.theme.fonts.terminal, size: 10))
        .foregroundStyle(state.theme.accent86)
    }
}

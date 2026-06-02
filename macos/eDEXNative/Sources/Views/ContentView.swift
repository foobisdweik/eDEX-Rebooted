import BootSupport
import BorderSupport
import ClockSupport
import CpuinfoSupport
import HardwareSupport
import LayoutSupport
import ModalSupport
import RamwatcherSupport
import SettingsEditorSupport
import ShortcutsSupport
import SwiftUI
import SysinfoSupport
import ThemeSupport
import ToplistSupport

struct ContentView: View {
    @Bindable var state: ShellState
    private let layoutEngine = EdexLayoutEngine()
    private let cpuFormatter = EdexCpuinfoFormatter()
    private let ramFormatter = EdexRamwatcherFormatter()
    private let toplistFormatter = EdexToplistFormatter()

    var body: some View {
        GeometryReader { proxy in
            let layout = layoutEngine.layout(
                in: LayoutSize(
                    width: Double(proxy.size.width),
                    height: Double(proxy.size.height)
                )
            )

            ZStack(alignment: .topLeading) {
                background(size: proxy.size)
                column(layout.leftColumn, title: "PANEL", subtitle: "SYSTEM", side: .left, vh: layout.vh)
                mainShell(layout.mainShell, vh: layout.vh)
                column(layout.rightColumn, title: "PANEL", subtitle: "NETWORK", side: .right, vh: layout.vh)
                if !layout.filesystem.isHidden {
                    filesystem(layout.filesystem, vh: layout.vh)
                }
                keyboard(layout.keyboard, vh: layout.vh)
                statusRibbon(vh: layout.vh)
                modalLayer(size: proxy.size, vh: layout.vh)
                if state.bootStage != .complete {
                    BootView(state: state)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.4), value: state.bootStage)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .foregroundStyle(state.theme.accent)
        .overlay(alignment: .top) {
            // Transparent drag strip for the full-size-content titlebar.
            Color.clear
                .frame(height: 42)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
        }
    }

    private func background(size: CGSize) -> some View {
        ZStack {
            state.theme.palette.background.color
            EdexGridBackground(
                color: state.theme.palette.panelBackground.color.opacity(0.95),
                step: max(1, size.height * 0.0204),
                lineWidth: max(0.5, size.height * 0.00092)
            )
        }
        .ignoresSafeArea()
    }

    private func column(_ frame: LayoutRect, title: String, subtitle: String, side: ColumnSide, vh: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title, subtitle)
            Spacer(minLength: 0)
            ForEach(side.placeholders, id: \.self) { label in
                if label == "CLOCK" {
                    clockPanel(vh: vh)
                } else if label == "SYSINFO" {
                    sysinfoPanel(vh: vh)
                } else if label == "HARDWARE" {
                    hardwarePanel(vh: vh)
                } else if label == "CPU" {
                    cpuPanel(vh: vh)
                } else if label == "RAM" {
                    ramPanel(vh: vh)
                } else if label == "TOPLIST" {
                    toplistPanel(vh: vh)
                } else {
                    panelStub(label, vh: vh)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .augmentedSurface(
            style: .panel(vh: vh),
            fill: state.theme.panelBackground.opacity(0.82),
            stroke: state.theme.accent
        )
        .positioned(in: frame)
    }

    private func mainShell(_ frame: LayoutRect, vh: Double) -> some View {
        let shellStyle = AugmentedBorderStyle.mainShell(vh: vh)
        return VStack(alignment: .leading, spacing: 7) {
            sectionTitle("TERMINAL", "MAIN SHELL")
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { index in
                    Text("SHELL \(index)")
                        .font(.custom(state.theme.fonts.main, size: 11))
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(index == 1 ? state.theme.accent : state.theme.panelBackground)
                        .foregroundStyle(index == 1 ? state.theme.panelBackground : state.theme.accent)
                        .augmentedSurface(
                            style: .settingsButton(vh: vh),
                            fill: index == 1 ? state.theme.accent.opacity(0.2) : state.theme.panelBackground.opacity(0.25),
                            stroke: state.theme.accent
                        )
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("$ edex-native --theme \(state.theme.name)")
                Text(state.statusText)
                    .foregroundStyle(state.theme.accent.opacity(0.68))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Text(state.paths?.userData ?? "userdata pending")
                    .foregroundStyle(state.theme.accent.opacity(0.58))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.custom(state.theme.fonts.terminal, size: 13))
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(state.theme.terminalBackground.opacity(0.92))
            .foregroundStyle(state.theme.terminalForeground)
        }
        .padding(8)
        .augmentedSurface(
            style: shellStyle,
            fill: state.theme.panelBackground.opacity(0.74),
            stroke: state.theme.accent
        )
        .positioned(in: frame)
    }

    private func filesystem(_ frame: LayoutRect, vh: Double) -> some View {
        let panelStyle = AugmentedBorderStyle.panel(vh: vh)
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("FILESYSTEM", "TRACKING ACTIVE")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(["..", "src", "crates", "macos", "docs", "themes"], id: \.self) { item in
                    VStack(spacing: 4) {
                        AugmentedBorderShape(style: .settingsButton(vh: vh))
                            .stroke(state.theme.accent.opacity(0.45), lineWidth: 1)
                            .background(
                                AugmentedBorderShape(style: .settingsButton(vh: vh))
                                    .fill(state.theme.accent.opacity(0.04))
                            )
                            .frame(width: 34, height: 28)
                        Text(item)
                            .font(.custom(state.theme.fonts.terminal, size: 10))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
            }
            Spacer(minLength: 0)
            Rectangle()
                .fill(state.theme.accent.opacity(0.45))
                .frame(height: 7)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(state.theme.accent)
                        .frame(width: max(24, CGFloat(frame.width) * 0.32), height: 7)
                }
        }
        .padding(10)
        .augmentedSurface(
            style: panelStyle,
            fill: state.theme.panelBackground.opacity(0.72),
            stroke: state.theme.accent
        )
        .positioned(in: frame)
    }

    private func keyboard(_ metrics: KeyboardLayoutMetrics, vh: Double) -> some View {
        VStack(spacing: CGFloat(metrics.rowGap)) {
            ForEach(0..<5, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<keyboardKeyCount(for: row), id: \.self) { index in
                        keyStub(width: keyboardKeyWidth(row: row, index: index, metrics: metrics), vh: vh)
                    }
                }
                .frame(height: CGFloat(metrics.rowHeight))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .augmentedSurface(
            style: .panel(vh: vh),
            fill: state.theme.panelBackground.opacity(0.42),
            stroke: state.theme.accent
        )
        .opacity(state.modalManager.isKeyboardDetached ? 0.18 : 1.0)
        .positioned(in: metrics.frame)
    }

    private func modalLayer(size: CGSize, vh: Double) -> some View {
        ForEach(state.modalManager.modals, id: \.id) { modal in
            EdexModalChrome(
                state: state,
                modal: modal,
                theme: state.theme,
                vh: vh,
                containerSize: size,
                processRows: state.processRows,
                processSort: state.processSort,
                onFocus: { state.modalManager.focus(modal.id) },
                onMove: { dx, dy in state.modalManager.move(modal.id, dx: dx, dy: dy) },
                onProcessSort: { field in state.processSort = state.processSort.toggled(field) },
                onClose: { state.closeModal(modal.id) }
            )
            .zIndex(Double(modal.zIndex))
        }
    }

    private func sectionTitle(_ left: String, _ right: String) -> some View {
        HStack {
            Text(left)
            Spacer(minLength: 8)
            Text(right)
        }
        .font(.custom(state.theme.fonts.main, size: 11))
        .foregroundStyle(state.theme.accent.opacity(0.76))
        .padding(.horizontal, 5)
        .padding(.bottom, 3)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(state.theme.accent.opacity(0.28))
                .frame(height: 1)
        }
    }

    private func panelStub(_ label: String, vh: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.custom(state.theme.fonts.main, size: 12))
            Text("00:00:00")
                .font(.custom(state.theme.fonts.terminal, size: 11))
                .foregroundStyle(state.theme.terminalForeground)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .augmentedSurface(
            style: .panel(vh: vh),
            fill: state.theme.terminalBackground.opacity(0.72),
            stroke: state.theme.accent
        )
    }

    private func clockPanel(vh: Double) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let clock = EdexClockFormatter(clockHours: state.settingsSummary.clockHours).format(context.date)
            VStack(alignment: .leading, spacing: 6) {
                Text("CLOCK")
                    .font(.custom(state.theme.fonts.main, size: 12))
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    clockTimeText(clock.time)
                    if let meridiem = clock.meridiem {
                        Text(meridiem)
                            .font(.custom(state.theme.fonts.main, size: 12))
                            .foregroundStyle(state.theme.accent.opacity(0.72))
                            .padding(.leading, 3)
                    }
                }
                .font(.custom(state.theme.fonts.terminal, size: 22))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .augmentedSurface(
                style: .panel(vh: vh),
                fill: state.theme.terminalBackground.opacity(0.72),
                stroke: state.theme.accent
            )
        }
    }

    private func clockTimeText(_ time: String) -> Text {
        let components = time.split(separator: ":").map(String.init)
        guard components.count == 3 else {
            return Text(time).foregroundColor(state.theme.terminalForeground)
        }

        return Text(components[0]).foregroundColor(state.theme.terminalForeground)
            + Text(":").foregroundColor(state.theme.accent.opacity(0.58))
            + Text(components[1]).foregroundColor(state.theme.terminalForeground)
            + Text(":").foregroundColor(state.theme.accent.opacity(0.58))
            + Text(components[2]).foregroundColor(state.theme.terminalForeground)
    }

    private func sysinfoPanel(vh: Double) -> some View {
        // 60s nudge catches the date rollover at midnight; uptime/battery come
        // from ShellState, refreshed by the polling task below.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let formatter = EdexSysinfoFormatter()
            let date = formatter.date(context.date)
            let uptime = formatter.uptime(seconds: state.uptimeSeconds)
            let power = formatter.power(state.powerState)

            VStack(alignment: .leading, spacing: 6) {
                Text("SYSINFO")
                    .font(.custom(state.theme.fonts.main, size: 12))
                HStack(alignment: .top, spacing: 8) {
                    sysinfoCell(heading: date.year, value: Text(date.monthDay))
                    sysinfoCell(heading: "UPTIME", value: uptimeText(uptime))
                }
                HStack(alignment: .top, spacing: 8) {
                    sysinfoCell(heading: "TYPE", value: Text(formatter.systemType))
                    sysinfoCell(heading: "POWER", value: Text(power))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .augmentedSurface(
                style: .panel(vh: vh),
                fill: state.theme.terminalBackground.opacity(0.72),
                stroke: state.theme.accent
            )
        }
        .task {
            // Battery cadence in sysinfo.class.js is 3s; uptime barely moves, so
            // refreshing both on the same tick is faithful and cheap.
            while !Task.isCancelled {
                await state.refreshSysinfo()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func sysinfoCell(heading: String, value: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(heading)
                .font(.custom(state.theme.fonts.main, size: 11))
                .foregroundStyle(state.theme.accent.opacity(0.76))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            value
                .font(.custom(state.theme.fonts.terminal, size: 14))
                .foregroundStyle(state.theme.terminalForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func uptimeText(_ value: EdexUptimeValue) -> Text {
        Text("\(value.days)").foregroundColor(state.theme.terminalForeground)
            + Text("d").foregroundColor(state.theme.accent.opacity(0.5))
            + Text(value.hours).foregroundColor(state.theme.terminalForeground)
            + Text(":").foregroundColor(state.theme.accent.opacity(0.5))
            + Text(value.minutes).foregroundColor(state.theme.terminalForeground)
    }

    private func hardwarePanel(vh: Double) -> some View {
        let info = state.hardware.map {
            EdexHardwareFormatter().format(
                manufacturer: $0.manufacturer,
                model: $0.model,
                chassisType: $0.chassisType
            )
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text("HARDWARE")
                .font(.custom(state.theme.fonts.main, size: 12))
            sysinfoCell(heading: "MANUFACTURER", value: Text(info?.manufacturer ?? "NONE"))
            sysinfoCell(heading: "MODEL", value: Text(info?.model ?? "NONE"))
            sysinfoCell(heading: "CHASSIS", value: Text(info?.chassis ?? "NONE"))
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .augmentedSurface(
            style: .panel(vh: vh),
            fill: state.theme.terminalBackground.opacity(0.72),
            stroke: state.theme.accent
        )
        .task {
            // hardwareInspector.class.js re-polls every 20s; the data is static
            // on this target, but match the cadence.
            while !Task.isCancelled {
                await state.refreshHardware()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func cpuPanel(vh: Double) -> some View {
        let snapshot = state.cpu
        let cores = Int(snapshot?.cores ?? 0)
        let divide = cpuFormatter.divide(cores: cores)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("CPU USAGE")
                    .font(.custom(state.theme.fonts.main, size: 12))
                Text(snapshot.map { cpuFormatter.cpuName(manufacturer: $0.manufacturer, brand: $0.brand) } ?? "")
                    .font(.custom(state.theme.fonts.terminal, size: 10))
                    .foregroundStyle(state.theme.accent.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            cpuGraphBlock(chart: 0, rangeStart: 1, rangeEnd: divide, divide: divide, cores: cores, snapshot: snapshot)
            cpuGraphBlock(chart: 1, rangeStart: divide + 1, rangeEnd: cores, divide: divide, cores: cores, snapshot: snapshot)
            HStack(spacing: 0) {
                cpuFooterCell("TEMP", snapshot.map { cpuFormatter.temperatureText($0.temperatureMax) } ?? "--°C")
                cpuFooterCell("SPD", snapshot.map { cpuFormatter.speedText($0.speed) } ?? "--GHz")
                cpuFooterCell("MAX", snapshot.map { cpuFormatter.speedText($0.speedMax) } ?? "--GHz")
                cpuFooterCell("TASKS", snapshot.map { cpuFormatter.tasksText(Int($0.processCount)) } ?? "---")
            }
            .padding(.top, 3)
            .overlay(alignment: .top) {
                Rectangle().fill(state.theme.accent.opacity(0.3)).frame(height: 1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .augmentedSurface(
            style: .panel(vh: vh),
            fill: state.theme.terminalBackground.opacity(0.72),
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

    private func cpuGraphBlock(chart: Int, rangeStart: Int, rangeEnd: Int, divide: Int, cores: Int, snapshot: FfiCpuSnapshot?) -> some View {
        // Average of the loads belonging to this graph half.
        let halfLoads: [Double] = (snapshot?.loads ?? []).enumerated()
            .filter { cpuFormatter.chartIndex(forCore: $0.offset, divide: divide) == chart }
            .map(\.element)
        let avg = snapshot == nil ? nil : cpuFormatter.average(loads: halfLoads)

        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(cores > 0 ? "# \(rangeStart) - \(rangeEnd)" : "# --")
                Spacer(minLength: 4)
                Text(avg.map { "Avg. \($0)%" } ?? "Avg. --%")
            }
            .font(.custom(state.theme.fonts.terminal, size: 10))
            .foregroundStyle(state.theme.accent.opacity(0.72))
            cpuGraph(chart: chart, divide: divide, cores: cores)
        }
    }

    private func cpuGraph(chart: Int, divide: Int, cores: Int) -> some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                guard cores > 0 else { return }
                // millisPerPixel = 50 in the legacy → 20px per 1s sample.
                let dx = 1000.0 / 50.0
                // Fraction (0...1) of the way to the next sample, for smooth scroll.
                let elapsed = min(max(context.date.timeIntervalSince(state.cpuLastSampleDate), 0), 1)
                let series = state.cpuSeries

                for core in 0..<cores where cpuFormatter.chartIndex(forCore: core, divide: divide) == chart {
                    guard core < series.count, series[core].count >= 2 else { continue }
                    let samples = series[core]
                    let n = samples.count
                    var path = Path()
                    for (index, load) in samples.enumerated() {
                        let x = size.width - (Double(n - 1 - index) + elapsed) * dx
                        let y = size.height - (min(max(load, 0), 100) / 100.0) * size.height
                        let point = CGPoint(x: x, y: y)
                        index == 0 ? path.move(to: point) : path.addLine(to: point)
                    }
                    ctx.stroke(path, with: .color(state.theme.accent), lineWidth: 1.7)
                }
            }
        }
        .frame(height: 34)
        .overlay(alignment: .top) { cpuGraphBorder }
        .overlay(alignment: .bottom) { cpuGraphBorder }
    }

    private var cpuGraphBorder: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 1)
            .overlay(
                Rectangle()
                    .strokeBorder(state.theme.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            )
    }

    private func cpuFooterCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.custom(state.theme.fonts.main, size: 9))
                .foregroundStyle(state.theme.accent.opacity(0.7))
            Text(value)
                .font(.custom(state.theme.fonts.terminal, size: 11))
                .foregroundStyle(state.theme.terminalForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private func ramPanel(vh: Double) -> some View {
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
                    .foregroundStyle(state.theme.accent.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            ramGrid(active: active, available: available)
            HStack(spacing: 8) {
                Text("SWAP")
                    .font(.custom(state.theme.fonts.main, size: 10))
                    .foregroundStyle(state.theme.accent.opacity(0.7))
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
            fill: state.theme.terminalBackground.opacity(0.72),
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
            for position in 0..<(cols * rows) {
                let column = position % cols
                let row = position / cols
                let tier = ramFormatter.cellState(rank: ranks[position], activeCount: active, availableCount: available)
                let opacity: Double
                switch tier {
                case .active: opacity = 1.0
                case .available: opacity = 0.45
                case .free: opacity = 0.12
                }
                let rect = CGRect(
                    x: Double(column) * cellW + pad,
                    y: Double(row) * cellH + pad,
                    width: max(0.5, cellW - 2 * pad),
                    height: max(0.5, cellH - 2 * pad)
                )
                ctx.fill(Path(roundedRect: rect, cornerRadius: 0.5), with: .color(state.theme.accent.opacity(opacity)))
            }
        }
        .frame(height: 60)
    }

    private func ramSwapBar(percent: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(state.theme.accent.opacity(0.2))
                Rectangle()
                    .fill(state.theme.accent)
                    .frame(width: geo.size.width * Double(min(max(percent, 0), 100)) / 100.0)
            }
        }
        .frame(height: 4)
    }

    private func toplistPanel(vh: Double) -> some View {
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
                        .foregroundStyle(state.theme.accent.opacity(0.48))
                }
                VStack(spacing: 2) {
                    ForEach(state.topProcesses, id: \.pid) { row in
                        toplistMiniRow(row)
                    }
                    if state.topProcesses.isEmpty {
                        Text("NO PROCESS DATA")
                            .font(.custom(state.theme.fonts.terminal, size: 10))
                            .foregroundStyle(state.theme.terminalForeground.opacity(0.52))
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
            .augmentedSurface(
                style: .panel(vh: vh),
                fill: state.theme.terminalBackground.opacity(0.72),
                stroke: state.theme.accent
            )
        }
        .buttonStyle(.plain)
        .task {
            // toplist.class.js polls the compact top-five table every 2s.
            while !Task.isCancelled {
                await state.refreshToplist()
                try? await Task.sleep(for: .seconds(2))
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
        .foregroundStyle(state.theme.accent.opacity(0.86))
    }

    private func keyStub(width: Double, vh: Double) -> some View {
        AugmentedBorderShape(style: .settingsButton(vh: vh))
            .stroke(state.theme.accent.opacity(0.45), lineWidth: 1)
            .background(
                AugmentedBorderShape(style: .settingsButton(vh: vh))
                    .fill(state.theme.accent.opacity(0.06))
            )
            .frame(width: CGFloat(width), height: 28)
    }

    private func statusRibbon(vh: Double) -> some View {
        return HStack(spacing: 14) {
            Text("⚙ eDEX NATIVE")
                .font(.custom(state.theme.fonts.main, size: 13))
            Text(state.settingsSummary.theme)
                .font(.custom(state.theme.fonts.terminal, size: 11))
                .foregroundStyle(state.theme.accent.opacity(0.68))
            Text(state.keepGeometry ? "16:10" : "FREE")
                .font(.custom(state.theme.fonts.terminal, size: 11))
                .foregroundStyle(state.theme.accent.opacity(0.68))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .augmentedSurface(
            style: .settingsButton(vh: vh),
            fill: state.theme.panelBackground.opacity(0.78),
            stroke: state.theme.accent
        )
        .contentShape(Rectangle())
        .onTapGesture { state.openSettingsModal() }
        .help("Open settings")
        .position(x: 132, y: 23)
    }

    private func keyboardKeyCount(for row: Int) -> Int {
        let counts = [13, 13, 12, 11, 6]
        guard counts.indices.contains(row) else { return 0 }
        return counts[row]
    }

    private func keyboardKeyWidth(row: Int, index: Int, metrics: KeyboardLayoutMetrics) -> Double {
        if row == 4 && index == 2 {
            return metrics.spacebarWidth
        }
        if index == 0 || index == keyboardKeyCount(for: row) - 1 {
            return metrics.keySide * 1.7
        }
        return metrics.keySide
    }
}

private extension EdexLayout {
    var vh: Double {
        viewport.height / 100
    }
}

private struct AugmentedBorderShape: Shape {
    let style: AugmentedBorderStyle

    func path(in rect: CGRect) -> Path {
        let geometry = AugmentedBorderGeometry(
            size: AugmentedBorderSize(width: rect.width.doubleValue, height: rect.height.doubleValue),
            style: style
        )
        var path = Path()
        guard let first = geometry.outlinePoints.first else { return path }

        path.move(to: first.cgPoint(offsetBy: rect.origin))
        for point in geometry.outlinePoints.dropFirst() {
            path.addLine(to: point.cgPoint(offsetBy: rect.origin))
        }
        path.closeSubpath()
        return path
    }
}

private struct AugmentedTickShape: Shape {
    let style: AugmentedBorderStyle

    func path(in rect: CGRect) -> Path {
        let geometry = AugmentedBorderGeometry(
            size: AugmentedBorderSize(width: rect.width.doubleValue, height: rect.height.doubleValue),
            style: style
        )
        var path = Path()
        for segment in geometry.tickSegments {
            path.move(to: segment.start.cgPoint(offsetBy: rect.origin))
            path.addLine(to: segment.end.cgPoint(offsetBy: rect.origin))
        }
        return path
    }
}

private enum ColumnSide {
    case left
    case right

    var placeholders: [String] {
        switch self {
        case .left:
            return ["CLOCK", "SYSINFO", "HARDWARE", "CPU", "RAM", "TOPLIST"]
        case .right:
            return ["NETSTAT", "CONNECTION", "GLOBE", "MEDIA"]
        }
    }
}

private struct EdexGridBackground: View {
    var color: Color
    var step: CGFloat
    var lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            guard step.isFinite, step > 0.5 else { return }
            var path = Path()
            var x = step * 0.9
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }

            var y = step * 0.9
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }

            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
    }
}

private struct EdexModalChrome: View {
    @Bindable var state: ShellState
    let modal: EdexModalRecord
    let theme: NativeTheme
    let vh: Double
    let containerSize: CGSize
    let processRows: [FfiProcessRow]
    let processSort: EdexProcessSort
    let onFocus: () -> Void
    let onMove: (_ dx: Double, _ dy: Double) -> Void
    let onProcessSort: (EdexProcessSortField) -> Void
    let onClose: () -> Void

    @State private var lastDrag = CGSize.zero

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            bodyContent
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                ForEach(buttonLabels, id: \.self) { label in
                    Button(label) {
                        onClose()
                    }
                    .buttonStyle(EdexModalButtonStyle(theme: theme, vh: vh))
                }
            }
        }
        .padding(16)
        .frame(width: modalWidth, alignment: .topLeading)
        .frame(minHeight: modalHeight, alignment: .topLeading)
        .augmentedSurface(
            style: .modal(vh: vh),
            fill: modalFill,
            stroke: theme.accent
        )
        .position(
            x: safeContainerWidth / 2 + CGFloat(modal.offsetX),
            y: safeContainerHeight / 2 + CGFloat(modal.offsetY)
        )
        .shadow(color: theme.accent.opacity(0.24), radius: 16)
        .simultaneousGesture(TapGesture().onEnded {
            onFocus()
        })
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(modal.title.uppercased())
                .font(.custom(theme.fonts.main, size: 16))
                .foregroundStyle(theme.accent)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(kindLabel)
                .font(.custom(theme.fonts.main, size: 10))
                .foregroundStyle(theme.accent.opacity(0.62))
        }
        .padding(.bottom, 7)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.accent.opacity(0.32))
                .frame(height: 1)
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    onFocus()
                    let dx = value.translation.width - lastDrag.width
                    let dy = value.translation.height - lastDrag.height
                    lastDrag = value.translation
                    onMove(Double(dx), Double(dy))
                }
                .onEnded { _ in
                    lastDrag = .zero
                }
        )
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch modal.content {
        case .message:
            Text(modal.message)
                .font(.custom(theme.fonts.terminal, size: 13))
                .foregroundStyle(theme.terminalForeground)
                .lineLimit(12)
                .textSelection(.enabled)
        case .processList:
            EdexProcessListTable(
                rows: processRows,
                sort: processSort,
                theme: theme,
                onSort: onProcessSort
            )
        case .settingsEditor:
            EdexSettingsForm(state: state, theme: theme)
        case .shortcuts:
            EdexShortcutsView(state: state, theme: theme)
        case .textEditor:
            customStatus("TEXT EDITOR", detail: "Ready for Phase 7.3 file editing")
        case .mediaViewer:
            customStatus("MEDIA VIEWER", detail: "Ready for Phase 10.1 media content")
        case .customPlaceholder:
            customStatus("CUSTOM MODAL", detail: modal.message)
        }
    }

    private func customStatus(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom(theme.fonts.main, size: 13))
                .foregroundStyle(theme.accent.opacity(0.78))
            Text(detail)
                .font(.custom(theme.fonts.terminal, size: 12))
                .foregroundStyle(theme.terminalForeground.opacity(0.84))
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .augmentedSurface(
            style: .panel(vh: vh),
            fill: theme.terminalBackground.opacity(0.72),
            stroke: theme.accent
        )
    }

    private var buttonLabels: [String] {
        switch modal.kind {
        case .error:
            ["PANIC", "RELOAD"]
        case .warning, .info:
            ["OK"]
        case .custom:
            ["Close"]
        }
    }

    private var kindLabel: String {
        switch modal.kind {
        case .error:
            "ERROR"
        case .warning:
            "WARNING"
        case .info:
            "INFO"
        case .custom:
            "CUSTOM"
        }
    }

    private var modalFill: Color {
        switch modal.kind {
        case .error:
            theme.panelBackground.opacity(0.94)
        case .warning:
            theme.panelBackground.opacity(0.9)
        case .info, .custom:
            theme.panelBackground.opacity(0.86)
        }
    }

    private var modalWidth: CGFloat {
        if modal.content == .processList {
            return min(max(safeContainerWidth * 0.72, 680), 980)
        }
        if modal.content == .settingsEditor {
            return min(max(safeContainerWidth * 0.5, 520), 760)
        }
        if modal.content == .shortcuts {
            return min(max(safeContainerWidth * 0.5, 520), 780)
        }
        return min(max(safeContainerWidth * 0.42, 380), 740)
    }

    private var modalHeight: CGFloat {
        if modal.content == .processList {
            return min(max(safeContainerHeight * 0.55, 360), 620)
        }
        if modal.content == .settingsEditor {
            return min(max(safeContainerHeight * 0.6, 420), 640)
        }
        if modal.content == .shortcuts {
            return min(max(safeContainerHeight * 0.55, 380), 600)
        }
        return modal.kind == .custom ? 260 : 150
    }

    private var safeContainerWidth: CGFloat {
        containerSize.width.isFinite && containerSize.width > 0 ? containerSize.width : 960
    }

    private var safeContainerHeight: CGFloat {
        containerSize.height.isFinite && containerSize.height > 0 ? containerSize.height : 600
    }
}

private struct EdexSettingsForm: View {
    @Bindable var state: ShellState
    let theme: NativeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(EdexSettingsField.all) { field in
                        row(field)
                    }
                }
                .padding(.trailing, 6)
            }
            .frame(maxHeight: 360)

            Text(state.settingsStatus)
                .font(.custom(theme.fonts.terminal, size: 11))
                .foregroundStyle(theme.accent.opacity(0.82))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                actionButton("Open in External Editor") { state.openSettingsFileExternally() }
                actionButton("Save to Disk") { state.saveSettings() }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .augmentedSurface(
            style: .panel(vh: 8),
            fill: theme.terminalBackground.opacity(0.7),
            stroke: theme.accent
        )
    }

    private func row(_ field: EdexSettingsField) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(field.label)
                    .font(.custom(theme.fonts.main, size: 11))
                    .foregroundStyle(theme.accent)
                Text(field.help)
                    .font(.custom(theme.fonts.terminal, size: 9))
                    .foregroundStyle(theme.terminalForeground.opacity(0.6))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control(field)
                .frame(width: 200, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func control(_ field: EdexSettingsField) -> some View {
        switch field.control {
        case .text:
            TextField("", text: stringBinding(field.key))
                .textFieldStyle(.roundedBorder)
                .font(.custom(theme.fonts.terminal, size: 11))
        case .integer:
            TextField("", value: intBinding(field.key), format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.custom(theme.fonts.terminal, size: 11))
        case .decimal:
            TextField("", value: doubleBinding(field.key), format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.custom(theme.fonts.terminal, size: 11))
        case .toggle:
            Toggle("", isOn: boolBinding(field.key))
                .labelsHidden()
        case let .choice(fixed):
            Picker("", selection: choiceBinding(field.key)) {
                ForEach(options(for: field.key, fixed: fixed), id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .font(.custom(theme.fonts.terminal, size: 11))
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.custom(theme.fonts.main, size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(theme.accent)
                .background(theme.accent.opacity(0.18))
        }
        .buttonStyle(.plain)
    }

    // MARK: Bindings

    private func stringBinding(_ key: EdexSettingsKey) -> Binding<String> {
        Binding(get: { state.settingsString(key) }, set: { state.setSettingsString($0, for: key) })
    }

    private func intBinding(_ key: EdexSettingsKey) -> Binding<Int> {
        Binding(get: { state.settingsInt(key) }, set: { state.setSettingsInt($0, for: key) })
    }

    private func doubleBinding(_ key: EdexSettingsKey) -> Binding<Double> {
        Binding(get: { state.settingsDouble(key) }, set: { state.setSettingsDouble($0, for: key) })
    }

    private func boolBinding(_ key: EdexSettingsKey) -> Binding<Bool> {
        Binding(get: { state.settingsBool(key) }, set: { state.setSettingsBool($0, for: key) })
    }

    /// Choice pickers are string-tagged. `clockHours` is int-backed, so it is
    /// bridged through its string representation.
    private func choiceBinding(_ key: EdexSettingsKey) -> Binding<String> {
        Binding(
            get: {
                key == .clockHours ? String(state.settingsInt(key)) : state.settingsString(key)
            },
            set: { newValue in
                if key == .clockHours {
                    state.setSettingsInt(Int(newValue) ?? 24, for: key)
                } else {
                    state.setSettingsString(newValue, for: key)
                }
            }
        )
    }

    /// Ensures the current value is always a selectable option so the Picker has
    /// a valid tag even before the FFI listings load (or for custom themes).
    private func options(for key: EdexSettingsKey, fixed: [String]) -> [String] {
        let dynamic: [String]
        switch key {
        case .theme: dynamic = state.settingsThemeOptions
        case .keyboard: dynamic = state.settingsKeyboardOptions
        default: return fixed
        }
        let current = state.settingsString(key)
        var options = dynamic
        if !current.isEmpty, !options.contains(current) {
            options.insert(current, at: 0)
        }
        return options.isEmpty ? [current] : options
    }
}

// MARK: - Shortcuts modal (Phase 6.4)

private struct EdexShortcutsView: View {
    @Bindable var state: ShellState
    let theme: NativeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    shortcutsSection(
                        title: "APP SHORTCUTS",
                        entries: state.shortcuts?.appEntries() ?? []
                    ) { entry in
                        appActionLabel(entry.action)
                    }

                    shortcutsSection(
                        title: "SHELL SHORTCUTS",
                        entries: state.shortcuts?.shellEntries() ?? []
                    ) { entry in
                        HStack(spacing: 8) {
                            Text(entry.action)
                                .font(.custom(theme.fonts.terminal, size: 12))
                                .foregroundStyle(theme.terminalForeground)
                            if entry.linebreak {
                                Text("+ Enter")
                                    .font(.custom(theme.fonts.terminal, size: 10))
                                    .foregroundStyle(theme.accent.opacity(0.6))
                            }
                        }
                    }
                }
                .padding(16)
            }

            Divider()
                .background(theme.accent.opacity(0.35))

            HStack(spacing: 12) {
                if !state.shortcutsStatus.isEmpty {
                    Text(state.shortcutsStatus)
                        .font(.custom(theme.fonts.terminal, size: 11))
                        .foregroundStyle(theme.accent.opacity(0.65))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
                Button("Open Shortcuts File") {
                    state.openShortcutsFileExternally()
                }
                .font(.custom(theme.fonts.main, size: 12))
                .foregroundStyle(theme.accent)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func shortcutsSection<Label: View>(
        title: String,
        entries: [EdexShortcutEntry],
        @ViewBuilder label: @escaping (EdexShortcutEntry) -> Label
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.custom(theme.fonts.main, size: 11))
                .foregroundStyle(theme.accent.opacity(0.78))
                .padding(.bottom, 2)

            if entries.isEmpty {
                Text("None")
                    .font(.custom(theme.fonts.terminal, size: 12))
                    .foregroundStyle(theme.terminalForeground.opacity(0.5))
            } else {
                VStack(spacing: 2) {
                    ForEach(entries) { entry in
                        HStack(alignment: .center, spacing: 0) {
                            Text(entry.enabled ? "ON " : "OFF")
                                .font(.custom(theme.fonts.terminal, size: 11))
                                .foregroundStyle(
                                    entry.enabled
                                        ? theme.accent.opacity(0.9)
                                        : theme.terminalForeground.opacity(0.35)
                                )
                                .frame(width: 36, alignment: .leading)

                            Text(entry.trigger)
                                .font(.custom(theme.fonts.terminal, size: 12))
                                .foregroundStyle(theme.terminalForeground.opacity(0.9))
                                .frame(width: 200, alignment: .leading)

                            label(entry)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(
                            entry.enabled
                                ? theme.terminalBackground.opacity(0.18)
                                : Color.clear
                        )
                    }
                }
                .padding(4)
                .augmentedSurface(
                    style: .panel(vh: 0.5),
                    fill: theme.terminalBackground.opacity(0.28),
                    stroke: theme.accent.opacity(0.4)
                )
            }
        }
    }

    private func appActionLabel(_ rawAction: String) -> some View {
        let label: String
        switch rawAction {
        case "COPY":          label = "Copy selected terminal buffer"
        case "PASTE":         label = "Paste clipboard to terminal"
        case "NEXT_TAB":      label = "Next terminal tab →"
        case "PREVIOUS_TAB":  label = "Previous terminal tab ←"
        case "TAB_X":         label = "Switch to tab N (1–5)"
        case "SETTINGS":      label = "Open settings editor"
        case "SHORTCUTS":     label = "Show this shortcuts list"
        case "FUZZY_SEARCH":  label = "Fuzzy-search current directory"
        case "FS_LIST_VIEW":  label = "Toggle list / grid view"
        case "FS_DOTFILES":   label = "Toggle hidden files"
        case "KB_PASSMODE":   label = "Keyboard password mode"
        case "DEV_DEBUG":     label = "Open developer tools"
        case "DEV_RELOAD":    label = "Reload UI"
        default:              label = rawAction
        }
        return Text(label)
            .font(.custom(theme.fonts.terminal, size: 12))
            .foregroundStyle(theme.terminalForeground)
    }
}

private struct EdexProcessListTable: View {
    let rows: [FfiProcessRow]
    let sort: EdexProcessSort
    let theme: NativeTheme
    let onSort: (EdexProcessSortField) -> Void

    private let formatter = EdexToplistFormatter()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(sortedRows(now: context.date), id: \.pid) { row in
                                processRow(row, now: context.date)
                            }
                        }
                    }
                    .frame(minHeight: 220, maxHeight: 430)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .overlay {
                if rows.isEmpty {
                    Text("NO PROCESS DATA")
                        .font(.custom(theme.fonts.terminal, size: 12))
                        .foregroundStyle(theme.terminalForeground.opacity(0.58))
                }
            }
            .augmentedSurface(
                style: .panel(vh: 8),
                fill: theme.terminalBackground.opacity(0.7),
                stroke: theme.accent
            )
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            headerCell(.pid, width: 58)
            headerCell(.name, width: 160)
            headerCell(.user, width: 90)
            headerCell(.cpu, width: 58)
            headerCell(.memory, width: 72)
            headerCell(.state, width: 82)
            headerCell(.started, width: 154)
            headerCell(.runtime, width: 88)
        }
        .padding(.trailing, 10)
    }

    private func headerCell(_ field: EdexProcessSortField, width: CGFloat) -> some View {
        Button {
            onSort(field)
        } label: {
            Text(headerTitle(field))
                .font(.custom(theme.fonts.main, size: 10))
                .foregroundStyle(theme.panelBackground)
                .lineLimit(1)
                .frame(width: width, height: 24)
                .background(theme.accent.opacity(0.72))
        }
        .buttonStyle(.plain)
    }

    private func processRow(_ row: EdexProcessRow, now: Date) -> some View {
        HStack(spacing: 0) {
            cell("\(row.pid)", width: 58, alignment: .leading)
            cell(row.name, width: 160, alignment: .leading)
            cell(row.user, width: 90, alignment: .leading)
            cell(formatter.percentText(row.cpu), width: 58, alignment: .trailing)
            cell(formatter.percentText(row.mem), width: 72, alignment: .trailing)
            cell(row.state, width: 82, alignment: .center)
            cell(row.started, width: 154, alignment: .leading)
            cell(formatter.runtimeText(started: row.started, now: now), width: 88, alignment: .leading)
        }
        .padding(.vertical, 2)
        .background(theme.accent.opacity(0.035))
    }

    private func cell(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text.isEmpty ? "-" : text)
            .font(.custom(theme.fonts.terminal, size: 10))
            .foregroundStyle(theme.terminalForeground)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, 3)
    }

    private func sortedRows(now: Date) -> [EdexProcessRow] {
        formatter.sorted(
            rows.map {
                EdexProcessRow(
                    pid: $0.pid,
                    name: $0.name,
                    user: $0.user,
                    cpu: $0.cpu,
                    mem: $0.mem,
                    state: $0.state,
                    started: $0.started
                )
            },
            sort: sort,
            now: now
        )
    }

    private func headerTitle(_ field: EdexProcessSortField) -> String {
        guard case let .field(current, ascending) = sort, current == field else {
            return field.rawValue
        }
        return "\(field.rawValue)\(ascending ? "▲" : "▼")"
    }
}

private struct EdexModalButtonStyle: ButtonStyle {
    let theme: NativeTheme
    let vh: Double

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom(theme.fonts.main, size: 11))
            .foregroundStyle(configuration.isPressed ? theme.panelBackground : theme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                AugmentedBorderShape(style: .settingsButton(vh: vh))
                    .fill(configuration.isPressed ? theme.accent.opacity(0.92) : theme.accent.opacity(0.08))
            )
            .overlay(
                AugmentedBorderShape(style: .settingsButton(vh: vh))
                    .stroke(theme.accent.opacity(0.74), lineWidth: max(1, CGFloat(0.092 * vh)))
            )
    }
}

private extension View {
    func positioned(in rect: LayoutRect) -> some View {
        frame(width: CGFloat(rect.width), height: CGFloat(rect.height))
            .position(
                x: CGFloat(rect.x + (rect.width / 2)),
                y: CGFloat(rect.y + (rect.height / 2))
            )
    }

    func augmentedSurface(style: AugmentedBorderStyle, fill: Color, stroke: Color) -> some View {
        background(AugmentedBorderShape(style: style).fill(fill))
            .clipShape(AugmentedBorderShape(style: style))
            .overlay(
                AugmentedBorderShape(style: style)
                    .stroke(stroke.opacity(style.borderOpacity), lineWidth: CGFloat(style.borderWidth))
            )
            .overlay(
                AugmentedTickShape(style: style)
                    .stroke(stroke.opacity(style.tickOpacity), lineWidth: max(1, CGFloat(style.borderWidth)))
            )
    }
}

private extension AugmentedPoint {
    func cgPoint(offsetBy origin: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(x), y: origin.y + CGFloat(y))
    }
}

private extension CGFloat {
    var doubleValue: Double {
        Double(self)
    }
}

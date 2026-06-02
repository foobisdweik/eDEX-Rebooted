import BorderSupport
import ClockSupport
import CpuinfoSupport
import HardwareSupport
import LayoutSupport
import SwiftUI
import SysinfoSupport
import ThemeSupport

struct ContentView: View {
    @Bindable var state: ShellState
    private let layoutEngine = EdexLayoutEngine()
    private let cpuFormatter = EdexCpuinfoFormatter()

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
        .positioned(in: metrics.frame)
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
            Text("eDEX NATIVE")
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

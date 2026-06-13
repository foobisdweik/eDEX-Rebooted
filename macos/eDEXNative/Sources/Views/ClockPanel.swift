import EdexDomainSupport
import EdexRenderingSupport
import SwiftUI

// Finding #1 (List 3): the clock/sysinfo/hardware panels were `private func`s on
// ContentView, so their per-tick reads (clock 1 Hz, sysinfo uptime/power 3 s,
// hardware 20 s) were attributed to `ContentView.body` — every shell
// invalidation re-ran them, and `hardwarePanel` even re-ran the formatter on
// each pass. Extracting them into dedicated `View` structs (same pattern as
// `CpuPanel`/`RamPanel`/`ToplistPanel`) gives each its own observation
// boundary; the render bodies are unchanged, so output is identical.
struct ClockPanel: View {
    let state: ShellState
    let vh: Double

    var body: some View {
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
}

import EdexDomainSupport
import EdexRenderingSupport
import SwiftUI

// Finding #1 (List 3): extracted from ContentView so the 3 s uptime/battery
// poll invalidates only this panel. See `ClockPanel` for the rationale.
struct SysinfoPanel: View {
    let state: ShellState
    let vh: Double
    private let formatter = EdexSysinfoFormatter()

    var body: some View {
        // 60s nudge catches the date rollover at midnight; uptime/battery come
        // from ShellState, refreshed by the polling task below.
        TimelineView(.periodic(from: .now, by: 60)) { context in
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
}

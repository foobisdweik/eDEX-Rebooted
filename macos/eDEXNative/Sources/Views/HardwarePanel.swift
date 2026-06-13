import EdexCoreBridge
import EdexDomainSupport
import EdexRenderingSupport
import SwiftUI

// Finding #1 (List 3): extracted from ContentView. The previous `private func`
// re-ran `EdexHardwareFormatter().format(...)` on every `ContentView.body`
// pass even though the hardware data only changes every 20 s; as its own View
// the format runs only when `state.hardware` changes. See `ClockPanel`.
struct HardwarePanel: View {
    let state: ShellState
    let vh: Double

    var body: some View {
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
}

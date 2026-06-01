import SwiftUI

struct ContentView: View {
    @Bindable var state: ShellState

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [state.theme.background, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                header
                Divider().overlay(state.theme.accent.opacity(0.7))
                ffiProof
                Spacer(minLength: 12)
                viabilityHint
            }
            .padding(32)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("eDEX Native")
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .tracking(3)
            Text("Phase 3.1/3.2 SwiftUI + AppKit shell")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(state.theme.accent.opacity(0.78))
        }
    }

    private var ffiProof: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            statusRow("FFI status", state.statusText)
            statusRow("settings theme", state.settingsSummary.theme)
            statusRow("keepGeometry", state.keepGeometry ? "true — 16:10 content aspect lock applied" : "false — freeform resizing")
            statusRow("userData", state.paths?.userData ?? "pending")
            statusRow("settings.json", state.paths?.settingsFile ?? "pending")
            statusRow("settings bytes", state.settingsSummary.byteCount.map(String.init) ?? "pending")
            statusRow("theme source", state.theme.source)
        }
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label.uppercased())
                .foregroundStyle(state.theme.accent.opacity(0.62))
            Text(value)
                .foregroundStyle(state.theme.accent)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private var viabilityHint: some View {
        Text("F11 toggles fullscreen. Windowed mode keeps standard traffic lights and a transparent titlebar. This surface is intentionally only a shell; panels come later if this spike remains viable.")
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(state.theme.accent.opacity(0.72))
            .fixedSize(horizontal: false, vertical: true)
    }
}

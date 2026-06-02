import SwiftUI
import ThemeSupport

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
                themePreview
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
                .font(.custom(state.theme.fonts.main, size: 34))
                .tracking(3)
            Text("Phase 4.1 native theme loader")
                .font(.custom(state.theme.fonts.mainLight, size: 16))
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
        .font(.custom(state.theme.fonts.terminal, size: 13))
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

    private var themePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                swatch("ACCENT", state.theme.palette.accent)
                swatch("PANEL", state.theme.palette.panelBackground)
                swatch("TERM", state.theme.palette.terminalBackground)
                swatch("SELECT", state.theme.palette.terminalSelection)
            }
            HStack(alignment: .top, spacing: 14) {
                placeholderPanel("SYS", "UPTIME 00:00:00")
                placeholderPanel("CPU", "AVG 0.00%")
                terminalSample
            }
        }
    }

    private func swatch(_ label: String, _ color: NativeColor) -> some View {
        HStack(spacing: 7) {
            Rectangle()
                .fill(color.color)
                .frame(width: 20, height: 20)
                .overlay(Rectangle().stroke(state.theme.accent.opacity(0.45), lineWidth: 1))
            Text(label)
                .font(.custom(state.theme.fonts.terminal, size: 11))
                .foregroundStyle(state.theme.accent.opacity(0.68))
        }
    }

    private func placeholderPanel(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.custom(state.theme.fonts.main, size: 13))
            Text(value)
                .font(.custom(state.theme.fonts.terminal, size: 12))
                .foregroundStyle(state.theme.accent.opacity(0.74))
        }
        .padding(12)
        .frame(width: 145, height: 72, alignment: .leading)
        .background(state.theme.panelBackground.opacity(0.82))
        .overlay(Rectangle().stroke(state.theme.accent.opacity(0.38), lineWidth: 1))
    }

    private var terminalSample: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("TERMINAL")
                .font(.custom(state.theme.fonts.main, size: 13))
            Text("$ theme --native \(state.theme.name)")
                .font(.custom(state.theme.fonts.terminal, size: 12))
                .foregroundStyle(state.theme.terminalForeground)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: 330, minHeight: 72, alignment: .leading)
        .background(state.theme.terminalBackground.opacity(0.9))
        .overlay(Rectangle().stroke(state.theme.accent.opacity(0.45), lineWidth: 1))
    }

    private var viabilityHint: some View {
        Text("F11 toggles fullscreen. Windowed mode keeps standard traffic lights and a transparent titlebar. This surface is intentionally only a shell; panels come later if this spike remains viable.")
            .font(.custom(state.theme.fonts.terminal, size: 11))
            .foregroundStyle(state.theme.accent.opacity(0.72))
            .fixedSize(horizontal: false, vertical: true)
    }
}

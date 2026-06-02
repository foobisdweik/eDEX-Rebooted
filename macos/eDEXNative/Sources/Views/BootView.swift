import BootSupport
import SwiftUI
import ThemeSupport

// MARK: - BootView

/// Full-screen boot sequence overlay. Displayed over the shell until the
/// sequence completes, then removed. Two stages mirror the legacy JS flow:
///
///   1. Log scroll — 85 fake kernel lines (+ synthetic kernel-version line)
///      displayed one at a time with the legacy JS timing schedule.
///   2. Title flash — "eDEX-UI" h1 with a theme-colored border animation
///      matching the displayTitleScreen() sequence.
struct BootView: View {
    @Bindable var state: ShellState

    var body: some View {
        ZStack {
            // Always-opaque dark background — stays through both stages.
            Color.black.ignoresSafeArea()

            switch state.bootStage {
            case .logScroll:
                logScrollStage
            case .titleFlash:
                TitleFlashView(state: state)
            case .complete:
                EmptyView()
            }
        }
        .task {
            await state.runBootSequence()
        }
    }

    // MARK: Log scroll stage

    private var logScrollStage: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(state.bootDisplayLines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.custom("SF Mono", size: 11).monospaced())
                            .foregroundStyle(.white.opacity(0.82))
                            .textSelection(.disabled)
                    }
                    // Anchor scroll target at the bottom.
                    Color.clear.frame(height: 1).id("boot_bottom")
                }
                .padding(14)
            }
            .onChange(of: state.bootDisplayLines.count) { _, _ in
                withAnimation(.linear(duration: 0.05)) {
                    proxy.scrollTo("boot_bottom", anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Title flash view

private struct TitleFlashView: View {
    @Bindable var state: ShellState
    @State private var stage: TitleFlashStage = .blank

    var body: some View {
        ZStack {
            // Solid fill behind title during the filled-block stage.
            if stage == .solidFill {
                Color.black.ignoresSafeArea()
            }
            if stage != .blank {
                titleView
            }
        }
        .task { await runSequence() }
    }

    private var themeColor: Color { state.theme.accent }

    @ViewBuilder
    private var titleView: some View {
        let text = Text("eDEX-UI")
            .font(.system(size: 48, weight: .thin, design: .monospaced))
            .tracking(8)

        switch stage {
        case .blank:
            EmptyView()
        case .centeredTitle:
            text.foregroundStyle(.white)
        case .solidFill:
            text
                .foregroundStyle(themeColor)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(themeColor)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(themeColor)
                        .frame(height: 5)
                }
        case .outline:
            text
                .foregroundStyle(themeColor)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .overlay(
                    Rectangle()
                        .strokeBorder(themeColor, lineWidth: 5)
                )
        case .glitch:
            text
                .foregroundStyle(.white)
                .phaseAnimator([false, true, false]) { content, glitching in
                    content
                        .offset(x: glitching ? 5 : -5)
                        .opacity(glitching ? 0.4 : 1.0)
                } animation: { _ in .easeInOut(duration: 0.04) }
        case .finalOutline:
            text
                .foregroundStyle(themeColor)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .overlay(
                    Rectangle()
                        .strokeBorder(themeColor, lineWidth: 5)
                )
        }
    }

    // Timeline mirroring displayTitleScreen()'s await chain.
    private func runSequence() async {
        do {
            stage = .blank

            try await Task.sleep(for: .milliseconds(400))
            stage = .centeredTitle
            try await Task.sleep(for: .milliseconds(200))
            stage = .solidFill
            try await Task.sleep(for: .milliseconds(100))
            // solidFill stage (theme-color background + bottom border)
            try await Task.sleep(for: .milliseconds(300))
            stage = .outline
            try await Task.sleep(for: .milliseconds(100))
            stage = .glitch
            try await Task.sleep(for: .milliseconds(500))
            stage = .finalOutline
            try await Task.sleep(for: .milliseconds(1000))
            // Signal ShellState that the boot sequence is fully done.
            state.bootStage = .complete
        } catch {
            // Task was cancelled — exit without completing the sequence.
        }
    }
}

// MARK: - Stage enum

enum TitleFlashStage: Equatable {
    case blank, centeredTitle, solidFill, outline, glitch, finalOutline
}

import EdexDomainSupport
import EdexRenderingSupport
import SwiftUI

struct EdexKeyboardPanel: View {
    let layout: NativeKeyboardLayout?
    let modifiers: KeyboardModifierState
    let pressedKeyIDs: Set<String>
    let isDetached: Bool
    let theme: NativeTheme
    let metrics: KeyboardLayoutMetrics
    let vh: Double
    let onToggleModifier: @MainActor (KeyboardModifier) -> Void
    let onPressKey: @MainActor (KeyboardKeyDescriptor) -> Void

    var body: some View {
        Group {
            if let layout {
                keyboardBand(layout: layout)
            } else {
                keyboardStubBand
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .augmentedSurface(
            style: .panel(vh: vh),
            fill: theme.panelBackground.opacity(0.42),
            stroke: theme.accent
        )
        .opacity(KeyboardViewModel.bandOpacity(modifiers: modifiers, isDetached: isDetached))
    }

    private func keyboardBand(layout: NativeKeyboardLayout) -> some View {
        let rows = KeyboardViewModel.descriptors(for: layout)
        return GeometryReader { proxy in
            let fitted = KeyboardRowLayoutMetrics.fit(
                rows: rows,
                availableWidth: Double(proxy.size.width),
                availableHeight: Double(proxy.size.height),
                preferredKeySide: metrics.keySide,
                preferredSpacebarWidth: metrics.spacebarWidth,
                preferredRowHeight: metrics.rowHeight,
                preferredRowGap: metrics.rowGap,
                preferredKeyGap: 6
            )
            VStack(spacing: CGFloat(fitted.rowGap)) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: CGFloat(fitted.keyGap)) {
                        ForEach(row) { descriptor in
                            keyView(descriptor, metrics: fitted)
                        }
                    }
                    .frame(height: CGFloat(fitted.rowHeight))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .clipped()
        }
    }

    private func keyView(_ descriptor: KeyboardKeyDescriptor, metrics: KeyboardRowLayoutMetrics) -> some View {
        let isPressed = pressedKeyIDs.contains(descriptor.id)
        let isHighlighted = descriptor.isHighlighted(modifiers: modifiers)
        let isFilled = isPressed || isHighlighted
        let accent = theme.accent
        let isEmphasizedEdge: Bool
        switch descriptor.role {
        case .spacebar, .enter, .enterContinuation:
            isEmphasizedEdge = true
        default:
            isEmphasizedEdge = false
        }

        let repeatEnabled = descriptor.modifier == nil
            && descriptor.role != .enter
            && descriptor.role != .enterContinuation
        return EdexKeyboardKeyButton(repeatEnabled: repeatEnabled) {
            if let modifier = descriptor.modifier {
                onToggleModifier(modifier)
            } else {
                onPressKey(descriptor)
            }
        } label: {
            ZStack {
                AugmentedBorderShape(style: .settingsButton(vh: vh))
                    .fill(isFilled ? accent : accent.opacity(0.06))
                AugmentedBorderShape(style: .settingsButton(vh: vh))
                    .stroke(accent.opacity(isEmphasizedEdge ? 0.6 : 0.45), lineWidth: 1)
                keyContent(descriptor, filled: isFilled)
            }
        }
        .frame(width: CGFloat(metrics.keyWidth(for: descriptor)))
        .frame(maxHeight: .infinity)
        .animation(.easeOut(duration: 0.12), value: isFilled)
    }

    @ViewBuilder
    private func keyContent(_ descriptor: KeyboardKeyDescriptor, filled: Bool) -> some View {
        let textColor = filled ? theme.panelBackground : theme.accent
        if let icon = descriptor.iconName {
            Image(systemName: keyboardIconSymbol(icon))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(textColor)
        } else {
            let primary = descriptor.prominentLabel(modifiers: modifiers)
            ZStack {
                Text(primary)
                    .font(.custom(theme.fonts.main, size: 13))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                keyCornerLabel(descriptor.shiftLabel, primary: primary, color: textColor, alignment: .topLeading)
                keyCornerLabel(descriptor.altShiftLabel, primary: primary, color: textColor, alignment: .topTrailing)
                keyCornerLabel(descriptor.altLabel, primary: primary, color: textColor, alignment: .bottomTrailing)
            }
            .padding(2)
        }
    }

    @ViewBuilder
    private func keyCornerLabel(_ label: String?, primary: String, color: Color, alignment: Alignment) -> some View {
        if let label, !label.isEmpty, label != primary {
            Text(label)
                .font(.custom(theme.fonts.terminal, size: 8))
                .foregroundStyle(color.opacity(0.55))
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        }
    }

    private func keyboardIconSymbol(_ name: String) -> String {
        switch name {
        case "ARROW_UP": return "arrow.up"
        case "ARROW_DOWN": return "arrow.down"
        case "ARROW_LEFT": return "arrow.left"
        case "ARROW_RIGHT": return "arrow.right"
        default: return "questionmark.square.dashed"
        }
    }

    private var keyboardStubBand: some View {
        GeometryReader { proxy in
            let scale = keyboardStubScale(size: proxy.size)
            let rowGap = metrics.rowGap * scale
            let rowHeight = metrics.rowHeight * scale
            let keyGap = 6 * scale
            VStack(spacing: CGFloat(rowGap)) {
                ForEach(0..<5, id: \.self) { row in
                    HStack(spacing: CGFloat(keyGap)) {
                        ForEach(0..<keyboardKeyCount(for: row), id: \.self) { index in
                            keyStub(width: keyboardKeyWidth(row: row, index: index, scale: scale), height: rowHeight)
                        }
                    }
                    .frame(height: CGFloat(rowHeight))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .clipped()
        }
    }

    private func keyStub(width: Double, height: Double) -> some View {
        AugmentedBorderShape(style: .settingsButton(vh: vh))
            .stroke(theme.accent.opacity(0.45), lineWidth: 1)
            .background(
                AugmentedBorderShape(style: .settingsButton(vh: vh))
                    .fill(theme.accent.opacity(0.06))
            )
            .frame(width: CGFloat(width), height: CGFloat(height))
    }

    private func keyboardKeyCount(for row: Int) -> Int {
        let counts = [13, 13, 12, 11, 6]
        guard counts.indices.contains(row) else { return 0 }
        return counts[row]
    }

    private func keyboardKeyWidth(row: Int, index: Int, scale: Double) -> Double {
        if row == 4 && index == 2 {
            return metrics.spacebarWidth * scale
        }
        if index == 0 || index == keyboardKeyCount(for: row) - 1 {
            return metrics.keySide * 1.7 * scale
        }
        return metrics.keySide * scale
    }

    private func keyboardStubScale(size: CGSize) -> Double {
        let rowWidths = (0..<5).map { row in
            let keyCount = keyboardKeyCount(for: row)
            let width = (0..<keyCount).reduce(0) { $0 + keyboardKeyWidth(row: row, index: $1, scale: 1) }
            return width + (Double(max(0, keyCount - 1)) * 6)
        }
        let maxWidth = rowWidths.max() ?? 0
        let totalHeight = (5 * metrics.rowHeight) + (4 * metrics.rowGap)
        let widthScale = maxWidth > 0 ? Double(size.width) / maxWidth : 1
        let heightScale = totalHeight > 0 ? Double(size.height) / totalHeight : 1
        return min(1, max(0, widthScale), max(0, heightScale))
    }
}

private struct EdexKeyboardKeyButton<Label: View>: View {
    let repeatEnabled: Bool
    let action: @MainActor () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isPressing = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        label()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in beginPress() }
                    .onEnded { _ in endPress() }
            )
            .onDisappear { endPress() }
    }

    private func beginPress() {
        guard !isPressing else { return }
        isPressing = true
        action()
        guard repeatEnabled else { return }
        repeatTask = Task {
            try? await Task.sleep(nanoseconds: 420_000_000)
            while !Task.isCancelled {
                await MainActor.run { action() }
                try? await Task.sleep(nanoseconds: 70_000_000)
            }
        }
    }

    private func endPress() {
        isPressing = false
        repeatTask?.cancel()
        repeatTask = nil
    }
}

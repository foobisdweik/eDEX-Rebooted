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
        return VStack(spacing: CGFloat(metrics.rowGap)) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { descriptor in
                        keyView(descriptor)
                    }
                }
                .frame(height: CGFloat(metrics.rowHeight))
            }
        }
    }

    private func keyView(_ descriptor: KeyboardKeyDescriptor) -> some View {
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

        return ZStack {
            AugmentedBorderShape(style: .settingsButton(vh: vh))
                .fill(isFilled ? accent : accent.opacity(0.06))
            AugmentedBorderShape(style: .settingsButton(vh: vh))
                .stroke(accent.opacity(isEmphasizedEdge ? 0.6 : 0.45), lineWidth: 1)
            keyContent(descriptor, filled: isFilled)
        }
        .frame(width: CGFloat(keyboardKeyWidth(for: descriptor)))
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isFilled)
        .onTapGesture {
            if let modifier = descriptor.modifier {
                onToggleModifier(modifier)
            } else {
                onPressKey(descriptor)
            }
        }
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

    private func keyboardKeyWidth(for descriptor: KeyboardKeyDescriptor) -> Double {
        switch descriptor.role {
        case .spacebar:
            return metrics.spacebarWidth
        case .enter:
            return max(metrics.keySide * 1.8, 9.72 * vh)
        case .enterContinuation:
            return max(metrics.keySide * 1.4, 7.78 * vh)
        case .wide:
            return metrics.keySide * 1.7
        case .standard, .icon:
            return metrics.keySide
        }
    }

    private var keyboardStubBand: some View {
        VStack(spacing: CGFloat(metrics.rowGap)) {
            ForEach(0..<5, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<keyboardKeyCount(for: row), id: \.self) { index in
                        keyStub(width: keyboardKeyWidth(row: row, index: index))
                    }
                }
                .frame(height: CGFloat(metrics.rowHeight))
            }
        }
    }

    private func keyStub(width: Double) -> some View {
        AugmentedBorderShape(style: .settingsButton(vh: vh))
            .stroke(theme.accent.opacity(0.45), lineWidth: 1)
            .background(
                AugmentedBorderShape(style: .settingsButton(vh: vh))
                    .fill(theme.accent.opacity(0.06))
            )
            .frame(width: CGFloat(width), height: 28)
    }

    private func keyboardKeyCount(for row: Int) -> Int {
        let counts = [13, 13, 12, 11, 6]
        guard counts.indices.contains(row) else { return 0 }
        return counts[row]
    }

    private func keyboardKeyWidth(row: Int, index: Int) -> Double {
        if row == 4 && index == 2 {
            return metrics.spacebarWidth
        }
        if index == 0 || index == keyboardKeyCount(for: row) - 1 {
            return metrics.keySide * 1.7
        }
        return metrics.keySide
    }
}

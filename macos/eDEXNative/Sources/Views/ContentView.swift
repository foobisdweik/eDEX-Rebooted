import EdexCoreBridge
import EdexDomainSupport
import EdexRenderingSupport
import SwiftUI

struct ContentView: View {
    @Bindable var state: ShellState
    private let layoutEngine = EdexLayoutEngine()

    var body: some View {
        GeometryReader { proxy in
            let layout = layoutEngine.layout(
                in: LayoutSize(
                    width: Double(proxy.size.width),
                    height: Double(proxy.size.height)
                )
            )

            ZStack(alignment: .topLeading) {
                // Spike B: Metal presentation substrate, default-off. Conditionally
                // mounted so the off path allocates no Metal device/queue/layer at
                // all; the bottom-most layer so it never alters the SDR composite.
                if state.settingsSummary.metalHostEnabled {
                    MetalHostView(
                        headroom: state.displayHeadroom,
                        reducedMotion: state.settingsSummary.reducedMotion,
                        isEnabled: true
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .allowsHitTesting(false)
                }
                background(size: proxy.size)
                column(layout.leftColumn, title: "SYSTEM", subtitle: "", side: .left, vh: layout.vh)
                mainShell(layout.mainShell, vh: layout.vh)
                column(layout.rightColumn, title: "NETWORK", subtitle: "", side: .right, vh: layout.vh)
                if !layout.filesystem.isHidden {
                    filesystem(layout.filesystem, vh: layout.vh)
                }
                keyboard(layout.keyboard, vh: layout.vh)
                statusRibbon(layout.statusRibbon, vh: layout.vh)
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
            .onAppear {
                state.updateFixedReservedRects(layout.fixedReservedRects)
                replaceAllModals(containerSize: proxy.size)
            }
            .onChange(of: layout.fixedReservedRects) { _, rects in
                state.updateFixedReservedRects(rects)
                replaceAllModals(containerSize: proxy.size)
            }
        }
        .foregroundStyle(state.theme.accent)
        .overlay(alignment: .topLeading) {
            // Transparent drag strip for the full-size-content titlebar.
            GeometryReader { proxy in
                let layout = layoutEngine.layout(
                    in: LayoutSize(
                        width: Double(proxy.size.width),
                        height: Double(proxy.size.height)
                    )
                )
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: CGFloat(min(Double(proxy.size.width), layout.statusRibbon.maxX + 8)))
                        .allowsHitTesting(false)
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(WindowDragGesture())
                        .allowsWindowActivationEvents(true)
                }
                .frame(height: 42)
            }
            .frame(height: 42)
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
                    ClockPanel(state: state, vh: vh)
                } else if label == "SYSINFO" {
                    SysinfoPanel(state: state, vh: vh)
                } else if label == "HARDWARE" {
                    HardwarePanel(state: state, vh: vh)
                } else if label == "CPU" {
                    // Finding #5: dedicated View struct → CPU samples (1 Hz)
                    // invalidate only this panel, not the whole ContentView.
                    CpuPanel(state: state, vh: vh)
                } else if label == "RAM" {
                    RamPanel(state: state, vh: vh)
                } else if label == "TOPLIST" {
                    ToplistPanel(state: state, vh: vh)
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
                    let selected = index - 1 == state.terminal.activeTab
                    ZStack(alignment: .topTrailing) {
                        Button {
                            state.handle(.switchTerminal(index - 1))
                        } label: {
                            Text("SHELL \(index)")
                                .font(.custom(state.theme.fonts.main, size: 11))
                                .frame(maxWidth: .infinity, minHeight: 30)
                                .background(selected ? state.theme.accent : state.theme.panelBackground)
                                .foregroundStyle(selected ? state.theme.panelBackground : state.theme.accent)
                                .augmentedSurface(
                                    style: .settingsButton(vh: vh),
                                    fill: selected ? state.theme.accent.opacity(0.2) : state.theme.panelBackground.opacity(0.25),
                                    stroke: state.theme.accent
                                )
                        }
                        .buttonStyle(.plain)

                        if state.terminal.aliveTabs.contains(index - 1) {
                            Button {
                                state.handle(.closeTerminal(index - 1))
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(3)
                                    .foregroundStyle(selected ? state.theme.panelBackground : state.theme.accent.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .help("Close shell \(index)")
                        }
                    }
                }
            }
            EdexTerminalSurface(terminalView: state.terminal.terminalView, theme: state.theme)
                .id(state.terminal.activeTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(state.theme.terminalBackground.opacity(0.92))
                .overlay { EdexTerminalAesthetic(theme: state.theme, vh: vh) }
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
        EdexFilesystemPanel(state: state, vh: vh)
            .positioned(in: frame)
    }

    private func keyboard(_ metrics: KeyboardLayoutMetrics, vh: Double) -> some View {
        EdexKeyboardPanel(
            layout: state.keyboardLayout,
            descriptorRows: state.keyboardDescriptorRows,
            modifiers: state.keyboardModifiers,
            pressedKeyIDs: state.pressedKeyIDs,
            isDetached: state.modalManager.isKeyboardDetached,
            theme: state.theme,
            metrics: metrics,
            vh: vh,
            onToggleModifier: state.toggleKeyboardModifier,
            onPressKey: { state.pressKey($0) }
        )
        .positioned(in: metrics.frame)
    }

    private func modalLayer(size: CGSize, vh: Double) -> some View {
        ForEach(state.modalManager.modals, id: \.id) { modal in
            let modalSize = EdexModalMetrics.size(
                for: modal,
                containerSize: size,
                mediaViewerExpanded: state.mediaViewerExpanded
            )
            let existingRects = existingModalRects(excluding: modal.id, containerSize: size)
            EdexModalChrome(
                state: state,
                modal: modal,
                theme: state.theme,
                vh: vh,
                containerSize: size,
                onFocus: { state.modalManager.focus(modal.id) },
                onMove: { dx, dy in
                    state.moveModal(
                        modal.id,
                        dx: dx,
                        dy: dy,
                        containerSize: size,
                        modalSize: modalSize,
                        existingModalRects: existingRects
                    )
                },
                onClose: { state.closeModal(modal.id) }
            )
            .zIndex(Double(modal.zIndex))
            .onAppear {
                state.moveModal(
                    modal.id,
                    dx: 0,
                    dy: 0,
                    containerSize: size,
                    modalSize: modalSize,
                    existingModalRects: existingRects
                )
            }
            .onChange(of: modalSize) { _, newSize in
                state.moveModal(
                    modal.id,
                    dx: 0,
                    dy: 0,
                    containerSize: size,
                    modalSize: newSize,
                    existingModalRects: existingModalRects(excluding: modal.id, containerSize: size)
                )
            }
        }
    }

    private func existingModalRects(excluding id: EdexModalID, containerSize: CGSize) -> [ModalLayoutRect] {
        state.modalManager.modals.compactMap { modal in
            guard modal.id != id else { return nil }
            let size = EdexModalMetrics.size(
                for: modal,
                containerSize: containerSize,
                mediaViewerExpanded: state.mediaViewerExpanded
            )
            return ModalLayoutRect(
                x: (Double(containerSize.width) - Double(size.width)) / 2 + modal.offsetX,
                y: (Double(containerSize.height) - Double(size.height)) / 2 + modal.offsetY,
                width: Double(size.width),
                height: Double(size.height)
            )
        }
    }

    private func replaceAllModals(containerSize: CGSize) {
        for modal in state.modalManager.modals {
            let size = EdexModalMetrics.size(
                for: modal,
                containerSize: containerSize,
                mediaViewerExpanded: state.mediaViewerExpanded
            )
            state.moveModal(
                modal.id,
                dx: 0,
                dy: 0,
                containerSize: containerSize,
                modalSize: size,
                existingModalRects: existingModalRects(excluding: modal.id, containerSize: containerSize)
            )
        }
    }

    private func sectionTitle(_ left: String, _ right: String) -> some View {
        HStack {
            Text(left)
            Spacer(minLength: 8)
            if !right.isEmpty {
                Text(right)
            }
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

    private func statusRibbon(_ frame: LayoutRect, vh: Double) -> some View {
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
        .positioned(in: frame)
    }
}

private extension EdexLayout {
    var vh: Double {
        viewport.height / 100
    }
}

struct AugmentedBorderShape: Shape {
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

struct AugmentedTickShape: Shape {
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
    let onFocus: () -> Void
    let onMove: (_ dx: Double, _ dy: Double) -> Void
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
            // Finding #2: read `processRows`/`processSort` only inside this
            // child, so the 1 Hz toplist refresh invalidates the table alone
            // and not `ContentView.body` (which used to receive the rows).
            ProcessListModalContent(state: state, theme: theme)
        case .settingsEditor:
            EdexSettingsForm(state: state, theme: theme)
        case .shortcuts:
            EdexShortcutsView(state: state, theme: theme)
        case .textEditor:
            EdexTextEditorView(state: state, theme: theme)
        case .fuzzyFinder:
            EdexFuzzyFinderView(state: state, theme: theme)
        case .mediaViewer:
            EdexMediaViewerView(state: state, theme: theme)
        case .pdfViewer:
            EdexPdfViewerView(state: state, theme: theme)
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
        EdexModalMetrics.size(
            for: modal,
            containerSize: CGSize(width: safeContainerWidth, height: safeContainerHeight),
            mediaViewerExpanded: state.mediaViewerExpanded
        ).width
    }

    private var modalHeight: CGFloat {
        EdexModalMetrics.size(
            for: modal,
            containerSize: CGSize(width: safeContainerWidth, height: safeContainerHeight),
            mediaViewerExpanded: state.mediaViewerExpanded
        ).height
    }

    private var safeContainerWidth: CGFloat {
        containerSize.width.isFinite && containerSize.width > 0 ? containerSize.width : 960
    }

    private var safeContainerHeight: CGFloat {
        containerSize.height.isFinite && containerSize.height > 0 ? containerSize.height : 600
    }
}

private enum EdexModalMetrics {
    static func size(for modal: EdexModalRecord, containerSize: CGSize, mediaViewerExpanded: Bool) -> CGSize {
        let safeWidth = containerSize.width.isFinite && containerSize.width > 0 ? containerSize.width : 960
        let safeHeight = containerSize.height.isFinite && containerSize.height > 0 ? containerSize.height : 600

        return CGSize(
            width: width(for: modal, safeContainerWidth: safeWidth, mediaViewerExpanded: mediaViewerExpanded),
            height: height(for: modal, safeContainerHeight: safeHeight, mediaViewerExpanded: mediaViewerExpanded)
        )
    }

    private static func width(
        for modal: EdexModalRecord,
        safeContainerWidth: CGFloat,
        mediaViewerExpanded: Bool
    ) -> CGFloat {
        if modal.content == .processList {
            return min(max(safeContainerWidth * 0.72, 680), 980)
        }
        if modal.content == .settingsEditor {
            return min(max(safeContainerWidth * 0.5, 520), 760)
        }
        if modal.content == .shortcuts {
            return min(max(safeContainerWidth * 0.5, 520), 780)
        }
        if modal.content == .textEditor {
            return min(max(safeContainerWidth * 0.6, 560), 900)
        }
        if modal.content == .fuzzyFinder {
            return min(max(safeContainerWidth * 0.42, 480), 640)
        }
        if modal.content == .mediaViewer {
            if mediaViewerExpanded {
                return min(max(safeContainerWidth * 0.96, 720), safeContainerWidth)
            }
            return min(max(safeContainerWidth * 0.55, 560), 900)
        }
        if modal.content == .pdfViewer {
            return min(max(safeContainerWidth * 0.6, 560), 900)
        }
        return min(max(safeContainerWidth * 0.42, 380), 740)
    }

    private static func height(
        for modal: EdexModalRecord,
        safeContainerHeight: CGFloat,
        mediaViewerExpanded: Bool
    ) -> CGFloat {
        if modal.content == .processList {
            return min(max(safeContainerHeight * 0.55, 360), 620)
        }
        if modal.content == .settingsEditor {
            return min(max(safeContainerHeight * 0.6, 420), 640)
        }
        if modal.content == .shortcuts {
            return min(max(safeContainerHeight * 0.55, 380), 600)
        }
        if modal.content == .textEditor {
            return min(max(safeContainerHeight * 0.6, 420), 680)
        }
        if modal.content == .fuzzyFinder {
            return min(max(safeContainerHeight * 0.34, 300), 380)
        }
        if modal.content == .mediaViewer {
            if mediaViewerExpanded {
                return min(max(safeContainerHeight * 0.92, 480), safeContainerHeight)
            }
            return min(max(safeContainerHeight * 0.52, 360), 620)
        }
        if modal.content == .pdfViewer {
            return min(max(safeContainerHeight * 0.72, 440), 780)
        }
        return modal.kind == .custom ? 260 : 150
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

// MARK: - Text editor modal (Phase 7.3)

private struct EdexTextEditorView: View {
    @Bindable var state: ShellState
    let theme: NativeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EdexDetachedTextView(text: Binding(
                get: { state.textEditorText },
                set: { state.setTextEditorText($0) }
            ), caret: Binding(
                get: { state.textEditorCaret },
                set: { state.setTextEditorCaret($0) }
            ), theme: theme)
            .background(theme.terminalBackground.opacity(0.72))
            .frame(minHeight: 280, maxHeight: .infinity)
            .overlay(
                Rectangle().strokeBorder(theme.accent.opacity(0.4), lineWidth: 1)
            )

            HStack(spacing: 12) {
                Text(state.textEditorStatus)
                    .font(.custom(theme.fonts.terminal, size: 11))
                    .foregroundStyle(theme.accent.opacity(0.82))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button { state.saveTextFile() } label: {
                    Text("Save to Disk")
                        .font(.custom(theme.fonts.main, size: 11))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(theme.accent)
                        .background(theme.accent.opacity(0.18))
                }
                .buttonStyle(.plain)
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
}

// MARK: - Fuzzy finder modal (Phase 7.2)

private struct EdexFuzzyFinderView: View {
    @Bindable var state: ShellState
    let theme: NativeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EdexDetachedSearchField(text: Binding(
                get: { state.fuzzyQuery },
                set: { state.setFuzzyQuery($0) }
            ), caret: Binding(
                get: { state.fuzzyCaret },
                set: { state.setFuzzyCaret($0) }
            ), placeholder: "Search file in cwd...", theme: theme) {
                state.submitFuzzySelection()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(theme.terminalBackground.opacity(0.72))
            .overlay(Rectangle().strokeBorder(theme.accent.opacity(0.44), lineWidth: 1))

            VStack(spacing: 0) {
                if state.fuzzyResults.isEmpty {
                    noResultsRow
                } else {
                    ForEach(0..<5, id: \.self) { index in
                        if state.fuzzyResults.indices.contains(index) {
                            let item = state.fuzzyResults[index]
                            Button {
                                state.fuzzySelection = index
                            } label: {
                                resultRow(item, selected: index == state.fuzzySelection)
                            }
                            .buttonStyle(.plain)
                        } else {
                            emptyRow
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
            .background(theme.terminalBackground.opacity(0.46))
            .overlay(Rectangle().strokeBorder(theme.accent.opacity(0.32), lineWidth: 1))

            HStack(spacing: 12) {
                Text(state.fuzzyStatus)
                    .font(.custom(theme.fonts.terminal, size: 11))
                    .foregroundStyle(theme.accent.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    state.submitFuzzySelection()
                } label: {
                    Text("Select")
                        .font(.custom(theme.fonts.main, size: 11))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(theme.accent)
                        .background(theme.accent.opacity(0.18))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .augmentedSurface(
            style: .panel(vh: 8),
            fill: theme.terminalBackground.opacity(0.7),
            stroke: theme.accent
        )
        .onKeyPress(.upArrow) {
            state.moveFuzzySelection(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            state.moveFuzzySelection(1)
            return .handled
        }
        .onKeyPress(.return) {
            state.submitFuzzySelection()
            return .handled
        }
    }

    private var noResultsRow: some View {
        HStack(spacing: 8) {
            Text("No results")
                .foregroundStyle(theme.terminalForeground.opacity(0.64))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.custom(theme.fonts.terminal, size: 12))
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(theme.accent.opacity(0.16))
    }

    private var emptyRow: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 27)
    }

    private func resultRow(_ item: FilesystemItem, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol(item.role))
                .font(.system(size: 12))
                .foregroundStyle(theme.accent)
                .frame(width: 18)
            Text(item.name)
                .foregroundStyle(theme.terminalForeground)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(typeLabel(item))
                .foregroundStyle(theme.accent.opacity(0.62))
                .lineLimit(1)
                .frame(width: 86, alignment: .leading)
            Text(item.sizeText)
                .foregroundStyle(theme.accent.opacity(0.8))
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
        }
        .font(.custom(theme.fonts.terminal, size: 11))
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(selected ? theme.accent.opacity(0.18) : Color.clear)
        .opacity(item.hidden ? 0.55 : 1.0)
    }

    private func symbol(_ role: FilesystemRole) -> String {
        switch role {
        case .goUp: return "arrow.up.left"
        case .showDisks: return "externaldrive.connected.to.line.below"
        case .directory: return "folder"
        case .symlink: return "arrowshape.turn.up.right"
        case .file: return "doc"
        case .themesDir: return "paintpalette"
        case .keyboardsDir: return "keyboard"
        case .themeFile: return "paintpalette.fill"
        case .keyboardFile: return "keyboard.fill"
        case .settingsFile: return "gearshape"
        case .shortcutsFile: return "command"
        case .disk: return "internaldrive"
        case .rom: return "opticaldiscdrive"
        case .usb: return "externaldrive"
        }
    }

    private func typeLabel(_ item: FilesystemItem) -> String {
        switch item.role {
        case .goUp, .showDisks: return "--"
        case .directory: return "folder"
        case .symlink: return "symlink"
        case .file: return "file"
        case .themesDir: return "themes"
        case .keyboardsDir: return "keyboards"
        case .themeFile: return "theme"
        case .keyboardFile: return "keyboard"
        case .settingsFile: return "settings"
        case .shortcutsFile: return "shortcuts"
        case .disk: return "disk"
        case .rom: return "rom"
        case .usb: return "usb"
        }
    }
}

/// Finding #2: the only observer of `state.processRows`/`state.processSort`.
/// Keeping these reads here (rather than in `ContentView`/`EdexModalChrome`)
/// confines the 1 Hz toplist invalidation to the process table.
private struct ProcessListModalContent: View {
    @Bindable var state: ShellState
    let theme: NativeTheme

    var body: some View {
        EdexProcessListTable(
            rows: state.processRows,
            sort: state.processSort,
            theme: theme,
            onSort: { field in state.processSort = state.processSort.toggled(field) }
        )
    }
}

private struct EdexProcessListTable: View {
    let rows: [FfiProcessRow]
    let sort: EdexProcessSort
    let theme: NativeTheme
    let onSort: (EdexProcessSortField) -> Void

    private let formatter = EdexToplistFormatter()

    var body: some View {
        // Finding #4: map + parse + sort once per `rows`/`sort` change (here in
        // `body`), not inside the per-second TimelineView closure. Ticks between
        // toplist refreshes reuse `prepared`; only the runtime column recomputes
        // from the already-parsed `startDate`.
        let prepared = formatter.prepared(
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
            sort: sort
        )
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(prepared) { row in
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

    private func processRow(_ row: EdexPreparedProcessRow, now: Date) -> some View {
        HStack(spacing: 0) {
            cell("\(row.pid)", width: 58, alignment: .leading)
            cell(row.name, width: 160, alignment: .leading)
            cell(row.user, width: 90, alignment: .leading)
            cell(row.cpuText, width: 58, alignment: .trailing)
            cell(row.memText, width: 72, alignment: .trailing)
            cell(row.state, width: 82, alignment: .center)
            cell(row.started, width: 154, alignment: .leading)
            cell(
                row.startDate.map { formatter.runtimeText(started: $0, now: now) } ?? "00:00:00:00",
                width: 88,
                alignment: .leading
            )
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

// MARK: - Filesystem panel (Phase 7.1)

private struct EdexFilesystemPanel: View {
    @Bindable var state: ShellState
    let vh: Double

    private var theme: NativeTheme { state.theme }

    /// Rows after the dotfile filter (special rows are never hidden).
    private var visibleItems: [FilesystemItem] {
        state.fsShowDotfiles ? state.fsItems : state.fsItems.filter { !$0.hidden }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
            Spacer(minLength: 0)
            diskBar
        }
        .padding(10)
        .augmentedSurface(
            style: .panel(vh: vh),
            fill: theme.panelBackground.opacity(0.72),
            stroke: theme.accent
        )
        .task { await state.loadInitialFilesystemIfNeeded() }
        .task {
            // Follow the active terminal tab's cwd. terminal.class.js polled
            // pty_metadata at 1s; match that cadence.
            while !Task.isCancelled {
                await state.refreshTerminalMetadata()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("FILESYSTEM")
                .font(.custom(theme.fonts.main, size: 11))
            HStack(spacing: 6) {
                toggleButton(symbol: "eye", active: state.fsShowDotfiles) { state.toggleFsDotfiles() }
                toggleButton(symbol: "list.bullet", active: state.fsListView) { state.toggleFsListView() }
            }
            Spacer(minLength: 8)
            Text(headerPath)
                .font(.custom(theme.fonts.terminal, size: 10))
                .foregroundStyle(theme.accent.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .foregroundStyle(theme.accent.opacity(0.76))
        .padding(.horizontal, 5)
        .padding(.bottom, 3)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.accent.opacity(0.28)).frame(height: 1)
        }
    }

    private var headerPath: String {
        if state.fsFailed { return "CANNOT ACCESS DIRECTORY" }
        if state.fsIsDiskView { return "Showing available block devices" }
        return state.fsPath
    }

    private func toggleButton(symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(active ? theme.accent : theme.accent.opacity(0.35))
                .frame(width: 20, height: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if state.fsFailed {
            Text("EXECUTION FAILED")
                .font(.custom(theme.fonts.main, size: 13))
                .foregroundStyle(theme.accent.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.fsListView {
            listView
        } else {
            gridView
        }
    }

    private var gridView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                spacing: 8
            ) {
                ForEach(visibleItems) { item in
                    Button { state.activateFsItem(item) } label: { gridCell(item) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func gridCell(_ item: FilesystemItem) -> some View {
        VStack(spacing: 3) {
            entryIcon(item, size: 18)
                .frame(height: 22)
            Text(item.name)
                .font(.custom(theme.fonts.terminal, size: 9))
                .foregroundStyle(theme.terminalForeground)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .top)
        .opacity(item.hidden ? 0.55 : 1.0)
    }

    private var listView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(visibleItems) { item in
                    Button { state.activateFsItem(item) } label: { listRow(item) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func listRow(_ item: FilesystemItem) -> some View {
        HStack(spacing: 8) {
            entryIcon(item, size: 12)
                .frame(width: 18)
            Text(item.name)
                .foregroundStyle(theme.terminalForeground)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(typeLabel(item))
                .foregroundStyle(theme.accent.opacity(0.62))
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
            Text(item.sizeText)
                .foregroundStyle(theme.accent.opacity(0.8))
                .lineLimit(1)
                .frame(width: 70, alignment: .trailing)
        }
        .font(.custom(theme.fonts.terminal, size: 10))
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .opacity(item.hidden ? 0.55 : 1.0)
    }

    // MARK: Disk-usage bar

    @ViewBuilder
    private var diskBar: some View {
        if state.fsIsDiskView {
            Button {
                Task { await state.navigateFS(to: state.fsPath) }
            } label: {
                barLabel(text: "EXIT DISPLAY", fill: 1.0)
            }
            .buttonStyle(.plain)
        } else if let usage = state.fsDiskUsage {
            let pct = DiskUsageFormatter.percent(usage)
            barLabel(
                text: "Mount \(DiskUsageFormatter.displayMount(usage.mount)) used \(pct)%",
                fill: Double(min(max(pct, 0), 100)) / 100.0
            )
        } else {
            barLabel(text: "Could not calculate mountpoint usage.", fill: 1.0)
        }
    }

    private func barLabel(text: String, fill: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text)
                .font(.custom(theme.fonts.terminal, size: 9))
                .foregroundStyle(theme.accent.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.middle)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(theme.accent.opacity(0.22))
                    Rectangle()
                        .fill(theme.accent)
                        .frame(width: geo.size.width * fill)
                }
            }
            .frame(height: 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Role → presentation

    /// Themed file-icons glyph (the legacy fsDisp SVG set) with the SF Symbol
    /// as the pre-load / parse-failure fallback.
    @ViewBuilder
    private func entryIcon(_ item: FilesystemItem, size: CGFloat) -> some View {
        if let icon = FileIconProvider.shared.image(forName: item.name, role: item.role, theme: theme) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: size + 4, height: size + 4)
        } else {
            Image(systemName: symbol(item.role))
                .font(.system(size: size))
                .foregroundStyle(theme.accent)
        }
    }

    private func symbol(_ role: FilesystemRole) -> String {
        switch role {
        case .goUp: return "arrow.up.left"
        case .showDisks: return "externaldrive.connected.to.line.below"
        case .directory: return "folder"
        case .symlink: return "arrowshape.turn.up.right"
        case .file: return "doc"
        case .themesDir: return "paintpalette"
        case .keyboardsDir: return "keyboard"
        case .themeFile: return "paintpalette.fill"
        case .keyboardFile: return "keyboard.fill"
        case .settingsFile: return "gearshape"
        case .shortcutsFile: return "command"
        case .disk: return "internaldrive"
        case .rom: return "opticaldiscdrive"
        case .usb: return "externaldrive"
        }
    }

    private func typeLabel(_ item: FilesystemItem) -> String {
        switch item.role {
        case .goUp, .showDisks: return "--"
        case .directory: return "folder"
        case .symlink: return "symlink"
        case .themesDir: return "themes folder"
        case .keyboardsDir: return "keyboards folder"
        case .themeFile: return "eDEX-UI theme"
        case .keyboardFile: return "eDEX-UI keyboard"
        case .settingsFile, .shortcutsFile: return "eDEX-UI config"
        case .disk: return "disk"
        case .rom: return "rom"
        case .usb: return "usb"
        case .file:
            if let dot = item.name.lastIndex(of: "."), dot != item.name.startIndex {
                return String(item.name[item.name.index(after: dot)...]).lowercased()
            }
            return "file"
        }
    }
}

extension View {
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

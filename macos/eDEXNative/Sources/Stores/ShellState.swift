import AppKit
import AVFoundation
import Darwin
import EdexCoreBridge
import EdexDomainSupport
import Foundation
import Observation
import EdexRenderingSupport
import SwiftUI

@Observable
@MainActor
final class ShellState: EdexActionHandler {
    @ObservationIgnored private let core: EdexCore
    private let client: EdexCoreClient
    private let audio = EdexAudioService()

    let modalManager = EdexModalManager()
    let terminal: TerminalStore
    let keyboard = KeyboardStore()
    var statusText = "booting"
    var paths: FfiPaths?
    var settingsSummary = SettingsSummary()
    var keepGeometry = true
    var theme = NativeTheme.fallback
    var uptimeSeconds: UInt64 = 0
    var battery: FfiBattery?
    var hardware: FfiHardware?
    var cpu: FfiCpuSnapshot?
    /// Timestamp of the last appended CPU sample; the graph interpolates its
    /// horizontal scroll against this so motion is smooth between 1 Hz samples.
    var cpuLastSampleDate = Date()
    private var cpuBuffer = CpuSeriesBuffer(coreCount: 0, capacity: cpuSampleCapacity)
    /// Per-core CPU load history feeding the two scrolling graphs.
    var cpuSeries: [[Double]] { cpuBuffer.series }
    private static let cpuSampleCapacity = 64

    var mem: FfiMemSnapshot?
    var topProcesses = [FfiTopProcessRow]()
    var processRows = [FfiProcessRow]()
    var processSort = EdexProcessSort.default
    @ObservationIgnored private var processListModalID: EdexModalID?
    @ObservationIgnored private var processListRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var fixedReservedRects = [ModalLayoutRect]()

    // Phase 6.5 boot screen state.
    /// Which stage of the boot sequence is active.
    var bootStage: EdexBootStage = .logScroll
    /// Lines accumulated so far during the log-scroll stage.
    var bootDisplayLines: [String] = []

    // Phase 7.1 filesystem panel state.
    /// Current directory being displayed. Starts at the user's home; Phase 9.5
    /// wires the panel to follow the active terminal tab's CWD (see
    /// `refreshTerminalMetadata`).
    var fsPath: String = NSHomeDirectory()
    /// The displayed rows (directory listing or "Show disks" view).
    var fsItems: [FilesystemItem] = []
    /// Disk-usage bar selection for the current directory's mount.
    var fsDiskUsage: DiskUsage?
    /// View toggles (initialized from settings in bootstrap).
    var fsShowDotfiles = true
    var fsListView = false
    /// Whether the panel is showing the block-device list rather than a directory.
    var fsIsDiskView = false
    /// Set when the current directory could not be read.
    var fsFailed = false
    @ObservationIgnored private var fsReading = false
    /// The terminal cwd the filesystem panel last auto-followed. Compared against
    /// each metadata poll so manual browsing isn't yanked back — only a real `cd`
    /// (which changes the shell cwd) re-navigates the panel (Phase 9.5).
    @ObservationIgnored private var lastFollowedCwd: String?
    /// Serializes metadata polls and cwd-follow work so overlapping 1 Hz polls and
    /// tab-switch follow-ups cannot apply stale PTY reads or skip navigation.
    @ObservationIgnored private var terminalMetadataRefreshTail: Task<Void, Never>?
    @ObservationIgnored private var keyboardFileApplyGeneration: UInt = 0
    @ObservationIgnored private var stdoutCueGate = StdoutAudioCueGate()

    // Phase 7.2 fuzzy finder state.
    var fuzzyQuery = ""
    var fuzzyResults: [FilesystemItem] = []
    var fuzzySelection = 0
    var fuzzyStatus = ""
    @ObservationIgnored var pendingTerminalInput: String?
    @ObservationIgnored private var fuzzyFinderModalID: EdexModalID?
    var fuzzyCaret = 0

    // Phase 7.3 text editor state.
    /// The document open in the editor modal, or nil when closed.
    var textDocument: EdexTextDocument?
    /// Status line under the editor (metrics, save success/failure).
    var textEditorStatus = ""
    @ObservationIgnored private var textEditorModalID: EdexModalID?
    var textEditorCaret = 0

    // Phase 10.1 media viewer state.
    var mediaViewerPath: String?
    var mediaViewerKind: MediaKind?
    var mediaViewerPlayer: AVPlayer?
    var mediaViewerExpanded = false
    var mediaViewerMuted = false
    /// Stored (not read from `AVPlayer.volume`) so the control bar observes
    /// volume changes — AVPlayer itself is invisible to `@Observable`.
    var mediaViewerVolume: Double = 1
    @ObservationIgnored private var mediaViewerModalID: EdexModalID?
    @ObservationIgnored private var mediaViewerVolumeBeforeMute: Float = 1
    var pdfViewerPath: String?
    @ObservationIgnored private var pdfViewerModalID: EdexModalID?

    // Phase 6.4 shortcuts state.
    var shortcuts: EdexShortcutsDocument?
    var shortcutsStatus = ""
    @ObservationIgnored private var shortcutsModalID: EdexModalID?
    @ObservationIgnored private var shortcutMonitor: Any?
    @ObservationIgnored private var keyUpMonitor: Any?
    @ObservationIgnored private var modifierMonitor: Any?

    // Phase 6.3 settings editor state.
    var settingsDocument = EdexSettingsDocument()
    var settingsThemeOptions = [String]()
    var settingsKeyboardOptions = [String]()
    var settingsStatus = ""
    /// The document as last loaded/saved; restart-required diffing is against this.
    @ObservationIgnored private var settingsBaseline = EdexSettingsDocument()
    @ObservationIgnored private var settingsModalID: EdexModalID?
    /// A fixed random permutation of the 440 grid positions → dot ranks, shuffled
    /// once (like the legacy `shuffleArray`) so the active/available regions
    /// scatter across the grid instead of filling left-to-right.
    let ramGridRanks: [Int] = Array(0..<EdexRamwatcherFormatter.gridCellCount).shuffled()

    init() {
        let core = EdexCore()
        self.core = core
        self.client = EdexCoreClient(core: core)
        self.terminal = TerminalStore(core: core)
        terminal.onStdout = { [weak self] in
            guard let self else { return }
            if self.stdoutCueGate.shouldPlay(at: Date(), passwordMode: self.keyboard.modifiers.passwordMode) {
                self.playAudio(.stdout)
            }
        }
    }

    /// Bridges the FFI battery record into the FFI-free `EdexDomainSupport` input.
    /// Falls back to a wired/no-battery state (POWER → "ON") before the first poll.
    var powerState: EdexPowerState {
        guard let battery else {
            return EdexPowerState(hasBattery: false, isCharging: false, acConnected: true, percent: 0)
        }
        return EdexPowerState(
            hasBattery: battery.hasBattery,
            isCharging: battery.isCharging,
            acConnected: battery.acConnected,
            percent: Int(battery.percent)
        )
    }

    // MARK: - Focused stores exposed for current views

    var keyboardLayout: NativeKeyboardLayout? {
        get { keyboard.layout }
        set { keyboard.layout = newValue }
    }

    /// Finding #3: the cached on-screen keyboard matrix for the current layout
    /// (built once per layout via `KeyboardDescriptorIndex`), so the keyboard
    /// panel no longer rebuilds it on every keystroke-driven re-render.
    var keyboardDescriptorRows: [[KeyboardKeyDescriptor]] {
        keyboard.descriptorIndex?.rows ?? []
    }

    var keyboardStatus: String {
        get { keyboard.status }
        set { keyboard.status = newValue }
    }

    var keyboardModifiers: KeyboardModifierState {
        get { keyboard.modifiers }
        set { keyboard.modifiers = newValue }
    }

    var pressedKeyIDs: Set<String> {
        get { keyboard.pressedKeyIDs }
        set { keyboard.pressedKeyIDs = newValue }
    }

    // MARK: - Action routing

    func handle(_ action: EdexAction) {
        switch action {
        case let .keyboardInput(text):
            terminal.sendInput(text)
            pendingTerminalInput = text
        case .openSettings:
            openSettingsModal()
        case .openFuzzyFinder:
            openFuzzyFinder()
        case let .switchTerminal(index):
            terminal.switchTab(index)
            followActiveTabSoon()
        case let .closeTerminal(index):
            terminal.closeTab(index)
        case .closeModal:
            guard let top = modalManager.modals.max(by: { $0.zIndex < $1.zIndex }) else { return }
            closeModal(top.id)
        }
    }

    func updateFixedReservedRects(_ rects: [LayoutRect]) {
        fixedReservedRects = rects
            .filter { !$0.isHidden && $0.width > 0 && $0.height > 0 }
            .map {
                ModalLayoutRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
            }
    }

    func moveModal(
        _ id: EdexModalID,
        dx: Double,
        dy: Double,
        containerSize: CGSize,
        modalSize: CGSize,
        existingModalRects: [ModalLayoutRect] = []
    ) {
        let viewport = ModalLayoutRect(
            x: 0,
            y: 0,
            width: Double(containerSize.width),
            height: Double(containerSize.height)
        )
        let size = ModalLayoutSize(width: Double(modalSize.width), height: Double(modalSize.height))
        modalManager.move(
            id,
            dx: dx,
            dy: dy,
            placement: ModalPlacementContext(
                viewport: viewport,
                modalSize: size,
                reserved: fixedReservedRects,
                existing: existingModalRects
            )
        )
    }

    func bootstrap() async {
        do {
            let snapshot = try client.bootstrap()
            paths = snapshot.paths
            settingsSummary = snapshot.settings
            keepGeometry = snapshot.settings.keepGeometry
            fsShowDotfiles = !snapshot.settings.hideDotfiles
            fsListView = snapshot.settings.fsListView
            theme = snapshot.theme
            await loadKeyboardLayout(named: snapshot.settings.keyboard)
            audio.configure(settings: snapshot.settings.audioSettings)
            statusText = "ok — EdexCore.paths(), ensureUserdata(), loadSettingsJson(), loadThemeJson() returned"
            print("eDEXNative FFI OK userData=\(snapshot.paths.userData) settingsBytes=\(snapshot.settings.byteCount ?? 0) theme=\(snapshot.settings.theme) keepGeometry=\(snapshot.settings.keepGeometry)")
            await loadShortcuts()
            terminal.start(settings: settingsSummary, theme: theme)
            terminateIfSmokeWindow()
        } catch {
            statusText = "error — \(error.localizedDescription)"
            presentModal(type: "error", title: "Native bootstrap failed", message: error.localizedDescription)
            print("eDEXNative FFI ERROR \(error.localizedDescription)")
            terminateIfSmokeWindow()
        }
    }

    // MARK: - Boot sequence (Phase 6.5)

    /// Drives the boot screen overlay. Called from BootView's task{} once after
    /// the view appears. Matches the legacy renderer.js displayLine() timing.
    ///
    /// nointro skips straight to complete (BootView removes itself immediately).
    func runBootSequence() async {
        guard !BootSequenceConfig.shouldSkipLog(nointro: settingsSummary.nointro) else {
            bootStage = .complete
            return
        }

        let lines = BootLines.rawLines
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0.0"
        let dateString = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium)
        let synthetic = BootLines.syntheticKernelLine(appVersion: appVersion, date: dateString)

        bootStage = .logScroll
        bootDisplayLines = []

        do {
            for (index, line) in lines.enumerated() {
                bootDisplayLines.append(line)
                if line == "Boot Complete" {
                    playAudio(.granted)
                } else {
                    playAudio(.stdout)
                }
                // Inject synthetic kernel-version line after line index 1 (mirrors JS i===2).
                if index == 1 {
                    bootDisplayLines.append(synthetic)
                }
                let delay = BootTiming.delay(forLine: index)
                try await Task.sleep(for: .seconds(delay))
            }

            // 300ms gap before the title flash (mirrors the displayTitleScreen call site).
            try await Task.sleep(for: .milliseconds(300))
            playAudio(.theme)
            bootStage = .titleFlash
            // TitleFlashView drives its own animation and sets bootStage = .complete when done.
        } catch {
            // Task was cancelled (e.g. app quit or view dismissed) — exit without
            // completing the sequence or playing further audio.
        }
    }

    /// Pulls uptime + battery from the Rust core for the sysinfo panel. The
    /// battery query hits IOKit (a few ms), so the FFI calls are offloaded to a
    /// background task to keep the main thread free; results land back on the
    /// MainActor. The panel polls this on a timer (see ContentView).
    func refreshSysinfo() async {
        let client = self.client
        let (uptime, battery) = await Task.detached(priority: .background) {
            (client.uptimeSeconds(), client.battery())
        }.value
        uptimeSeconds = uptime
        // Finding #5: battery is frequently identical between 3 s polls (stable
        // charge / on AC); skip the assignment so the sysinfo panel isn't
        // invalidated for unchanged data.
        if self.battery != battery {
            self.battery = battery
        }
    }

    /// Pulls host hardware identity from the Rust core for the hardware-inspector
    /// panel. Offloaded off the MainActor like `refreshSysinfo()`. The data is
    /// effectively static at runtime; the panel re-polls on the legacy 20s cadence.
    func refreshHardware() async {
        let client = self.client
        let latest = await Task.detached(priority: .background) {
            client.hardware()
        }.value
        // Finding #5: hardware identity is static on this target but re-polled
        // every 20 s; only assign when it actually differs so the panel isn't
        // invalidated on every poll.
        if hardware != latest {
            hardware = latest
        }
    }

    /// Pulls a fresh CPU snapshot for the cpuinfo panel, appends it to the
    /// per-core sample buffer, and stamps the sample time. The FFI call (a full
    /// system refresh) is offloaded off the MainActor; the panel polls 1 Hz.
    func refreshCpu() async {
        let client = self.client
        guard let snapshot = await Task.detached(priority: .background, operation: {
            client.cpuSnapshot()
        }).value else { return }

        if cpuBuffer.coreCount != Int(snapshot.cores) {
            cpuBuffer = CpuSeriesBuffer(coreCount: Int(snapshot.cores), capacity: Self.cpuSampleCapacity)
        }
        cpuBuffer.append(loads: snapshot.loads)
        cpuLastSampleDate = Date()
        cpu = snapshot
    }

    /// Pulls a memory snapshot for the ramwatcher panel, offloaded off the
    /// MainActor. The panel polls every 1.5s (legacy cadence).
    func refreshMem() async {
        let client = self.client
        mem = await Task.detached(priority: .background) {
            client.memSnapshot()
        }.value
    }

    /// Pulls the compact TOPLIST rows. The expanded process rows are only
    /// requested while the process modal is open because that Rust snapshot is
    /// the heaviest telemetry poll in this phase.
    func refreshToplist(includeProcessList: Bool = false) async {
        let client = self.client
        let collapseThreadsByName = settingsSummary.excludeThreadsFromToplist
        guard let snapshot = await Task.detached(priority: .background, operation: {
            client.toplistSnapshot(
                collapseThreadsByName: collapseThreadsByName,
                includeProcessList: includeProcessList
            )
        }).value else { return }

        // Finding #5: @Observable notifies on every assignment regardless of
        // equality, so guard against no-op writes. When the host is idle the
        // top-process set and its rounded metrics are often identical between
        // polls; skipping the write then avoids a needless panel/table
        // invalidation. (Both Ffi row types are Equatable.)
        let newTop = snapshot.topProcesses
        if topProcesses != newTop {
            topProcesses = newTop
        }
        if includeProcessList {
            let newRows = snapshot.processList?.list ?? []
            if processRows != newRows {
                processRows = newRows
            }
        }
    }

    func openProcessListModal() {
        if let processListModalID, modalManager.modal(id: processListModalID) != nil {
            modalManager.focus(processListModalID)
            return
        }

        processSort = .default
        let openedID = presentModal(
            type: "custom",
            title: "Active Processes",
            message: "",
            content: .processList,
            onClose: { [weak self] closedID in
                Task { @MainActor in
                    guard self?.processListModalID == closedID else { return }
                    self?.processListModalID = nil
                    self?.processListRefreshTask?.cancel()
                    self?.processListRefreshTask = nil
                }
            }
        )
        processListModalID = openedID
        guard openedID != nil else { return }

        processListRefreshTask?.cancel()
        processListRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshToplist(includeProcessList: true)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: Settings editor (Phase 6.3)

    func openSettingsModal() {
        if let settingsModalID, modalManager.modal(id: settingsModalID) != nil {
            modalManager.focus(settingsModalID)
            return
        }

        let client = self.client
        Task {
            let (json, themes, keyboards) = await Task.detached(priority: .background) {
                (
                    (try? client.loadSettingsJson()) ?? "{}",
                    client.listThemes(),
                    client.listKeyboards()
                )
            }.value

            let document: EdexSettingsDocument
            let statusLine: String
            do {
                document = try EdexSettingsDocument(jsonString: json)
                statusLine = "Loaded values from settings.json"
            } catch {
                // Malformed/non-object settings.json: edit from defaults, but warn
                // that a save replaces the unreadable file rather than silently doing so.
                document = EdexSettingsDocument()
                statusLine = "settings.json could not be parsed; showing defaults. Saving will overwrite it."
            }
            settingsDocument = document
            settingsBaseline = document
            settingsThemeOptions = themes
            settingsKeyboardOptions = keyboards
            settingsStatus = statusLine

            let openedID = presentModal(
                type: "custom",
                title: "Settings",
                message: "",
                content: .settingsEditor,
                detachesKeyboard: true,
                onClose: { [weak self] closedID in
                    Task { @MainActor in
                        guard self?.settingsModalID == closedID else { return }
                        self?.settingsModalID = nil
                    }
                }
            )
            settingsModalID = openedID
        }
    }

    func saveSettings() {
        let document = settingsDocument
        let client = self.client
        Task {
            let result: Result<Void, Error> = await Task.detached(priority: .background) {
                do {
                    try client.writeSettings(try document.jsonString())
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success:
                let changed = EdexSettingsDocument.restartRequiredKeys(from: settingsBaseline, to: document)
                settingsBaseline = document
                applyLiveSettings(document)
                playAudio(.granted)
                settingsStatus = changed.isEmpty
                    ? "Saved to settings.json."
                    : "Saved. Restart required for: \(changed.joined(separator: ", "))."
            case let .failure(error):
                playAudio(.denied)
                settingsStatus = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    func openSettingsFileExternally() {
        guard let path = paths?.settingsFile else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    // Typed bindings for the settings form (mutating the stored value type
    // republishes via Observation, so SwiftUI controls stay in sync).
    func settingsString(_ key: EdexSettingsKey) -> String { settingsDocument.string(key) ?? "" }
    func settingsInt(_ key: EdexSettingsKey) -> Int { settingsDocument.int(key) ?? 0 }
    func settingsBool(_ key: EdexSettingsKey) -> Bool { settingsDocument.bool(key) ?? false }
    func settingsDouble(_ key: EdexSettingsKey) -> Double { settingsDocument.double(key) ?? 0 }
    func setSettingsString(_ value: String, for key: EdexSettingsKey) { settingsDocument.setString(value, for: key) }
    func setSettingsInt(_ value: Int, for key: EdexSettingsKey) { settingsDocument.setInt(value, for: key) }
    func setSettingsBool(_ value: Bool, for key: EdexSettingsKey) { settingsDocument.setBool(value, for: key) }
    func setSettingsDouble(_ value: Double, for key: EdexSettingsKey) { settingsDocument.setDouble(value, for: key) }

    /// Re-applies the settings that can take effect without a restart (theme,
    /// clock format, audio, toplist thread collapsing, windowed geometry).
    private func applyLiveSettings(_ document: EdexSettingsDocument) {
        settingsSummary.clockHours = document.int(.clockHours) ?? 24
        settingsSummary.keepGeometry = document.bool(.keepGeometry) ?? true
        settingsSummary.excludeThreadsFromToplist = document.bool(.excludeThreadsFromToplist) ?? true
        settingsSummary.nointro = document.bool(.nointro) ?? false
        settingsSummary.reducedMotion = document.bool(.reducedMotion) ?? false
        keepGeometry = settingsSummary.keepGeometry

        let audioSettings = EdexAudioSettings(
            audio: document.bool(.audio) ?? true,
            audioVolume: document.double(.audioVolume) ?? 1.0,
            disableFeedbackAudio: document.bool(.disableFeedbackAudio) ?? false
        )
        settingsSummary.audioSettings = audioSettings
        audio.configure(settings: audioSettings)

        let themeName = document.string(.theme) ?? "tron"
        guard themeName != settingsSummary.theme else { return }
        let client = self.client
        Task {
            do {
                let themeJson = try await Task.detached(priority: .background) {
                    try client.loadThemeJson(themeName)
                }.value
                // Update the label only after the visuals actually change, so the
                // status ribbon never claims a theme that failed to load.
                theme = try NativeTheme(json: themeJson, name: themeName)
                settingsSummary.theme = themeName
            } catch {
                settingsStatus = "Saved, but theme '\(themeName)' could not be loaded: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Keyboard layout (Phase 8.1)

    func loadKeyboardLayout(named name: String) async {
        let client = self.client
        let result: Result<NativeKeyboardLayout, Error> = await Task.detached(priority: .background) {
            do {
                return .success(try client.loadKeyboardLayout(name))
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case let .success(layout):
            keyboardLayout = layout
            keyboardStatus = "Loaded \(layout.name) keyboard layout (\(layout.keyCount) keys)"
        case let .failure(error):
            keyboardLayout = nil
            keyboardStatus = "Keyboard layout \(name) failed: \(error.localizedDescription)"
        }
    }

    // MARK: Keyboard view (Phase 8.2)

    /// Toggle a modifier's visual state. Caps/Fn behave as sticky toggles like
    /// the legacy on-screen keyboard; Shift/Alt/Ctrl toggle here too so the
    /// label-emphasis rendering can be exercised before Phase 8.3 wires real
    /// press-and-hold + routing semantics.
    func toggleKeyboardModifier(_ modifier: KeyboardModifier) {
        keyboard.toggleModifier(modifier)
    }

    /// Handle an on-screen (non-modifier) key tap: flash it, resolve the command
    /// against the current modifier/dead-key state and loaded shortcuts, then
    /// apply the outcome (fire a shortcut, emit text, arm a dead key, or toggle
    /// Caps/Fn). Modifier keys (Shift/Ctrl/Alt/Caps/Fn) arrive via
    /// `toggleKeyboardModifier` instead.
    func pressKey(_ descriptor: KeyboardKeyDescriptor) {
        keyboard.pressVisual(id: descriptor.id)

        let outcome = KeyboardCommandResolver.resolve(
            key: descriptor.key,
            modifiers: keyboard.modifiers,
            armedDeadKey: keyboard.armedDeadKey,
            shortcuts: shortcuts
        )

        // Consume armed dead key when used; preserve it only across app shortcut
        // interception (legacy returns early only when `shortcutsTriggered`).
        if !outcome.preservesArmedDeadKey {
            keyboard.armedDeadKey = nil
        }

        var isEnter = false
        switch outcome {
        case let .shortcut(match):
            dispatchShortcutMatch(match)
        case let .emit(text):
            isEnter = (text == "\r" || text == "\n")
            routeEmit(text)
        case let .armDeadKey(deadKey):
            keyboard.armedDeadKey = deadKey
        case let .setCapsLock(on):
            keyboard.modifiers.capsLock = on
        case let .setFn(on):
            keyboard.modifiers.fn = on
        case .none:
            break
        }

        // Audio: enter plays the granted cue, every other press plays stdin —
        // both silenced in password mode (legacy `passwordMode == "false"`).
        if !keyboard.modifiers.passwordMode {
            playAudio(isEnter ? .granted : .stdin)
        }

        // On-screen taps can't press-and-hold, so transient modifiers act as
        // one-shot: applied to this key, then released. Caps/Fn stay latched.
        keyboard.modifiers.shift = false
        keyboard.modifiers.ctrl = false
        keyboard.modifiers.alt = false
    }

    /// Fires a matched shortcut from the on-screen keyboard. App actions dispatch
    /// through the existing handler; shell actions write their command text to the
    /// active sink (legacy on-screen `term.write(cut.action)`).
    private func dispatchShortcutMatch(_ match: ShortcutMatch) {
        switch match {
        case let .app(action, tabIndex):
            dispatchAppShortcut(action, tabIndex: tabIndex)
        case let .shell(action, linebreak):
            // Shell shortcuts always target the terminal (legacy on-screen
            // `term.write(cut.action)`), even while a modal holds the keyboard —
            // they bypass detached-field routing.
            handle(.keyboardInput(linebreak ? action + "\r" : action))
        }
    }

    /// Routes an emitted string to the active sink: a detached native text field
    /// when a keyboard-owning modal is open, otherwise the terminal. While
    /// detached with no text target (e.g. the shortcuts list), input is swallowed
    /// rather than leaking to the hidden terminal (legacy `linkedToTerm == false`).
    private func routeEmit(_ text: String) {
        guard modalManager.isKeyboardDetached else {
            handle(.keyboardInput(text))
            return
        }
        guard let field = activeDetachedField else { return }
        if let delta = KeyboardDetachedEditor.verticalDelta(command: text),
           let moveVertical = field.moveVertical {
            moveVertical(delta)
            return
        }
        switch KeyboardDetachedEditor.apply(command: text, to: field.state) {
        case let .replace(newState): field.setState(newState)
        case .submit: field.submit()
        case .ignore: break
        }
    }

    /// The focused text field while the keyboard is detached, or nil when the
    /// open modal has no text input. The fuzzy finder submits its selection on
    /// Enter; the text editor inserts a newline instead.
    private var activeDetachedField: DetachedField? {
        if let id = fuzzyFinderModalID, modalManager.modal(id: id) != nil {
            return DetachedField(
                state: KeyboardDetachedEditor.State(text: fuzzyQuery, caret: fuzzyCaret),
                setState: { [weak self] in self?.setFuzzyState($0) },
                submit: { [weak self] in self?.submitFuzzySelection() },
                moveVertical: { [weak self] in self?.moveFuzzySelection($0) }
            )
        }
        if let id = textEditorModalID, modalManager.modal(id: id) != nil {
            return DetachedField(
                state: KeyboardDetachedEditor.State(text: textEditorText, caret: textEditorCaret),
                setState: { [weak self] in self?.setTextEditorState($0) },
                submit: { [weak self] in
                    guard let self else { return }
                    let state = KeyboardDetachedEditor.State(text: textEditorText, caret: textEditorCaret)
                    var text = state.text
                    let insertIndex = text.index(atUTF16Offset: state.caret)
                    text.insert("\n", at: insertIndex)
                    let newCaret = text.utf16Offset(of: text.index(after: insertIndex))
                    setTextEditorState(KeyboardDetachedEditor.State(text: text, caret: newCaret))
                }
            )
        }
        return nil
    }

    private struct DetachedField {
        let state: KeyboardDetachedEditor.State
        let setState: (KeyboardDetachedEditor.State) -> Void
        let submit: () -> Void
        /// List-style fields override vertical arrows (the fuzzy finder moves
        /// its result selection); nil falls through to line-aware caret moves.
        var moveVertical: ((Int) -> Void)?
    }

    // MARK: Filesystem panel (Phase 7.1)

    /// eDEX userdata paths that drive the special theme/keyboard/settings tagging.
    private var fsContext: FilesystemContext {
        FilesystemContext(
            userDataDir: paths?.userData,
            themesDir: paths?.themesDir,
            keyboardsDir: paths?.keyboardsDir
        )
    }

    /// Polls the active terminal tab's metadata (1 Hz, matching the legacy
    /// terminal.class.js cadence) and follows its working directory in the
    /// filesystem panel. Mirrors the legacy `followTab`: a real `cd` re-navigates
    /// the panel, but manual browsing is left alone (see `TerminalCwdFollow`).
    func refreshTerminalMetadata() async {
        await enqueueTerminalMetadataRefresh().value
    }

    /// Re-follows the active tab's cwd immediately after a tab switch instead of
    /// waiting up to a full poll interval (legacy `resendCWD`).
    private func followActiveTabSoon() {
        _ = enqueueTerminalMetadataRefresh()
    }

    private func enqueueTerminalMetadataRefresh() -> Task<Void, Never> {
        let prior = terminalMetadataRefreshTail
        let task = Task { @MainActor [weak self] in
            if let prior { await prior.value }
            guard let self else { return }
            await self.performTerminalMetadataRefresh()
        }
        terminalMetadataRefreshTail = task
        return task
    }

    private func performTerminalMetadataRefresh() async {
        await terminal.refreshActiveMetadata()
        // Feed the *raw* (possibly nil) cwd: a poll that can't read the shell's
        // cwd must not be coerced to home (TerminalStore.activeCwd does that for
        // display), which would look like a real `cd ~` and yank the panel.
        switch TerminalCwdFollow.decide(
            newCwd: terminal.activeCwdRaw,
            lastFollowedCwd: lastFollowedCwd,
            isDiskView: fsIsDiskView
        ) {
        case let .navigate(path):
            switch await navigateFS(to: path) {
            case .navigated, .failed:
                // The follow resolved: either the panel now shows `path`, or the
                // directory is unreadable (a hard failure already played the
                // denied cue once). Stamp so the 1 Hz poll stops re-attempting —
                // and stops replaying that cue — until the shell cwd changes again.
                lastFollowedCwd = path
            case .skipped:
                // Another read held `fsReading`; leave `lastFollowedCwd` unset so
                // the next poll retries this still-pending follow.
                break
            }
        case .ignore:
            break
        }
    }

    /// First load when the panel appears. Re-entrant-safe; no-op once populated.
    func loadInitialFilesystemIfNeeded() async {
        guard fsItems.isEmpty, !fsFailed, !fsReading else { return }
        await navigateFS(to: fsPath)
    }

    /// Reads a directory and rebuilds the displayed rows. The FFI listing runs
    /// off the MainActor; results land back here. A read failure sets the failed
    /// state and plays the denied cue (mirrors the legacy setFailedState path).
    @discardableResult
    func navigateFS(to path: String) async -> FilesystemNavigationOutcome {
        guard !fsReading else { return .skipped }
        fsReading = true
        defer { fsReading = false }

        let client = self.client
        let entries = await Task.detached(priority: .userInitiated) {
            try? client.fsReaddir(path)
        }.value

        guard let entries else {
            fsFailed = true
            fsItems = []
            playAudio(.denied)
            return .failed
        }

        fsFailed = false
        fsIsDiskView = false
        fsPath = path
        let mapped = entries.map {
            FilesystemEntry(name: $0.name, category: $0.category, hidden: $0.hidden, size: $0.size)
        }
        fsItems = FilesystemListBuilder.items(entries: mapped, path: path, context: fsContext)
        await refreshFsDiskUsage(forPath: path)
        return .navigated
    }

    /// Recomputes the disk-usage bar for the current directory's mount.
    func refreshFsDiskUsage(forPath path: String) async {
        let client = self.client
        let disks = await Task.detached(priority: .background) {
            client.fsSize()
        }.value
        guard let disks else { fsDiskUsage = nil; return }
        let usages = disks.map { DiskUsage(mount: $0.mount, usePct: $0.usePct) }
        fsDiskUsage = DiskUsageFormatter.select(disks: usages, forPath: path)
    }

    /// Switches the panel to the block-device "Show disks" view, filtering to
    /// devices whose mount point actually exists (legacy fs_exists gate).
    func showFsDisks() async {
        let client = self.client
        let devices = await Task.detached(priority: .background) { () -> [DiskDevice] in
            guard let blocks = client.blockDevices() else { return [] }
            return blocks.compactMap { block in
                guard client.fsExists(block.mount) else { return nil }
                return DiskDevice(
                    name: block.name,
                    deviceType: block.deviceType,
                    mount: block.mount,
                    removable: block.removable,
                    label: block.label
                )
            }
        }.value

        fsFailed = false
        fsIsDiskView = true
        fsDiskUsage = nil
        fsItems = FilesystemListBuilder.diskItems(devices: devices)
    }

    /// Routes a row tap to the right action: navigate, show disks, open special
    /// config items, or hand the file to the host's default app. The in-app text
    /// editor (7.3) and media viewer (10.1) supersede external-open later.
    func activateFsItem(_ item: FilesystemItem) {
        switch item.role {
        case .showDisks:
            Task { await showFsDisks() }
        case .goUp, .directory, .symlink, .themesDir, .keyboardsDir, .disk, .rom, .usb:
            Task { await navigateFS(to: item.path) }
        case .settingsFile:
            openSettingsModal()
        case .shortcutsFile:
            openShortcutsModal()
        case .themeFile:
            applyThemeFile(item.name)
        case .keyboardFile:
            applyKeyboardFile(item.name)
        case .file:
            if FileTypeDetector.isText(name: item.name) {
                openTextFile(path: item.path)
            } else if FileTypeDetector.isPdf(name: item.name) {
                openPdfFile(path: item.path, name: item.name)
            } else if let kind = FileTypeDetector.mediaKind(name: item.name) {
                openMediaFile(path: item.path, name: item.name, kind: kind)
            } else {
                openFsExternal(item.path)
            }
        }
    }

    /// Opens a path in the host's default application.
    func openFsExternal(_ path: String) {
        let client = self.client
        Task {
            let ok = await Task.detached(priority: .background) {
                (try? client.fsOpenExternal(path)) != nil
            }.value
            if !ok { playAudio(.denied) }
        }
    }

    func toggleFsDotfiles() { fsShowDotfiles.toggle() }
    func toggleFsListView() { fsListView.toggle() }

    // MARK: Fuzzy finder (Phase 7.2)

    private var fuzzySearchItems: [FilesystemItem] {
        fsShowDotfiles ? fsItems : fsItems.filter { !$0.hidden }
    }

    func openFuzzyFinder() {
        if let fuzzyFinderModalID, modalManager.modal(id: fuzzyFinderModalID) != nil {
            modalManager.focus(fuzzyFinderModalID)
            return
        }
        if let settingsModalID, modalManager.modal(id: settingsModalID) != nil {
            modalManager.focus(settingsModalID)
            playAudio(.denied)
            return
        }
        guard !fsIsDiskView else {
            statusText = "fuzzy search unavailable — open a directory listing first"
            playAudio(.denied)
            return
        }

        fuzzyQuery = ""
        fuzzyCaret = 0
        fuzzyResults = FuzzyMatcher.search(fuzzySearchItems, query: fuzzyQuery)
        fuzzySelection = 0
        fuzzyStatus = fuzzyResults.isEmpty ? "No results in current directory." : "Searching \(fsPath)"

        let openedID = presentModal(
            type: "custom",
            title: "Fuzzy cwd file search",
            message: "",
            content: .fuzzyFinder,
            detachesKeyboard: true,
            onClose: { [weak self] closedID in
                Task { @MainActor in
                    guard self?.fuzzyFinderModalID == closedID else { return }
                    self?.fuzzyFinderModalID = nil
                    self?.fuzzyQuery = ""
                    self?.fuzzyCaret = 0
                    self?.fuzzyResults = []
                    self?.fuzzySelection = 0
                    self?.fuzzyStatus = ""
                }
            }
        )
        fuzzyFinderModalID = openedID
    }

    func setFuzzyQuery(_ value: String) {
        fuzzyQuery = value
        fuzzyCaret = value.utf16.count
        fuzzyResults = FuzzyMatcher.search(fuzzySearchItems, query: value)
        fuzzySelection = 0
        fuzzyStatus = fuzzyResults.isEmpty ? "No results." : "\(fuzzyResults.count) match\(fuzzyResults.count == 1 ? "" : "es")"
    }

    private func setFuzzyState(_ state: KeyboardDetachedEditor.State) {
        fuzzyQuery = state.text
        fuzzyCaret = state.caret
        fuzzyResults = FuzzyMatcher.search(fuzzySearchItems, query: state.text)
        fuzzySelection = 0
        fuzzyStatus = fuzzyResults.isEmpty ? "No results." : "\(fuzzyResults.count) match\(fuzzyResults.count == 1 ? "" : "es")"
    }

    func setFuzzyCaret(_ value: Int) {
        fuzzyCaret = min(max(0, value), fuzzyQuery.utf16.count)
    }

    func moveFuzzySelection(_ delta: Int) {
        guard !fuzzyResults.isEmpty else {
            fuzzySelection = 0
            return
        }
        if delta > 0 {
            fuzzySelection = FuzzySelection.next(from: fuzzySelection, count: fuzzyResults.count)
        } else if delta < 0 {
            fuzzySelection = FuzzySelection.previous(from: fuzzySelection, count: fuzzyResults.count)
        }
    }

    func submitFuzzySelection() {
        guard fuzzyResults.indices.contains(fuzzySelection) else {
            closeFuzzyFinder()
            return
        }
        let selected = fuzzyResults[fuzzySelection]
        let quotedPath = FuzzyTerminalInput.quotedPath(selected.path)
        handle(.keyboardInput(quotedPath))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(quotedPath, forType: .string)
        statusText = "Copied \(quotedPath) — terminal routing lands in Phase 9"
        closeFuzzyFinder()
    }

    private func closeFuzzyFinder() {
        guard let fuzzyFinderModalID, modalManager.modal(id: fuzzyFinderModalID) != nil else { return }
        closeModal(fuzzyFinderModalID)
    }

    // MARK: Text editor (Phase 7.3)

    /// Reads a text file off the MainActor and opens it in the editor modal
    /// (which detaches the keyboard). A read failure shows an info modal instead,
    /// mirroring the legacy openFile error path.
    func openTextFile(path: String) {
        // Already editing this exact file: just focus the existing modal.
        if let textDocument, textDocument.path == path,
           let textEditorModalID, modalManager.modal(id: textEditorModalID) != nil {
            modalManager.focus(textEditorModalID)
            return
        }
        // Switching to a different file: close the open editor first (its
        // onClose guard checks the modal ID, so it won't clobber the new one).
        if let textEditorModalID, modalManager.modal(id: textEditorModalID) != nil {
            closeModal(textEditorModalID)
        }
        textEditorModalID = nil

        let client = self.client
        Task {
            let (text, errorMessage) = await Task.detached(priority: .userInitiated) { () -> (String?, String?) in
                do { return (try client.fsReadTextFile(path), nil) }
                catch { return (nil, error.localizedDescription) }
            }.value

            guard let text else {
                presentModal(type: "info", title: "Failed to load file", message: errorMessage ?? "Unknown error")
                return
            }

            let document = EdexTextDocument(path: path, text: text)
            textDocument = document
            textEditorCaret = text.utf16.count
            textEditorStatus = document.statusLine
            let openedID = presentModal(
                type: "custom",
                title: document.fileName,
                message: "",
                content: .textEditor,
                detachesKeyboard: true,
                onClose: { [weak self] closedID in
                    Task { @MainActor in
                        guard self?.textEditorModalID == closedID else { return }
                        self?.textEditorModalID = nil
                        self?.textDocument = nil
                        self?.textEditorCaret = 0
                        self?.textEditorStatus = ""
                    }
                }
            )
            textEditorModalID = openedID
        }
    }

    // MARK: Media viewer (Phase 10.1)

    /// Presents the in-app media viewer for image/audio/video files.
    func openMediaFile(path: String, name: String, kind: MediaKind) {
        if mediaViewerPath == path,
           let mediaViewerModalID, modalManager.modal(id: mediaViewerModalID) != nil {
            modalManager.focus(mediaViewerModalID)
            return
        }
        if let mediaViewerModalID, modalManager.modal(id: mediaViewerModalID) != nil {
            closeModal(mediaViewerModalID)
        }
        mediaViewerModalID = nil

        tearDownMediaViewer()
        mediaViewerPath = path
        mediaViewerKind = kind
        mediaViewerExpanded = false
        mediaViewerMuted = false
        mediaViewerVolume = 1
        mediaViewerVolumeBeforeMute = 1

        if kind == .audio || kind == .video {
            mediaViewerPlayer = AVPlayer(url: URL(fileURLWithPath: path))
            mediaViewerPlayer?.volume = 1
        }

        let openedID = presentModal(
            type: "custom",
            title: name,
            message: "",
            content: .mediaViewer,
            detachesKeyboard: true,
            onClose: { [weak self] closedID in
                guard self?.mediaViewerModalID == closedID else { return }
                self?.mediaViewerModalID = nil
                self?.tearDownMediaViewer()
            }
        )
        mediaViewerModalID = openedID
    }

    // MARK: PDF viewer (QoL)

    /// Opens a PDF in the in-app PDFKit modal, mirroring `openMediaFile`'s
    /// focus-or-replace semantics for repeat activations.
    func openPdfFile(path: String, name: String) {
        if pdfViewerPath == path,
           let pdfViewerModalID, modalManager.modal(id: pdfViewerModalID) != nil {
            modalManager.focus(pdfViewerModalID)
            return
        }
        if let pdfViewerModalID, modalManager.modal(id: pdfViewerModalID) != nil {
            closeModal(pdfViewerModalID)
        }
        pdfViewerModalID = nil
        pdfViewerPath = path

        let openedID = presentModal(
            type: "custom",
            title: name,
            message: "",
            content: .pdfViewer,
            detachesKeyboard: true,
            onClose: { [weak self] closedID in
                guard self?.pdfViewerModalID == closedID else { return }
                self?.pdfViewerModalID = nil
                self?.pdfViewerPath = nil
            }
        )
        pdfViewerModalID = openedID
    }

    var mediaViewerIsPlaying: Bool {
        guard let player = mediaViewerPlayer else { return false }
        return player.rate > 0
    }

    func toggleMediaPlayback() {
        guard let player = mediaViewerPlayer else { return }
        if player.rate > 0 {
            player.pause()
        } else {
            player.play()
        }
    }

    func seekMedia(fraction: Double) {
        guard let player = mediaViewerPlayer else { return }
        let duration = mediaViewerDuration
        guard duration > 0 else { return }
        let seconds = MediaPlayerSupport.seekTime(fraction: fraction, duration: duration)
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func setMediaVolume(_ value: Double) {
        guard let player = mediaViewerPlayer else { return }
        let clamped = MediaPlayerSupport.clampVolume(value)
        player.volume = Float(clamped)
        mediaViewerVolume = clamped
        if clamped > 0 {
            mediaViewerVolumeBeforeMute = Float(clamped)
            mediaViewerMuted = false
        } else {
            mediaViewerMuted = true
        }
    }

    func toggleMediaMute() {
        guard let player = mediaViewerPlayer else { return }
        if mediaViewerMuted || player.volume == 0 {
            mediaViewerMuted = false
            let restored = mediaViewerVolumeBeforeMute > 0 ? mediaViewerVolumeBeforeMute : 1
            player.volume = restored
            mediaViewerVolume = Double(restored)
        } else {
            mediaViewerVolumeBeforeMute = player.volume
            mediaViewerMuted = true
            player.volume = 0
        }
    }

    func toggleMediaExpanded() {
        mediaViewerExpanded.toggle()
    }

    var mediaViewerDuration: Double {
        guard let item = mediaViewerPlayer?.currentItem else { return 0 }
        let seconds = item.duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    private func tearDownMediaViewer() {
        mediaViewerPlayer?.pause()
        mediaViewerPlayer = nil
        mediaViewerPath = nil
        mediaViewerKind = nil
        mediaViewerExpanded = false
        mediaViewerMuted = false
        mediaViewerVolume = 1
        mediaViewerVolumeBeforeMute = 1
    }

    /// The editor buffer, bridged to the SwiftUI TextEditor.
    var textEditorText: String { textDocument?.text ?? "" }

    /// Updates the buffer as the user types and refreshes the metrics status line.
    func setTextEditorText(_ value: String) {
        guard textDocument != nil else { return }
        textDocument?.text = value
        textEditorCaret = value.utf16.count
        if let document = textDocument {
            textEditorStatus = document.statusLine
        }
    }

    private func setTextEditorState(_ state: KeyboardDetachedEditor.State) {
        guard textDocument != nil else { return }
        textDocument?.text = state.text
        textEditorCaret = state.caret
        if let document = textDocument {
            textEditorStatus = document.statusLine
        }
    }

    func setTextEditorCaret(_ value: Int) {
        textEditorCaret = min(max(0, value), textEditorText.utf16.count)
    }

    /// Writes the buffer to disk off the MainActor, rebaselines the dirty state,
    /// and reports success/failure in the status line.
    func saveTextFile() {
        guard let document = textDocument else { return }
        let client = self.client
        let path = document.path
        let contents = document.text
        Task {
            let failure = await Task.detached(priority: .background) { () -> String? in
                do { try client.fsWriteTextFile(path, contents: contents); return nil }
                catch { return error.localizedDescription }
            }.value

            // The buffer may have changed while the write was in flight; only
            // rebaseline if this is still the same open document.
            guard textDocument?.path == path else { return }
            if let failure {
                playAudio(.denied)
                textEditorStatus = EdexTextEditorStatus.failed(failure)
            } else {
                playAudio(.granted)
                // Only rebaseline if the buffer hasn't changed since the write;
                // if the user kept typing mid-write, it stays dirty.
                if textDocument?.text == contents {
                    textDocument?.markSaved()
                }
                if let saved = textDocument {
                    textEditorStatus = EdexTextEditorStatus.saved(saved)
                }
            }
        }
    }

    /// Applies a theme JSON file live (preview), mirroring the legacy
    /// `themeChanger`. Does not persist to settings.json.
    private func applyThemeFile(_ fileName: String) {
        let themeName = fileName.hasSuffix(".json") ? String(fileName.dropLast(5)) : fileName
        let client = self.client
        Task {
            do {
                let json = try await Task.detached(priority: .background) {
                    try client.loadThemeJson(themeName)
                }.value
                theme = try NativeTheme(json: json, name: themeName)
                settingsSummary.theme = themeName
                playAudio(.granted)
            } catch {
                playAudio(.denied)
            }
        }
    }

    /// Applies a keyboard layout file tapped in the filesystem panel to the
    /// on-screen keyboard for this session (mirrors `applyThemeFile`; the
    /// persisted `settings.keyboard` is still owned by the settings editor).
    private func applyKeyboardFile(_ fileName: String) {
        let layoutName = fileName.hasSuffix(".json") ? String(fileName.dropLast(5)) : fileName
        let previous = keyboardLayout
        keyboardFileApplyGeneration &+= 1
        let generation = keyboardFileApplyGeneration
        let client = self.client
        Task {
            let result: Result<NativeKeyboardLayout, Error> = await Task.detached(priority: .background) {
                do {
                    return .success(try client.loadKeyboardLayout(layoutName))
                } catch {
                    return .failure(error)
                }
            }.value
            guard generation == keyboardFileApplyGeneration else { return }
            switch result {
            case let .success(layout):
                keyboardLayout = layout
                // Record the layout that actually loaded (the client falls
                // back to en-US for names missing from the keyboards dir).
                settingsSummary.keyboard = layout.name
                keyboardStatus = "Loaded \(layout.name) keyboard layout (\(layout.keyCount) keys)"
                playAudio(.granted)
            case .failure:
                // A malformed file must not leave the on-screen keyboard empty.
                keyboardLayout = previous
                keyboardStatus = "Keyboard layout \(layoutName) failed; kept \(previous?.name ?? "none")"
                playAudio(.denied)
            }
        }
    }

    // MARK: Shortcuts (Phase 6.4)

    /// Loads shortcuts.json from the Rust core and installs the local key-event
    /// monitor. Called once from bootstrap() after userdata is ready.
    func loadShortcuts() async {
        let client = self.client
        let json = await Task.detached(priority: .background) {
            try? client.loadShortcutsJson()
        }.value

        if let json, let doc = try? EdexShortcutsDocument(jsonString: json) {
            shortcuts = doc
        } else {
            shortcuts = nil
            shortcutsStatus = "shortcuts.json could not be parsed; shortcuts are disabled."
        }
        installShortcutMonitor()
    }

    private func installShortcutMonitor() {
        guard shortcutMonitor == nil else { return }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let combo = event.keyCombo
            let consumed = MainActor.assumeIsolated {
                if let combo,
                   let id = self.keyboard.descriptorID(for: combo) {
                    self.keyboard.holdVisual(id: id)
                }
                return self.handleShortcutKeyCombo(combo)
            }
            return consumed ? nil : event
        }
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            let combo = event.keyCombo
            MainActor.assumeIsolated {
                guard let combo,
                      let id = self.keyboard.descriptorID(for: combo)
                else { return }
                self.keyboard.releaseVisual(id: id)
            }
            return event
        }
        modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard let physicalModifier = event.keyboardPhysicalModifier,
                      let id = self.keyboard.descriptorID(for: physicalModifier)
                else { return }
                if event.isActivePhysicalModifier(physicalModifier) {
                    self.keyboard.holdVisual(id: id)
                } else {
                    self.keyboard.releaseVisual(id: id)
                }
            }
            return event
        }
    }

    /// Called by deinit or on explicit teardown. Removes the NSEvent monitor.
    func removeShortcutMonitor() {
        if let m = shortcutMonitor { NSEvent.removeMonitor(m) }
        if let m = keyUpMonitor { NSEvent.removeMonitor(m) }
        if let m = modifierMonitor { NSEvent.removeMonitor(m) }
        shortcutMonitor = nil
        keyUpMonitor = nil
        modifierMonitor = nil
    }

    /// Matches a keyDown combo against loaded shortcuts. Returns true when the
    /// event should be consumed because a shortcut fired.
    private func handleShortcutKeyCombo(_ combo: KeyCombo?) -> Bool {
        guard let doc = shortcuts, let combo else { return false }
        guard let match = doc.match(combo) else { return false }

        switch match {
        case let .app(action, tabIndex):
            dispatchAppShortcut(action, tabIndex: tabIndex)
        case let .shell(action, linebreak):
            handle(.keyboardInput(linebreak ? action + "\r" : action))
        }
        return true
    }

    /// Dispatches a recognised app shortcut action to the appropriate handler.
    func dispatchAppShortcut(_ action: AppShortcutAction, tabIndex: Int?) {
        switch action {
        case .settings:
            handle(.openSettings)
        case .shortcuts:
            openShortcutsModal()
        case .fsListView:
            toggleFsListView()
        case .fsDotfiles:
            toggleFsDotfiles()
        case .fuzzySearch:
            handle(.openFuzzyFinder)
        case .tabTemplate:
            if let tabIndex {
                handle(.switchTerminal(tabIndex))
            }
        case .kbPassmode:
            // Toggle on-screen keyboard password mode (legacy togglePasswordMode):
            // dims the band and silences key audio.
            keyboard.modifiers.passwordMode.toggle()
        case .copy:
            terminal.copySelection()
        case .paste:
            terminal.pasteClipboard()
        case .nextTab:
            terminal.selectNextTab()
            followActiveTabSoon()
        case .previousTab:
            terminal.selectPreviousTab()
            followActiveTabSoon()
        case .devDebug, .devReload:
            break
        }
    }

    func openShortcutsModal() {
        if let shortcutsModalID, modalManager.modal(id: shortcutsModalID) != nil {
            modalManager.focus(shortcutsModalID)
            return
        }
        let openedID = presentModal(
            type: "custom",
            title: "Keyboard Shortcuts",
            message: "",
            content: .shortcuts,
            detachesKeyboard: true,
            onClose: { [weak self] closedID in
                Task { @MainActor in
                    guard self?.shortcutsModalID == closedID else { return }
                    self?.shortcutsModalID = nil
                }
            }
        )
        shortcutsModalID = openedID
    }

    func openShortcutsFileExternally() {
        guard let path = paths?.shortcutsFile else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @discardableResult
    func playAudio(_ cue: EdexAudioCue) -> Bool {
        audio.play(cue)
    }

    @discardableResult
    func presentModal(
        type: String,
        title: String?,
        message: String?,
        content: EdexModalContent = .message,
        detachesKeyboard: Bool? = nil,
        onClose: ((EdexModalID) -> Void)? = nil
    ) -> EdexModalID? {
        do {
            let request = try EdexModalRequest(
                type: type,
                title: title,
                message: message,
                content: content,
                detachesKeyboard: detachesKeyboard
            )
            playAudio(request.openCue)
            return modalManager.present(request, onClose: onClose)
        } catch {
            statusText = "modal error — \(error.localizedDescription)"
            return nil
        }
    }

    func closeModal(_ id: EdexModalID) {
        if let cue = modalManager.close(id) {
            playAudio(cue)
        }
    }

    private func terminateIfSmokeWindow() {
        guard CommandLine.arguments.contains("--smoke-window") else { return }
        DispatchQueue.main.async {
            print("eDEXNative window smoke: bootstrap complete; terminating")
            NSApp.terminate(nil)
            Darwin.exit(0)
        }
    }
}

/// Outcome of a `navigateFS(to:)` call, so the cwd-follow can tell a resolved
/// navigation (shown or hard-failed) apart from one skipped because another read
/// held `fsReading` — only the latter should be retried on the next poll.
enum FilesystemNavigationOutcome {
    case navigated
    case failed
    case skipped
}

struct SettingsSummary: Sendable {
    var theme = "pending"
    var keyboard = "en-US"
    var keepGeometry = true
    var clockHours = 24
    var excludeThreadsFromToplist = true
    var nointro = false
    var hideDotfiles = false
    var fsListView = false
    var reducedMotion = false
    var audioSettings = EdexAudioSettings()
    var byteCount: Int?
}

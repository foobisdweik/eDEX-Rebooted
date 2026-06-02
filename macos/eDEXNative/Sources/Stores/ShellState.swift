import AppKit
import AudioSupport
import CpuinfoSupport
import Darwin
import Foundation
import HardwareSupport
import ModalSupport
import Observation
import RamwatcherSupport
import SettingsEditorSupport
import ShortcutsSupport
import SwiftUI
import SysinfoSupport
import ThemeSupport
import ToplistSupport

@Observable
@MainActor
final class ShellState {
    private let client = EdexCoreClient()
    private let audio = EdexAudioService()

    let modalManager = EdexModalManager()
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

    // Phase 6.4 shortcuts state.
    var shortcuts: EdexShortcutsDocument?
    var shortcutsStatus = ""
    @ObservationIgnored private var shortcutsModalID: EdexModalID?
    @ObservationIgnored private var shortcutMonitor: Any?

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

    /// Bridges the FFI battery record into the FFI-free `SysinfoSupport` input.
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

    func bootstrap() async {
        do {
            let snapshot = try client.bootstrap()
            paths = snapshot.paths
            settingsSummary = snapshot.settings
            keepGeometry = snapshot.settings.keepGeometry
            theme = snapshot.theme
            audio.configure(settings: snapshot.settings.audioSettings)
            statusText = "ok — EdexCore.paths(), ensureUserdata(), loadSettingsJson(), loadThemeJson() returned"
            print("eDEXNative FFI OK userData=\(snapshot.paths.userData) settingsBytes=\(snapshot.settings.byteCount ?? 0) theme=\(snapshot.settings.theme) keepGeometry=\(snapshot.settings.keepGeometry)")
            await loadShortcuts()
            terminateIfSmokeWindow()
        } catch {
            statusText = "error — \(error.localizedDescription)"
            presentModal(type: "error", title: "Native bootstrap failed", message: error.localizedDescription)
            print("eDEXNative FFI ERROR \(error.localizedDescription)")
            terminateIfSmokeWindow()
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
        self.battery = battery
    }

    /// Pulls host hardware identity from the Rust core for the hardware-inspector
    /// panel. Offloaded off the MainActor like `refreshSysinfo()`. The data is
    /// effectively static at runtime; the panel re-polls on the legacy 20s cadence.
    func refreshHardware() async {
        let client = self.client
        hardware = await Task.detached(priority: .background) {
            client.hardware()
        }.value
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

        topProcesses = snapshot.topProcesses
        if includeProcessList {
            processRows = snapshot.processList?.list ?? []
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
            return MainActor.assumeIsolated { self.handleShortcutKeyEvent(event) }
        }
    }

    /// Called by deinit or on explicit teardown. Removes the NSEvent monitor.
    func removeShortcutMonitor() {
        if let m = shortcutMonitor { NSEvent.removeMonitor(m) }
        shortcutMonitor = nil
    }

    /// Matches a keyDown event against loaded shortcuts. Returns nil to consume
    /// the event (shortcut fired), or the event itself to pass it through.
    private func handleShortcutKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard let doc = shortcuts, let eventCombo = event.keyCombo else { return event }

        // Regular (non-TAB_X) app + shell shortcuts
        for entry in doc.enabledEntries() {
            guard entry.action != AppShortcutAction.tabTemplate.rawValue else { continue }
            guard let combo = entry.combo, combo == eventCombo else { continue }
            switch entry.type {
            case .app:
                if let action = AppShortcutAction(rawValue: entry.action) {
                    dispatchAppShortcut(action, tabIndex: nil)
                }
            case .shell:
                // Shell shortcuts write a command to the active terminal.
                // Terminal tab management is Phase 9; these are parsed and
                // stored now but execution is deferred until the PTY seam exists.
                break
            }
            return nil
        }

        // TAB_X expansion: Ctrl+1 … Ctrl+5
        for (combo, tabIndex) in doc.expandedTabCombos() {
            guard combo == eventCombo else { continue }
            dispatchAppShortcut(.tabTemplate, tabIndex: tabIndex)
            return nil
        }

        return event
    }

    /// Dispatches a recognised app shortcut action to the appropriate handler.
    func dispatchAppShortcut(_ action: AppShortcutAction, tabIndex: Int?) {
        switch action {
        case .settings:
            openSettingsModal()
        case .shortcuts:
            openShortcutsModal()
        case .copy, .paste, .nextTab, .previousTab, .tabTemplate,
             .fuzzySearch, .fsListView, .fsDotfiles, .kbPassmode,
             .devDebug, .devReload:
            // These actions are dispatched by this handler but their targets
            // (terminal, filesystem, keyboard) are built in later phases.
            // Stubs prevent crashes when shortcuts fire before the feature exists.
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

struct SettingsSummary: Sendable {
    var theme = "pending"
    var keepGeometry = true
    var clockHours = 24
    var excludeThreadsFromToplist = true
    var audioSettings = EdexAudioSettings()
    var byteCount: Int?
}

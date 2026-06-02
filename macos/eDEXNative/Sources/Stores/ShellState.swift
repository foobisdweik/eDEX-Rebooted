import AppKit
import AudioSupport
import BootSupport
import CpuinfoSupport
import Darwin
import FilesystemSupport
import FuzzyFinderSupport
import Foundation
import HardwareSupport
import KeyboardSupport
import ModalSupport
import Observation
import RamwatcherSupport
import SettingsEditorSupport
import ShortcutsSupport
import SwiftUI
import SysinfoSupport
import TextEditorSupport
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

    // Phase 6.5 boot screen state.
    /// Which stage of the boot sequence is active.
    var bootStage: EdexBootStage = .logScroll
    /// Lines accumulated so far during the log-scroll stage.
    var bootDisplayLines: [String] = []

    // Phase 7.1 filesystem panel state.
    /// Current directory being displayed. Starts at the user's home; tab-CWD
    /// tracking is deferred to Phase 9 (PTY seam).
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

    // Phase 7.2 fuzzy finder state.
    var fuzzyQuery = ""
    var fuzzyResults: [FilesystemItem] = []
    var fuzzySelection = 0
    var fuzzyStatus = ""
    @ObservationIgnored var pendingTerminalInput: String?
    @ObservationIgnored private var fuzzyFinderModalID: EdexModalID?

    // Phase 7.3 text editor state.
    /// The document open in the editor modal, or nil when closed.
    var textDocument: EdexTextDocument?
    /// Status line under the editor (metrics, save success/failure).
    var textEditorStatus = ""
    @ObservationIgnored private var textEditorModalID: EdexModalID?

    // Phase 8.1 keyboard layout state.
    var keyboardLayout: NativeKeyboardLayout?
    var keyboardStatus = "keyboard layout not loaded"

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
            fsShowDotfiles = !snapshot.settings.hideDotfiles
            fsListView = snapshot.settings.fsListView
            theme = snapshot.theme
            await loadKeyboardLayout(named: snapshot.settings.keyboard)
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
        settingsSummary.nointro = document.bool(.nointro) ?? false
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

    // MARK: Filesystem panel (Phase 7.1)

    /// eDEX userdata paths that drive the special theme/keyboard/settings tagging.
    private var fsContext: FilesystemContext {
        FilesystemContext(
            userDataDir: paths?.userData,
            themesDir: paths?.themesDir,
            keyboardsDir: paths?.keyboardsDir
        )
    }

    /// First load when the panel appears. Re-entrant-safe; no-op once populated.
    func loadInitialFilesystemIfNeeded() async {
        guard fsItems.isEmpty, !fsFailed, !fsReading else { return }
        await navigateFS(to: fsPath)
    }

    /// Reads a directory and rebuilds the displayed rows. The FFI listing runs
    /// off the MainActor; results land back here. A read failure sets the failed
    /// state and plays the denied cue (mirrors the legacy setFailedState path).
    func navigateFS(to path: String) async {
        guard !fsReading else { return }
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
            return
        }

        fsFailed = false
        fsIsDiskView = false
        fsPath = path
        let mapped = entries.map {
            FilesystemEntry(name: $0.name, category: $0.category, hidden: $0.hidden, size: $0.size)
        }
        fsItems = FilesystemListBuilder.items(entries: mapped, path: path, context: fsContext)
        await refreshFsDiskUsage(forPath: path)
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
            // Keyboard layout swapping is Phase 8; open in the host app for now.
            openFsExternal(item.path)
        case .file:
            if FileTypeDetector.isText(name: item.name) {
                openTextFile(path: item.path)
            } else if FileTypeDetector.isPdf(name: item.name) {
                // DocReader/pdfjs is deferred to v0.2, mirroring the legacy panel.
                presentModal(
                    type: "info",
                    title: item.name,
                    message: "PDF preview is deferred to v0.2 of the native port."
                )
            } else {
                // Media (image/audio/video) gets its viewer in Phase 10.1; until
                // then, non-text files open in the host's default application.
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
        fuzzyResults = FuzzyMatcher.search(fuzzySearchItems, query: value)
        fuzzySelection = 0
        fuzzyStatus = fuzzyResults.isEmpty ? "No results." : "\(fuzzyResults.count) match\(fuzzyResults.count == 1 ? "" : "es")"
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
        pendingTerminalInput = quotedPath
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
                        self?.textEditorStatus = ""
                    }
                }
            )
            textEditorModalID = openedID
        }
    }

    /// The editor buffer, bridged to the SwiftUI TextEditor.
    var textEditorText: String { textDocument?.text ?? "" }

    /// Updates the buffer as the user types and refreshes the metrics status line.
    func setTextEditorText(_ value: String) {
        guard textDocument != nil else { return }
        textDocument?.text = value
        if let document = textDocument {
            textEditorStatus = document.statusLine
        }
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
        case .fsListView:
            toggleFsListView()
        case .fsDotfiles:
            toggleFsDotfiles()
        case .fuzzySearch:
            openFuzzyFinder()
        case .copy, .paste, .nextTab, .previousTab, .tabTemplate,
             .kbPassmode, .devDebug, .devReload:
            // These actions are dispatched by this handler but their targets
            // (terminal, keyboard) are built in later phases. Stubs prevent
            // crashes when shortcuts fire before the feature exists.
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
    var keyboard = "en-US"
    var keepGeometry = true
    var clockHours = 24
    var excludeThreadsFromToplist = true
    var nointro = false
    var hideDotfiles = false
    var fsListView = false
    var audioSettings = EdexAudioSettings()
    var byteCount: Int?
}

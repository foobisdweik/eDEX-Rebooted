import Foundation
import EdexCoreBridge
import EdexDomainSupport
import EdexRenderingSupport

struct BootstrapSnapshot: Sendable {
    var paths: FfiPaths
    var settings: SettingsSummary
    var theme: NativeTheme
}

struct EdexCoreClient {
    private let core: EdexCore

    init(core: EdexCore = EdexCore()) {
        self.core = core
    }

    func bootstrap() throws -> BootstrapSnapshot {
        try core.ensureUserdata()

        let paths = core.paths()
        let settingsJson = try core.loadSettingsJson()
        let settingsData = Data(settingsJson.utf8)
        let decodedSettings = try JSONDecoder().decode(SettingsFile.self, from: settingsData)
        let themeName = decodedSettings.theme ?? "tron"
        let keyboardName = decodedSettings.keyboard ?? "en-US"

        var summary = SettingsSummary(
            theme: themeName,
            keyboard: keyboardName,
            keepGeometry: decodedSettings.keepGeometry ?? true,
            clockHours: decodedSettings.clockHours ?? 24,
            excludeThreadsFromToplist: decodedSettings.excludeThreadsFromToplist ?? true,
            nointro: decodedSettings.nointro ?? false,
            hideDotfiles: decodedSettings.hideDotfiles ?? false,
            fsListView: decodedSettings.fsListView ?? false,
            audioSettings: (try? JSONDecoder().decode(EdexAudioSettings.self, from: settingsData)) ?? EdexAudioSettings(),
            byteCount: settingsData.count
        )

        let theme: NativeTheme
        do {
            let themeJson = try core.loadThemeJson(name: themeName)
            theme = try NativeTheme(json: themeJson, name: themeName)
        } catch {
            summary.theme = "\(themeName) (theme load failed; using fallback)"
            theme = .fallback
        }

        return BootstrapSnapshot(paths: paths, settings: summary, theme: theme)
    }

    /// System uptime in seconds (sysinfo panel UPTIME cell).
    func uptimeSeconds() -> UInt64 {
        core.uptime()
    }

    /// Battery/power state, or nil if the query fails (sysinfo panel POWER cell).
    func battery() -> FfiBattery? {
        try? core.battery()
    }

    /// Host hardware identity (hardware-inspector panel).
    func hardware() -> FfiHardware {
        core.hardware()
    }

    /// Live CPU snapshot, or nil if the query fails (cpuinfo panel).
    func cpuSnapshot() -> FfiCpuSnapshot? {
        try? core.cpuSnapshot()
    }

    /// Memory snapshot, or nil if the query fails (ramwatcher panel).
    func memSnapshot() -> FfiMemSnapshot? {
        try? core.memSnapshot()
    }

    /// TOPLIST panel snapshot. `includeProcessList` is true only while the
    /// expanded process modal is open; the compact panel needs top rows only.
    func toplistSnapshot(collapseThreadsByName: Bool, includeProcessList: Bool) -> FfiToplistSnapshot? {
        try? core.toplistSnapshot(
            collapseThreadsByName: collapseThreadsByName,
            includeProcessList: includeProcessList
        )
    }

    /// Raw settings.json text (settings editor load).
    func loadSettingsJson() throws -> String {
        try core.loadSettingsJson()
    }

    /// Persist the full settings document (settings editor save). Throws on
    /// malformed JSON or a failed write.
    func writeSettings(_ json: String) throws {
        try core.writeSettingsJson(contents: json)
    }

    /// Raw theme JSON by name (settings editor live theme re-apply).
    func loadThemeJson(_ name: String) throws -> String {
        try core.loadThemeJson(name: name)
    }

    /// Available theme names (settings editor theme picker).
    func listThemes() -> [String] {
        core.listThemes()
    }

    /// Available keyboard layout codes (settings editor keyboard picker).
    func listKeyboards() -> [String] {
        core.listKeyboards()
    }

    /// Typed keyboard layout by name (Phase 8.1 native keyboard data loader).
    func loadKeyboardLayout(_ name: String) throws -> NativeKeyboardLayout {
        let available = core.listKeyboards()
        let selected = available.contains(name) ? name : "en-US"
        return try NativeKeyboardLayout(json: core.loadKeyboardJson(name: selected), name: selected)
    }

    /// Raw shortcuts.json text (shortcuts load / display modal).
    func loadShortcutsJson() throws -> String {
        try core.loadShortcutsJson()
    }

    /// Persist shortcuts.json. Rejects non-array or malformed JSON before writing.
    func writeShortcutsJson(_ json: String) throws {
        try core.writeShortcutsJson(contents: json)
    }

    // MARK: - Filesystem panel (Phase 7.1)

    /// Directory listing for the filesystem panel. Throws on missing dir /
    /// permission errors so the panel can show its failed state.
    func fsReaddir(_ path: String) throws -> [FfiDirEntry] {
        try core.fsReaddir(path: path)
    }

    /// Whether a path exists (filters unmounted "Show disks" rows).
    func fsExists(_ path: String) -> Bool {
        core.fsExists(path: path)
    }

    /// Open a path in the host's default application.
    func fsOpenExternal(_ path: String) throws {
        try core.fsOpenExternal(path: path)
    }

    /// Mounted-filesystem space accounting (disk-usage bar). nil if the query fails.
    func fsSize() -> [FfiDiskUsage]? {
        try? core.fsSize()
    }

    /// Block devices for the "Show disks" view. nil if the query fails.
    func blockDevices() -> [FfiBlockDevice]? {
        try? core.blockDevices()
    }

    /// Read a text file for the editor modal (Phase 7.3). Throws on a missing
    /// file, permission error, or non-UTF-8 content.
    func fsReadTextFile(_ path: String) throws -> String {
        try core.fsReadTextFile(path: path)
    }

    /// Write the editor buffer back to disk (Phase 7.3). Throws on a failed write.
    func fsWriteTextFile(_ path: String, contents: String) throws {
        try core.fsWriteTextFile(path: path, contents: contents)
    }
}

private struct SettingsFile: Decodable {
    var theme: String?
    var keyboard: String?
    var keepGeometry: Bool?
    var clockHours: Int?
    var excludeThreadsFromToplist: Bool?
    var nointro: Bool?
    var hideDotfiles: Bool?
    var fsListView: Bool?
}

import Foundation
import ThemeSupport

struct BootstrapSnapshot: Sendable {
    var paths: FfiPaths
    var settings: SettingsSummary
    var theme: NativeTheme
}

struct EdexCoreClient {
    private let core = EdexCore()

    func bootstrap() throws -> BootstrapSnapshot {
        try core.ensureUserdata()

        let paths = core.paths()
        let settingsJson = try core.loadSettingsJson()
        let settingsData = Data(settingsJson.utf8)
        let decodedSettings = try JSONDecoder().decode(SettingsFile.self, from: settingsData)
        let themeName = decodedSettings.theme ?? "tron"

        var summary = SettingsSummary(
            theme: themeName,
            keepGeometry: decodedSettings.keepGeometry ?? true,
            clockHours: decodedSettings.clockHours ?? 24,
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
}

private struct SettingsFile: Decodable {
    var theme: String?
    var keepGeometry: Bool?
    var clockHours: Int?
}

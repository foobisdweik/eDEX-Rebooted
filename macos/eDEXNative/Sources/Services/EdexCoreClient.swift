import Foundation
import SwiftUI

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
}

private struct ThemeFile: Decodable {
    struct Colors: Decodable {
        var r: Double?
        var g: Double?
        var b: Double?
        var lightBlack: String?
        var black: String?

        enum CodingKeys: String, CodingKey {
            case r, g, b, black
            case lightBlack = "light_black"
        }
    }

    var colors: Colors?
}

extension NativeTheme {
    init(json: String, name: String) throws {
        let decoded = try JSONDecoder().decode(ThemeFile.self, from: Data(json.utf8))
        let colors = decoded.colors
        let accent = Color(
            red: (colors?.r ?? 170.0) / 255.0,
            green: (colors?.g ?? 207.0) / 255.0,
            blue: (colors?.b ?? 209.0) / 255.0
        )
        self.init(
            accent: accent,
            background: Color(hex: colors?.lightBlack ?? colors?.black ?? "#05080d") ?? NativeTheme.fallback.background,
            source: "\(name).json via UniFFI"
        )
    }
}

private extension Color {
    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6, let value = UInt64(trimmed, radix: 16) else {
            return nil
        }
        self.init(
            red: Double((value >> 16) & 0xff) / 255.0,
            green: Double((value >> 8) & 0xff) / 255.0,
            blue: Double(value & 0xff) / 255.0
        )
    }
}

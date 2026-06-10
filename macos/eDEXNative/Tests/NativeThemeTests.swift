import XCTest
@testable import EdexDomainSupport
@testable import EdexRenderingSupport

final class NativeThemeTests: XCTestCase {
    func testThemeRejectsNonDictionaryJsonRoot() throws {
        XCTAssertThrowsError(try NativeTheme(json: "[]", name: "array-root")) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                XCTFail("Expected DecodingError.dataCorrupted, got \(error)")
                return
            }
            XCTAssertEqual(context.debugDescription, "Theme JSON root is not a dictionary")
        }
    }

    func testNativeColorClampsComponents() {
        let color = NativeColor(red: -0.5, green: 1.5, blue: 0.25, alpha: 2)

        XCTAssertEqual(color.red, 0)
        XCTAssertEqual(color.green, 1)
        XCTAssertEqual(color.blue, 0.25)
        XCTAssertEqual(color.alpha, 1)
        XCTAssertEqual(color.hexRGB, "#00FF40")
    }

    func testBundledThemesDecodeIntoNativeThemeModel() throws {
        let themesDirectory = EdexBundledAssets.themesDirectory(from: #filePath)
        let themeFiles = try FileManager.default.contentsOfDirectory(
            at: themesDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        XCTAssertGreaterThan(themeFiles.count, 0)
        for file in themeFiles {
            let json = try String(contentsOf: file, encoding: .utf8)
            let name = file.deletingPathExtension().lastPathComponent
            let theme = try NativeTheme(json: json, name: name)
            XCTAssertFalse(theme.name.isEmpty)
            XCTAssertFalse(theme.fonts.main.isEmpty)
            XCTAssertFalse(theme.fonts.terminal.isEmpty)
            XCTAssertFalse(theme.palette.background.hexRGB.isEmpty)
        }
    }

    func testThemeDecodesCorePaletteAndFonts() throws {
        let json = """
        {
          "colors": {
            "r": 170,
            "g": 207,
            "b": 209,
            "black": "#000000",
            "light_black": "#05080d",
            "grey": "#262828"
          },
          "cssvars": {
            "font_main": "United Sans Medium",
            "font_main_light": "United Sans Light"
          },
          "terminal": {
            "fontFamily": "Fira Mono",
            "foreground": "#aacfd1",
            "background": "#05080d",
            "selection": "rgba(170,207,209,0.3)"
          }
        }
        """

        let theme = try NativeTheme(json: json, name: "tron")

        XCTAssertEqual(theme.name, "tron")
        XCTAssertEqual(theme.source, "tron.json via UniFFI")
        XCTAssertEqual(theme.fonts.main, "United Sans Medium")
        XCTAssertEqual(theme.fonts.mainLight, "United Sans Light")
        XCTAssertEqual(theme.fonts.terminal, "Fira Mono")
        XCTAssertEqual(theme.palette.accent.hexRGB, "#AACFD1")
        XCTAssertEqual(theme.palette.background.hexRGB, "#05080D")
        XCTAssertEqual(theme.palette.panelBackground.hexRGB, "#05080D")
        XCTAssertEqual(theme.palette.terminalForeground.hexRGB, "#AACFD1")
        XCTAssertEqual(theme.palette.terminalSelection.alpha, 0.3)
    }

    func testThemeDecodesCamelCaseLightBlackAndNamedSwatches() throws {
        let json = """
        {
          "colors": {
            "r": 216,
            "g": 222,
            "b": 233,
            "black": "#2E3440",
            "lightBlack": "#4C566A",
            "blue": "#81A1C1",
            "cyan": "#88C0D0"
          },
          "cssvars": {
            "font_main": "United Sans Medium"
          },
          "terminal": {
            "fontFamily": "Fira Mono",
            "foreground": "#D8DEE9",
            "background": "#2E3440"
          }
        }
        """

        let theme = try NativeTheme(json: json, name: "nord")

        XCTAssertEqual(theme.palette.panelBackground.hexRGB, "#4C566A")
        XCTAssertEqual(theme.palette.swatches["blue"]?.hexRGB, "#81A1C1")
        XCTAssertEqual(theme.palette.swatches["cyan"]?.hexRGB, "#88C0D0")
        XCTAssertEqual(theme.fonts.mainLight, "United Sans Medium")
    }

    func testLegacyLightBlackPrefersSwatchesThenPanelBackground() throws {
        // The legacy renderer read `theme.colors.light_black` for secondary
        // fills (e.g. the two-tone fsDisp folder glyphs); themes spell it
        // `lightBlack`, `light_black`, or only ship `black`.
        let withSwatch = try NativeTheme(json: """
        {
          "colors": { "r": 216, "g": 222, "b": 233, "lightBlack": "#4C566A", "black": "#2E3440" },
          "terminal": { "foreground": "#D8DEE9", "background": "#2E3440" }
        }
        """, name: "nord")
        XCTAssertEqual(withSwatch.legacyLightBlack.hexRGB, "#4C566A")

        let blackOnly = try NativeTheme(json: """
        {
          "colors": { "r": 216, "g": 222, "b": 233, "black": "#2E3440" },
          "terminal": { "foreground": "#D8DEE9", "background": "#2E3440" }
        }
        """, name: "mono")
        XCTAssertEqual(blackOnly.legacyLightBlack.hexRGB, "#2E3440")

        let bare = try NativeTheme(json: """
        {
          "colors": { "r": 170, "g": 207, "b": 209 },
          "terminal": { "foreground": "#AACFD1", "background": "#05080D" }
        }
        """, name: "bare")
        XCTAssertEqual(bare.legacyLightBlack.hexRGB, bare.palette.panelBackground.hexRGB)
    }
}

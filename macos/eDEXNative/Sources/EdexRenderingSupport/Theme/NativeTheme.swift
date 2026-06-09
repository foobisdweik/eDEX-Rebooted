import Foundation
import SwiftUI

public struct NativeTheme: Sendable {
    public var name: String
    public var source: String
    public var palette: NativeThemePalette
    public var fonts: NativeThemeFonts

    public var accent: Color { palette.accent.color }
    public var background: Color { palette.background.color }
    public var panelBackground: Color { palette.panelBackground.color }
    public var terminalBackground: Color { palette.terminalBackground.color }
    public var terminalForeground: Color { palette.terminalForeground.color }

    public static let fallback = NativeTheme(
        name: "fallback",
        source: "fallback tron palette",
        palette: NativeThemePalette(
            accent: NativeColor(red: 170.0 / 255.0, green: 207.0 / 255.0, blue: 209.0 / 255.0),
            background: NativeColor(red: 5.0 / 255.0, green: 8.0 / 255.0, blue: 13.0 / 255.0),
            panelBackground: NativeColor(red: 5.0 / 255.0, green: 8.0 / 255.0, blue: 13.0 / 255.0),
            terminalForeground: NativeColor(red: 170.0 / 255.0, green: 207.0 / 255.0, blue: 209.0 / 255.0),
            terminalBackground: NativeColor(red: 5.0 / 255.0, green: 8.0 / 255.0, blue: 13.0 / 255.0),
            terminalSelection: NativeColor(red: 170.0 / 255.0, green: 207.0 / 255.0, blue: 209.0 / 255.0, alpha: 0.3),
            swatches: [:]
        ),
        fonts: NativeThemeFonts(
            main: "United Sans Medium",
            mainLight: "United Sans Light",
            terminal: "Fira Mono"
        )
    )
}

public struct NativeThemePalette: Sendable {
    public var accent: NativeColor
    public var background: NativeColor
    public var panelBackground: NativeColor
    public var terminalForeground: NativeColor
    public var terminalBackground: NativeColor
    public var terminalSelection: NativeColor
    public var swatches: [String: NativeColor]

    public init(
        accent: NativeColor,
        background: NativeColor,
        panelBackground: NativeColor,
        terminalForeground: NativeColor,
        terminalBackground: NativeColor,
        terminalSelection: NativeColor,
        swatches: [String: NativeColor]
    ) {
        self.accent = accent
        self.background = background
        self.panelBackground = panelBackground
        self.terminalForeground = terminalForeground
        self.terminalBackground = terminalBackground
        self.terminalSelection = terminalSelection
        self.swatches = swatches
    }
}

public struct NativeThemeFonts: Sendable {
    public var main: String
    public var mainLight: String
    public var terminal: String

    public init(main: String, mainLight: String, terminal: String) {
        self.main = main
        self.mainLight = mainLight
        self.terminal = terminal
    }
}

public struct NativeColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double = 1

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red.clamped01
        self.green = green.clamped01
        self.blue = blue.clamped01
        self.alpha = alpha.clamped01
    }

    public var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    public var hexRGB: String {
        let r = Int((red * 255).rounded()).clampedByte
        let g = Int((green * 255).rounded()).clampedByte
        let b = Int((blue * 255).rounded()).clampedByte
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension NativeTheme {
    public init(json: String, name: String) throws {
        guard let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Theme JSON root is not a dictionary"))
        }
        let colors = root["colors"] as? [String: Any] ?? [:]
        let cssvars = root["cssvars"] as? [String: Any] ?? [:]
        let terminal = root["terminal"] as? [String: Any] ?? [:]
        let fallback = NativeTheme.fallback

        let swatches = NativeTheme.decodeSwatches(colors)
        let accent = NativeTheme.rgbAccent(colors)
            ?? NativeColor(css: terminal["foreground"] as? String)
            ?? fallback.palette.accent
        let terminalBackground = NativeColor(css: terminal["background"] as? String)
            ?? NativeTheme.firstColor(colors, keys: ["lightBlack", "light_black", "black"])
            ?? fallback.palette.terminalBackground
        let panelBackground = NativeTheme.firstColor(colors, keys: ["lightBlack", "light_black", "black"])
            ?? terminalBackground
        let terminalForeground = NativeColor(css: terminal["foreground"] as? String) ?? accent
        let terminalSelection = NativeColor(css: terminal["selection"] as? String)
            ?? NativeColor(red: accent.red, green: accent.green, blue: accent.blue, alpha: 0.3)

        self.init(
            name: name,
            source: "\(name).json via UniFFI",
            palette: NativeThemePalette(
                accent: accent,
                background: terminalBackground,
                panelBackground: panelBackground,
                terminalForeground: terminalForeground,
                terminalBackground: terminalBackground,
                terminalSelection: terminalSelection,
                swatches: swatches
            ),
            fonts: NativeThemeFonts(
                main: cssvars["font_main"] as? String ?? fallback.fonts.main,
                mainLight: cssvars["font_main_light"] as? String ?? cssvars["font_main"] as? String ?? fallback.fonts.mainLight,
                terminal: terminal["fontFamily"] as? String ?? fallback.fonts.terminal
            )
        )
    }

    private static func decodeSwatches(_ colors: [String: Any]) -> [String: NativeColor] {
        var swatches = [String: NativeColor]()
        for (key, value) in colors {
            guard let css = value as? String, let color = NativeColor(css: css) else {
                continue
            }
            swatches[key] = color
        }
        return swatches
    }

    private static func rgbAccent(_ colors: [String: Any]) -> NativeColor? {
        guard
            let r = number(colors["r"]),
            let g = number(colors["g"]),
            let b = number(colors["b"])
        else {
            return nil
        }
        return NativeColor(red: r / 255.0, green: g / 255.0, blue: b / 255.0)
    }

    private static func firstColor(_ colors: [String: Any], keys: [String]) -> NativeColor? {
        for key in keys {
            if let color = NativeColor(css: colors[key] as? String) {
                return color
            }
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        return nil
    }
}

extension NativeColor {
    init?(css: String?) {
        guard let css else { return nil }
        let trimmed = css.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            self.init(hex: trimmed)
            return
        }
        if trimmed.lowercased().hasPrefix("rgba(") || trimmed.lowercased().hasPrefix("rgb(") {
            self.init(rgbFunction: trimmed)
            return
        }
        return nil
    }

    private init?(hex: String) {
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

    private init?(rgbFunction: String) {
        guard
            let start = rgbFunction.firstIndex(of: "("),
            let end = rgbFunction.lastIndex(of: ")"),
            start < end
        else {
            return nil
        }
        let values = rgbFunction[rgbFunction.index(after: start)..<end]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard values.count == 3 || values.count == 4 else {
            return nil
        }
        guard
            let r = Double(values[0]),
            let g = Double(values[1]),
            let b = Double(values[2])
        else {
            return nil
        }
        let alpha = values.count == 4 ? Double(values[3]) ?? 1 : 1
        self.init(red: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: alpha)
    }
}

private extension Int {
    var clampedByte: Int {
        Swift.min(255, Swift.max(0, self))
    }
}

private extension Double {
    var clamped01: Double {
        Swift.min(1.0, Swift.max(0.0, self))
    }
}

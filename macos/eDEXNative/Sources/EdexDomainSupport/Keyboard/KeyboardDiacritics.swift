import Foundation

/// A dead key armed by an `ESCAPED|-- <NAME>` keyboard command. The next
/// printable keystroke is composed against the matching table.
///
/// Ported verbatim from the legacy `keyboard.class.js` `addX`/`toGreek`
/// composition tables. Pure data; FFI-free.
public enum DeadKey: String, CaseIterable, Sendable {
    case circumflex
    case trema
    case acute
    case grave
    case caron
    case bar
    case breve
    case tilde
    case macron
    case cedilla
    case overring
    case greek
    case iotaSubscript

    /// Maps an `ESCAPED|-- <NAME>` body (after the `ESCAPED|-- ` prefix) to a
    /// dead key. Returns nil for non-dead-key escaped commands.
    public init?(escapedName: String) {
        switch escapedName {
        case "CIRCUM": self = .circumflex
        case "TREMA": self = .trema
        case "ACUTE": self = .acute
        case "GRAVE": self = .grave
        case "CARON": self = .caron
        case "BAR": self = .bar
        case "BREVE": self = .breve
        case "TILDE": self = .tilde
        case "MACRON": self = .macron
        case "CEDILLA": self = .cedilla
        case "OVERRING": self = .overring
        case "GREEK": self = .greek
        case "IOTASUB": self = .iotaSubscript
        default: return nil
        }
    }
}

public enum KeyboardDiacritics {
    /// Compose `base` under `deadKey`. Returns `base` unchanged when the table
    /// has no entry (legacy `default: return char`).
    public static func compose(_ deadKey: DeadKey, _ base: String) -> String {
        table(for: deadKey)[base] ?? base
    }

    private static func table(for deadKey: DeadKey) -> [String: String] {
        switch deadKey {
        case .circumflex: return circumflex
        case .trema: return trema
        case .acute: return acute
        case .grave: return grave
        case .caron: return caron
        case .bar: return bar
        case .breve: return breve
        case .tilde: return tilde
        case .macron: return macron
        case .cedilla: return cedilla
        case .overring: return overring
        case .greek: return greek
        case .iotaSubscript: return iotaSubscript
        }
    }

    // The circumflex also produces superscript numbers (legacy comment).
    private static let circumflex: [String: String] = [
        "a": "â", "A": "Â", "z": "ẑ", "Z": "Ẑ", "e": "ê", "E": "Ê",
        "y": "ŷ", "Y": "Ŷ", "u": "û", "U": "Û", "i": "î", "I": "Î",
        "o": "ô", "O": "Ô", "s": "ŝ", "S": "Ŝ", "g": "ĝ", "G": "Ĝ",
        "h": "ĥ", "H": "Ĥ", "j": "ĵ", "J": "Ĵ", "w": "ŵ", "W": "Ŵ",
        "c": "ĉ", "C": "Ĉ",
        "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵",
        "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "0": "⁰",
    ]

    private static let trema: [String: String] = [
        "a": "ä", "A": "Ä", "e": "ë", "E": "Ë", "t": "ẗ",
        "y": "ÿ", "Y": "Ÿ", "u": "ü", "U": "Ü", "i": "ï", "I": "Ï",
        "o": "ö", "O": "Ö", "h": "ḧ", "H": "Ḧ", "w": "ẅ", "W": "Ẅ",
        "x": "ẍ", "X": "Ẍ",
    ]

    private static let acute: [String: String] = [
        "a": "á", "A": "Á", "c": "ć", "C": "Ć", "e": "é", "E": "É",
        "g": "ǵ", "G": "Ǵ", "i": "í", "I": "Í", "j": "ȷ́", "J": "J́",
        "k": "ḱ", "K": "Ḱ", "l": "ĺ", "L": "Ĺ", "m": "ḿ", "M": "Ḿ",
        "n": "ń", "N": "Ń", "o": "ó", "O": "Ó", "p": "ṕ", "P": "Ṕ",
        "r": "ŕ", "R": "Ŕ", "s": "ś", "S": "Ś", "u": "ú", "U": "Ú",
        "v": "v́", "V": "V́", "w": "ẃ", "W": "Ẃ", "y": "ý", "Y": "Ý",
        "z": "ź", "Z": "Ź", "ê": "ế", "Ê": "Ế", "ç": "ḉ", "Ç": "Ḉ",
    ]

    private static let grave: [String: String] = [
        "a": "à", "A": "À", "e": "è", "E": "È", "i": "ì", "I": "Ì",
        "m": "m̀", "M": "M̀", "n": "ǹ", "N": "Ǹ", "o": "ò", "O": "Ò",
        "u": "ù", "U": "Ù", "v": "v̀", "V": "V̀", "w": "ẁ", "W": "Ẁ",
        "y": "ỳ", "Y": "Ỳ", "ê": "ề", "Ê": "Ề",
    ]

    // The caron also produces subscript numbers (legacy comment).
    private static let caron: [String: String] = [
        "a": "ǎ", "A": "Ǎ", "c": "č", "C": "Č", "d": "ď", "D": "Ď",
        "e": "ě", "E": "Ě", "g": "ǧ", "G": "Ǧ", "h": "ȟ", "H": "Ȟ",
        "i": "ǐ", "I": "Ǐ", "j": "ǰ", "k": "ǩ", "K": "Ǩ", "l": "ľ",
        "L": "Ľ", "n": "ň", "N": "Ň", "o": "ǒ", "O": "Ǒ", "r": "ř",
        "R": "Ř", "s": "š", "S": "Š", "t": "ť", "T": "Ť", "u": "ǔ",
        "U": "Ǔ", "z": "ž", "Z": "Ž",
        "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅",
        "6": "₆", "7": "₇", "8": "₈", "9": "₉", "0": "₀",
    ]

    private static let bar: [String: String] = [
        "a": "ⱥ", "A": "Ⱥ", "b": "ƀ", "B": "Ƀ", "c": "ȼ", "C": "Ȼ",
        "d": "đ", "D": "Đ", "e": "ɇ", "E": "Ɇ", "g": "ǥ", "G": "Ǥ",
        "h": "ħ", "H": "Ħ", "i": "ɨ", "I": "Ɨ", "j": "ɉ", "J": "Ɉ",
        "l": "ł", "L": "Ł", "o": "ø", "O": "Ø", "p": "ᵽ", "P": "Ᵽ",
        "r": "ɍ", "R": "Ɍ", "t": "ŧ", "T": "Ŧ", "u": "ʉ", "U": "Ʉ",
        "y": "ɏ", "Y": "Ɏ", "z": "ƶ", "Z": "Ƶ",
    ]

    private static let breve: [String: String] = [
        "a": "ă", "A": "Ă", "e": "ĕ", "E": "Ĕ", "g": "ğ", "G": "Ğ",
        "i": "ĭ", "I": "Ĭ", "o": "ŏ", "O": "Ŏ", "u": "ŭ", "U": "Ŭ",
        "à": "ằ", "À": "Ằ",
    ]

    private static let tilde: [String: String] = [
        "a": "ã", "A": "Ã", "e": "ẽ", "E": "Ẽ", "i": "ĩ", "I": "Ĩ",
        "n": "ñ", "N": "Ñ", "o": "õ", "O": "Õ", "u": "ũ", "U": "Ũ",
        "v": "ṽ", "V": "Ṽ", "y": "ỹ", "Y": "Ỹ", "ê": "ễ", "Ê": "Ễ",
    ]

    private static let macron: [String: String] = [
        "a": "ā", "A": "Ā", "e": "ē", "E": "Ē", "g": "ḡ", "G": "Ḡ",
        "i": "ī", "I": "Ī", "o": "ō", "O": "Ō", "u": "ū", "U": "Ū",
        "y": "ȳ", "Y": "Ȳ", "é": "ḗ", "É": "Ḗ", "è": "ḕ", "È": "Ḕ",
    ]

    private static let cedilla: [String: String] = [
        "c": "ç", "C": "Ç", "d": "ḑ", "D": "Ḑ", "e": "ȩ", "E": "Ȩ",
        "g": "ģ", "G": "Ģ", "h": "ḩ", "H": "Ḩ", "k": "ķ", "K": "Ķ",
        "l": "ļ", "L": "Ļ", "n": "ņ", "N": "Ņ", "r": "ŗ", "R": "Ŗ",
        "s": "ş", "S": "Ş", "t": "ţ", "T": "Ţ",
    ]

    private static let overring: [String: String] = [
        "a": "å", "A": "Å", "u": "ů", "U": "Ů", "w": "ẘ", "y": "ẙ",
    ]

    private static let greek: [String: String] = [
        "b": "β", "p": "π", "P": "Π", "d": "δ", "D": "Δ", "l": "λ",
        "L": "Λ", "j": "θ", "J": "Θ", "z": "ζ", "w": "ω", "W": "Ω",
        "A": "α", "u": "υ", "U": "Υ", "i": "ι", "e": "ε", "t": "τ",
        "s": "σ", "S": "Σ", "r": "ρ", "R": "Ρ", "n": "ν", "m": "μ",
        "y": "ψ", "Y": "Ψ", "x": "ξ", "X": "Ξ", "k": "κ", "q": "χ",
        "Q": "Χ", "g": "γ", "G": "Γ", "h": "η", "f": "φ", "F": "Φ",
    ]

    private static let iotaSubscript: [String: String] = [
        "o": "ǫ", "O": "Ǫ", "a": "ą", "A": "Ą", "u": "ų", "U": "Ų",
        "i": "į", "I": "Į", "e": "ę", "E": "Ę",
    ]
}

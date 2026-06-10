import Foundation

// Native port of the retired file-icons pipeline: `assets/icons/file-icons.json`
// (SVG fragments per icon name) plus `assets/misc/file-icons-match.json` (the
// ordered filename→icon regex cascade frozen from the generated
// `file-icons-match.js`). Matching semantics mirror the legacy fsDisp:
// unanchored regex search, first rule wins, special roles bypass matching.

// MARK: - Catalog

public struct FileIconCatalogEntry: Equatable, Sendable {
    /// The generator emitted numbers, numeric strings, and nulls depending on
    /// the source icon pack, so dimensions are optional after lenient decode.
    public let width: Double?
    public let height: Double?
    /// Inner SVG markup (no enclosing `<svg>` element).
    public let svg: String

    public init(width: Double?, height: Double?, svg: String) {
        self.width = width
        self.height = height
        self.svg = svg
    }
}

public struct FileIconCatalog: Sendable {
    private let entries: [String: FileIconCatalogEntry]

    public init(entries: [String: FileIconCatalogEntry]) {
        self.entries = entries
    }

    public var count: Int { entries.count }
    public var names: [String] { Array(entries.keys) }

    public static func load(from url: URL) throws -> FileIconCatalog {
        let data = try Data(contentsOf: url)
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FileIconError.malformedCatalog
        }
        var entries: [String: FileIconCatalogEntry] = [:]
        entries.reserveCapacity(raw.count)
        for (name, value) in raw {
            guard let object = value as? [String: Any],
                  let svg = object["svg"] as? String else { continue }
            entries[name] = FileIconCatalogEntry(
                width: lenientDimension(object["width"]),
                height: lenientDimension(object["height"]),
                svg: svg
            )
        }
        return FileIconCatalog(entries: entries)
    }

    public func entry(named name: String) -> FileIconCatalogEntry? {
        entries[name]
    }

    /// Builds a standalone SVG document like the legacy renderer did
    /// (`<svg viewBox="0 0 w h" fill="...">inner</svg>`), or nil when the
    /// entry is missing or its dimensions never survived generation.
    public func svgDocument(named name: String, fill: String) -> String? {
        guard let entry = entries[name],
              let width = entry.width, let height = entry.height,
              width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(dimensionText(width)) \(dimensionText(height))" fill="\(fill)">\(entry.svg)</svg>
        """
    }

    private static func lenientDimension(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            let dimension = number.doubleValue
            return dimension.isFinite ? dimension : nil
        case let text as String:
            return Double(text)
        default:
            return nil
        }
    }

    private func dimensionText(_ value: Double) -> String {
        if let exact = Int(exactly: value.rounded()), value == value.rounded() {
            return String(exact)
        }
        return String(value)
    }
}

public enum FileIconError: Error, Equatable {
    case malformedCatalog
}

// MARK: - Matcher

public struct FileIconRule: Equatable, Sendable {
    public let pattern: String
    public let caseInsensitive: Bool
    public let icon: String

    public init(pattern: String, caseInsensitive: Bool, icon: String) {
        self.pattern = pattern
        self.caseInsensitive = caseInsensitive
        self.icon = icon
    }
}

public struct FileIconMatcher {
    public let rules: [FileIconRule]
    /// Patterns that failed ICU compilation; those rules are skipped.
    public let compilationFailures: [String]
    private let compiled: [(regex: NSRegularExpression, icon: String)]

    public var ruleCount: Int { rules.count }

    public init(rules: [FileIconRule]) {
        self.rules = rules
        var compiled: [(NSRegularExpression, String)] = []
        compiled.reserveCapacity(rules.count)
        var failures: [String] = []
        for rule in rules {
            var options: NSRegularExpression.Options = []
            if rule.caseInsensitive { options.insert(.caseInsensitive) }
            if let regex = try? NSRegularExpression(pattern: rule.pattern, options: options) {
                compiled.append((regex, rule.icon))
            } else {
                failures.append(rule.pattern)
            }
        }
        self.compiled = compiled
        self.compilationFailures = failures
    }

    public static func load(from url: URL) throws -> FileIconMatcher {
        struct Document: Decodable {
            struct Rule: Decodable {
                let pattern: String
                let caseInsensitive: Bool
                let icon: String
            }
            let rules: [Rule]
        }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        return FileIconMatcher(rules: document.rules.map {
            FileIconRule(pattern: $0.pattern, caseInsensitive: $0.caseInsensitive, icon: $0.icon)
        })
    }

    /// First matching rule wins; patterns are unanchored searches, mirroring
    /// JS `regex.test(filename)`.
    public func icon(forName name: String) -> String? {
        let range = NSRange(name.startIndex..., in: name)
        for (regex, icon) in compiled {
            if regex.firstMatch(in: name, options: [], range: range) != nil {
                return icon
            }
        }
        return nil
    }
}

// MARK: - Resolution

public enum FileIconResolution: Equatable, Sendable {
    /// An icon from `file-icons.json` (may still be absent — render falls back).
    case catalog(String)
    /// One of the bespoke eDEX icons the legacy fsDisp defined inline.
    case edex(EdexFsIcon)
}

public enum FileIconResolver {
    /// Mirrors the legacy fsDisp switch: fixed-icon roles bypass the matcher;
    /// plain files and directories try the regex cascade and fall back to the
    /// generic `file`/`dir` catalog icons.
    public static func resolve(
        name: String,
        role: FilesystemRole,
        matcher: FileIconMatcher?
    ) -> FileIconResolution {
        switch role {
        case .showDisks: return .catalog("showDisks")
        case .goUp: return .catalog("up")
        case .symlink: return .catalog("symlink")
        case .disk: return .catalog("disk")
        case .rom: return .catalog("rom")
        case .usb: return .catalog("usb")
        case .themesDir: return .edex(.themesDir)
        case .keyboardsDir: return .edex(.kblayoutsDir)
        case .themeFile: return .edex(.theme)
        case .keyboardFile: return .edex(.kblayout)
        case .settingsFile, .shortcutsFile: return .edex(.settings)
        case .directory:
            if let matched = matcher?.icon(forName: name) { return .catalog(matched) }
            return .catalog("dir")
        case .file:
            if let matched = matcher?.icon(forName: name) { return .catalog(matched) }
            return .catalog("file")
        }
    }
}

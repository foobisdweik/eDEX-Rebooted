import AppKit
import EdexDomainSupport
import EdexRenderingSupport
import Observation
import SwiftUI

/// Serves themed filesystem icons from the frozen file-icons data
/// (`assets/icons/file-icons.json` + `assets/misc/file-icons-match.json`),
/// replacing the SF Symbol placeholders with the legacy fsDisp glyphs.
///
/// The catalog and the 2,408-rule matcher load lazily off the MainActor
/// (the catalog is ~1 MB of JSON; loading it at launch would claw back the
/// startup time the telemetry-perf pass removed). Views read `isReady`
/// through `@Observable` tracking, so they re-render once data arrives and
/// fall back to SF Symbols until then.
@Observable
@MainActor
final class FileIconProvider {
    static let shared = FileIconProvider()

    private(set) var isReady = false

    @ObservationIgnored private var catalog: FileIconCatalog?
    @ObservationIgnored private var matcher: FileIconMatcher?
    @ObservationIgnored private var loadStarted = false
    /// filename+role → resolved icon image, reset when the fill colors change.
    @ObservationIgnored private var imageCache: [String: NSImage] = [:]
    @ObservationIgnored private var cachedFillKey = ""

    func image(forName name: String, role: FilesystemRole, theme: NativeTheme) -> NSImage? {
        beginLoadingIfNeeded()
        guard isReady else { return nil }

        let fill = theme.palette.accent.hexRGB
        let secondaryFill = theme.legacyLightBlack.hexRGB
        resetCacheIfFillsChanged(fill: fill, secondaryFill: secondaryFill)

        // The cache key must name the glyph actually drawn, not the matched
        // icon id: when a matched id has no renderable catalog entry, the
        // fallback differs by role (`dir` vs `file`), so keying on the
        // matched id would pin one role's fallback for the other.
        let cacheKey: String
        let document: String?
        switch FileIconResolver.resolve(name: name, role: role, matcher: matcher) {
        case .catalog(let iconName):
            if let matchedDocument = catalog?.svgDocument(named: iconName, fill: fill) {
                cacheKey = "c:\(iconName)"
                document = matchedDocument
            } else {
                // Legacy fallback chain: matched icon → role icon → `other`;
                // the caller's SF Symbol remains the last resort.
                let fallbackName = Self.roleFallbackIconName(for: role)
                cacheKey = "c:\(fallbackName)"
                document = catalog?.svgDocument(named: fallbackName, fill: fill)
                    ?? catalog?.svgDocument(named: "other", fill: fill)
            }
        case .edex(let icon):
            cacheKey = "e:\(icon.rawValue)"
            document = icon.svgDocument(fill: fill, secondaryFill: secondaryFill)
        }
        if let cached = imageCache[cacheKey] { return cached }
        guard let document,
              let data = document.data(using: .utf8),
              let image = NSImage(data: data) else { return nil }
        imageCache[cacheKey] = image
        return image
    }

    /// Themed playback-control glyphs from the file-icons catalog (`play`,
    /// `pause`, `volume`, `mute`, `fullscreen`, `fullscreen-exit`).
    func controlImage(named name: String, theme: NativeTheme) -> NSImage? {
        beginLoadingIfNeeded()
        guard isReady else { return nil }

        let fill = theme.palette.accent.hexRGB
        resetCacheIfFillsChanged(fill: fill, secondaryFill: theme.legacyLightBlack.hexRGB)

        let cacheKey = "ctl:\(name)"
        if let cached = imageCache[cacheKey] { return cached }
        guard let document = catalog?.svgDocument(named: name, fill: fill),
              let data = document.data(using: .utf8),
              let image = NSImage(data: data) else { return nil }
        imageCache[cacheKey] = image
        return image
    }

    private func beginLoadingIfNeeded() {
        guard !loadStarted else { return }
        loadStarted = true
        Task.detached(priority: .utility) {
            // Catalog and matcher degrade independently — the legacy renderer
            // did the same (`window.__FILE_ICONS_MATCHER__ || (() => "file")`):
            // a missing matcher still leaves role/edex glyphs working, and a
            // missing catalog falls back to SF Symbols. Surface either failure
            // loudly so the degraded mode is at least visible in logs.
            var catalog: FileIconCatalog?
            do {
                catalog = try FileIconCatalog.load(from: EdexBundledAssets.fileIconsCatalogURL())
            } catch {
                print("eDEXNative file-icons catalog failed to load: \(error)")
            }
            var matcher: FileIconMatcher?
            do {
                matcher = try FileIconMatcher.load(from: EdexBundledAssets.fileIconsMatchRulesURL())
                if let failures = matcher?.compilationFailures, !failures.isEmpty {
                    print("eDEXNative file-icons matcher skipped \(failures.count) uncompilable rules")
                }
            } catch {
                print("eDEXNative file-icons matcher failed to load: \(error)")
            }
            await MainActor.run { [weak self, catalog, matcher] in
                guard let self else { return }
                self.catalog = catalog
                self.matcher = matcher
                self.isReady = catalog != nil
            }
        }
    }

    private func resetCacheIfFillsChanged(fill: String, secondaryFill: String) {
        let fillKey = "\(fill)|\(secondaryFill)"
        if fillKey != cachedFillKey {
            imageCache.removeAll(keepingCapacity: true)
            cachedFillKey = fillKey
        }
    }

    private static func roleFallbackIconName(for role: FilesystemRole) -> String {
        switch role {
        case .directory, .themesDir, .keyboardsDir: return "dir"
        default: return "file"
        }
    }
}

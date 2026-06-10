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
        let secondaryFill = secondaryFillHex(for: theme)
        let fillKey = "\(fill)|\(secondaryFill)"
        if fillKey != cachedFillKey {
            imageCache.removeAll(keepingCapacity: true)
            cachedFillKey = fillKey
        }

        let resolution = FileIconResolver.resolve(name: name, role: role, matcher: matcher)
        let cacheKey: String
        switch resolution {
        case .catalog(let iconName): cacheKey = "c:\(iconName)"
        case .edex(let icon): cacheKey = "e:\(icon.rawValue)"
        }
        if let cached = imageCache[cacheKey] { return cached }

        let document: String?
        switch resolution {
        case .catalog(let iconName):
            // Mirror the legacy fallback chain: matched icon → role icon →
            // `other`; the caller's SF Symbol remains the last resort.
            document = catalog?.svgDocument(named: iconName, fill: fill)
                ?? fallbackDocument(for: role, fill: fill)
        case .edex(let icon):
            document = icon.svgDocument(fill: fill, secondaryFill: secondaryFill)
        }
        guard let document,
              let data = document.data(using: .utf8),
              let image = NSImage(data: data) else { return nil }
        imageCache[cacheKey] = image
        return image
    }

    private func beginLoadingIfNeeded() {
        guard !loadStarted else { return }
        loadStarted = true
        Task.detached(priority: .utility) {
            let catalog = try? FileIconCatalog.load(from: EdexBundledAssets.fileIconsCatalogURL())
            let matcher = try? FileIconMatcher.load(from: EdexBundledAssets.fileIconsMatchRulesURL())
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.catalog = catalog
                self.matcher = matcher
                self.isReady = catalog != nil
            }
        }
    }

    private func fallbackDocument(for role: FilesystemRole, fill: String) -> String? {
        guard let catalog else { return nil }
        let roleIcon: String
        switch role {
        case .directory, .themesDir, .keyboardsDir: roleIcon = "dir"
        default: roleIcon = "file"
        }
        return catalog.svgDocument(named: roleIcon, fill: fill)
            ?? catalog.svgDocument(named: "other", fill: fill)
    }

    private func secondaryFillHex(for theme: NativeTheme) -> String {
        let swatch = theme.palette.swatches["lightBlack"]
            ?? theme.palette.swatches["light_black"]
            ?? theme.palette.swatches["black"]
        return (swatch ?? theme.palette.panelBackground).hexRGB
    }
}

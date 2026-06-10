import AppKit
import XCTest

@testable import EdexDomainSupport

final class NativeFileIconTests: XCTestCase {

    // MARK: - Catalog (assets/icons/file-icons.json)

    func testCatalogLoadsBundledEntries() throws {
        let catalog = try FileIconCatalog.load(from: EdexBundledAssets.fileIconsCatalogURL())
        XCTAssertGreaterThanOrEqual(catalog.count, 1600)
        // eDEX-specific role icons appended by the retired generator.
        for name in ["dir", "file", "symlink", "disk", "rom", "usb", "up", "showDisks", "other"] {
            XCTAssertNotNil(catalog.entry(named: name), "missing role icon \(name)")
        }
        XCTAssertNotNil(catalog.entry(named: "python"))
        XCTAssertNil(catalog.entry(named: "no-such-icon"))
    }

    func testCatalogDecodesLenientDimensions() throws {
        // The generator emitted numbers, numeric strings, and nulls for
        // width/height depending on the source icon pack.
        let catalog = try FileIconCatalog.load(from: EdexBundledAssets.fileIconsCatalogURL())
        let github = try XCTUnwrap(catalog.entry(named: "github"))  // "64" as string
        XCTAssertEqual(github.width, 64)
        XCTAssertEqual(github.height, 64)
        let drupal = try XCTUnwrap(catalog.entry(named: "drupal"))  // float
        XCTAssertEqual(drupal.width ?? 0, 447.87, accuracy: 0.01)
        let dyalog = try XCTUnwrap(catalog.entry(named: "dyalog"))  // null dims
        XCTAssertNil(dyalog.width)
        XCTAssertNil(dyalog.height)
    }

    func testSvgDocumentWrapsEntryWithViewBoxAndFill() throws {
        let catalog = try FileIconCatalog.load(from: EdexBundledAssets.fileIconsCatalogURL())
        let doc: String = try XCTUnwrap(catalog.svgDocument(named: "dir", fill: "#00ff9c"))
        XCTAssertTrue(doc.hasPrefix("<svg"))
        XCTAssertTrue(doc.contains("xmlns=\"http://www.w3.org/2000/svg\""))
        XCTAssertTrue(doc.contains("viewBox=\"0 0 24 24\""))
        XCTAssertTrue(doc.contains("fill=\"#00ff9c\""))
        XCTAssertTrue(doc.contains("<path"))
        XCTAssertTrue(doc.hasSuffix("</svg>"))
    }

    func testSvgDocumentIsNilForMissingDimensionsOrName() throws {
        let catalog = try FileIconCatalog.load(from: EdexBundledAssets.fileIconsCatalogURL())
        XCTAssertNil(catalog.svgDocument(named: "dyalog", fill: "#fff"), "null-dim entries cannot build a viewBox")
        XCTAssertNil(catalog.svgDocument(named: "no-such-icon", fill: "#fff"))
    }

    // MARK: - Matcher (assets/misc/file-icons-match.json)

    func testMatcherLoadsBundledRulesAndAllCompile() throws {
        let matcher = try FileIconMatcher.load(from: EdexBundledAssets.fileIconsMatchRulesURL())
        XCTAssertEqual(matcher.ruleCount, 2408)
        XCTAssertEqual(matcher.compilationFailures, [], "every frozen rule must compile under ICU")
    }

    func testRepresentativeFilenameMatches() throws {
        let matcher = try FileIconMatcher.load(from: EdexBundledAssets.fileIconsMatchRulesURL())
        XCTAssertEqual(matcher.icon(forName: "script.py"), "python")
        XCTAssertEqual(matcher.icon(forName: "main.rs"), "rust")
        XCTAssertEqual(matcher.icon(forName: "App.swift"), "swift")
        XCTAssertEqual(matcher.icon(forName: "node_modules"), "node")
        XCTAssertEqual(matcher.icon(forName: "Dockerfile"), "docker")
        XCTAssertEqual(matcher.icon(forName: "README.md"), "markdown")
        XCTAssertEqual(matcher.icon(forName: ".git"), "git")
    }

    func testUnmatchedFilenameReturnsNil() throws {
        let matcher = try FileIconMatcher.load(from: EdexBundledAssets.fileIconsMatchRulesURL())
        XCTAssertNil(matcher.icon(forName: "completely-unknown-blob.zzz9"))
    }

    func testFirstMatchingRuleWins() {
        let matcher = FileIconMatcher(rules: [
            FileIconRule(pattern: "\\.py$", caseInsensitive: true, icon: "first"),
            FileIconRule(pattern: "\\.py$", caseInsensitive: true, icon: "second"),
        ])
        XCTAssertEqual(matcher.icon(forName: "a.py"), "first")
    }

    func testCaseSensitivityIsPerRule() {
        let matcher = FileIconMatcher(rules: [
            FileIconRule(pattern: "^node_modules$", caseInsensitive: false, icon: "node"),
            FileIconRule(pattern: "^readme", caseInsensitive: true, icon: "book"),
        ])
        XCTAssertEqual(matcher.icon(forName: "node_modules"), "node")
        XCTAssertNil(matcher.icon(forName: "NODE_MODULES"))
        XCTAssertEqual(matcher.icon(forName: "ReadMe.txt"), "book")
    }

    func testPatternsAreUnanchoredSearches() {
        // JS `.test` scans anywhere in the string unless the pattern anchors.
        let matcher = FileIconMatcher(rules: [
            FileIconRule(pattern: "abc", caseInsensitive: false, icon: "found")
        ])
        XCTAssertEqual(matcher.icon(forName: "xx-abc-yy"), "found")
    }

    func testInvalidPatternIsSkippedNotFatal() {
        let matcher = FileIconMatcher(rules: [
            FileIconRule(pattern: "([unclosed", caseInsensitive: false, icon: "broken"),
            FileIconRule(pattern: "\\.ok$", caseInsensitive: false, icon: "ok"),
        ])
        XCTAssertEqual(matcher.compilationFailures, ["([unclosed"])
        XCTAssertEqual(matcher.icon(forName: "a.ok"), "ok")
    }

    // MARK: - Resolution (mirrors the retired fsDisp icon switch)

    func testSpecialRolesBypassMatching() {
        // A matcher that would match anything must not be consulted for
        // fixed-icon roles.
        let greedy = FileIconMatcher(rules: [
            FileIconRule(pattern: ".", caseInsensitive: false, icon: "greedy")
        ])
        XCTAssertEqual(FileIconResolver.resolve(name: "Show disks", role: .showDisks, matcher: greedy), .catalog("showDisks"))
        XCTAssertEqual(FileIconResolver.resolve(name: "Go up", role: .goUp, matcher: greedy), .catalog("up"))
        XCTAssertEqual(FileIconResolver.resolve(name: "link", role: .symlink, matcher: greedy), .catalog("symlink"))
        XCTAssertEqual(FileIconResolver.resolve(name: "ssd", role: .disk, matcher: greedy), .catalog("disk"))
        XCTAssertEqual(FileIconResolver.resolve(name: "cd", role: .rom, matcher: greedy), .catalog("rom"))
        XCTAssertEqual(FileIconResolver.resolve(name: "stick", role: .usb, matcher: greedy), .catalog("usb"))
    }

    func testEdexRolesUseBespokeIcons() {
        let greedy = FileIconMatcher(rules: [
            FileIconRule(pattern: ".", caseInsensitive: false, icon: "greedy")
        ])
        XCTAssertEqual(FileIconResolver.resolve(name: "themes", role: .themesDir, matcher: greedy), .edex(.themesDir))
        XCTAssertEqual(FileIconResolver.resolve(name: "keyboards", role: .keyboardsDir, matcher: greedy), .edex(.kblayoutsDir))
        XCTAssertEqual(FileIconResolver.resolve(name: "tron.json", role: .themeFile, matcher: greedy), .edex(.theme))
        XCTAssertEqual(FileIconResolver.resolve(name: "en-US.json", role: .keyboardFile, matcher: greedy), .edex(.kblayout))
        XCTAssertEqual(FileIconResolver.resolve(name: "settings.json", role: .settingsFile, matcher: greedy), .edex(.settings))
        XCTAssertEqual(FileIconResolver.resolve(name: "shortcuts.json", role: .shortcutsFile, matcher: greedy), .edex(.settings))
    }

    func testFilesAndDirectoriesMatchThenFallBack() {
        let matcher = FileIconMatcher(rules: [
            FileIconRule(pattern: "^node_modules$", caseInsensitive: false, icon: "node")
        ])
        XCTAssertEqual(FileIconResolver.resolve(name: "node_modules", role: .directory, matcher: matcher), .catalog("node"))
        XCTAssertEqual(FileIconResolver.resolve(name: "plain-folder", role: .directory, matcher: matcher), .catalog("dir"))
        XCTAssertEqual(FileIconResolver.resolve(name: "node_modules", role: .file, matcher: matcher), .catalog("node"))
        XCTAssertEqual(FileIconResolver.resolve(name: "plain.bin", role: .file, matcher: matcher), .catalog("file"))
        XCTAssertEqual(FileIconResolver.resolve(name: "anything", role: .file, matcher: nil), .catalog("file"))
    }

    // MARK: - Bespoke eDEX icons

    func testEdexFsIconDocumentsSubstituteFills() {
        for icon in EdexFsIcon.allCases {
            let doc = icon.svgDocument(fill: "#00ff9c", secondaryFill: "#102030")
            XCTAssertTrue(doc.hasPrefix("<svg"), "\(icon)")
            XCTAssertTrue(doc.contains("viewBox=\"0 0 24 24\""), "\(icon)")
            XCTAssertTrue(doc.contains("fill=\"#00ff9c\""), "\(icon)")
            XCTAssertFalse(doc.contains("EDEX_SECONDARY_FILL"), "\(icon) leaked the placeholder")
        }
        // The two-tone folder icons carry the secondary fill.
        XCTAssertTrue(EdexFsIcon.themesDir.svgDocument(fill: "#fff", secondaryFill: "#102030").contains("fill=\"#102030\""))
        XCTAssertTrue(EdexFsIcon.kblayoutsDir.svgDocument(fill: "#fff", secondaryFill: "#102030").contains("fill=\"#102030\""))
    }

    func testEdexFsIconsParseAsNSImage() throws {
        for icon in EdexFsIcon.allCases {
            let doc = icon.svgDocument(fill: "#00ff9c", secondaryFill: "#102030")
            let data = try XCTUnwrap(doc.data(using: .utf8))
            XCTAssertNotNil(NSImage(data: data), "\(icon) did not parse")
        }
    }

    // MARK: - Catalog/rules drift

    func testKnownRuleIconDriftIsBounded() throws {
        // 158 rule targets were already absent from the catalog in the original
        // generated data; the renderer falls back for those. This pins the
        // count so silent drift in either frozen file fails loudly.
        let catalog = try FileIconCatalog.load(from: EdexBundledAssets.fileIconsCatalogURL())
        let matcher = try FileIconMatcher.load(from: EdexBundledAssets.fileIconsMatchRulesURL())
        let referenced = Set(matcher.rules.map(\.icon))
        let missing = referenced.filter { catalog.entry(named: $0) == nil }
        XCTAssertEqual(missing.count, 158)
    }

    // MARK: - SVG render census (AppKit)

    func testEveryDimensionedCatalogEntryParsesAsNSImage() throws {
        let catalog = try FileIconCatalog.load(from: EdexBundledAssets.fileIconsCatalogURL())
        var failures: [String] = []
        var rendered = 0
        for name in catalog.names {
            guard let doc = catalog.svgDocument(named: name, fill: "#00ff9c") else { continue }
            guard let data = doc.data(using: .utf8), NSImage(data: data) != nil else {
                failures.append(name)
                continue
            }
            rendered += 1
        }
        XCTAssertGreaterThanOrEqual(rendered, 1600)
        XCTAssertEqual(failures, [], "catalog entries NSImage refused to parse")
    }

    func testRoleIconsRasterize() throws {
        // Fully draw the always-visible role icons, not just parse them.
        let catalog = try FileIconCatalog.load(from: EdexBundledAssets.fileIconsCatalogURL())
        for name in ["dir", "file", "symlink", "disk", "rom", "usb", "up", "showDisks", "python"] {
            let doc: String = try XCTUnwrap(catalog.svgDocument(named: name, fill: "#00ff9c"))
            let data = try XCTUnwrap(doc.data(using: .utf8))
            let image = try XCTUnwrap(NSImage(data: data))
            let rep = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 24, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            let ctx = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            image.draw(in: NSRect(x: 0, y: 0, width: 24, height: 24))
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

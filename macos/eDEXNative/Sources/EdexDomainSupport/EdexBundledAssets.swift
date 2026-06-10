import Foundation

/// Bundled data paths shared by the native app and Rust core. Packaged app
/// builds read from `Contents/Resources/assets`; SwiftPM dev/test runs fall
/// back to the repository-root `assets/` tree. Runtime userdata still lives
/// under `~/Library/Application Support/eDEX-UI/`.
public enum EdexBundledAssets {
    public static func repositoryRoot(
        from filePath: String = #filePath,
        bundleResourceURL: URL? = Bundle.main.resourceURL
    ) -> URL {
        if let bundleResourceURL,
           FileManager.default.fileExists(
               atPath: bundleResourceURL.appendingPathComponent("assets", isDirectory: true).path
           ) {
            return bundleResourceURL
        }

        var candidate = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("assets").path) {
                return candidate
            }
            if candidate.lastPathComponent == "macos" {
                return candidate.deletingLastPathComponent()
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { break }
            candidate = parent
        }
        return URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    public static func themesDirectory(from filePath: String = #filePath) -> URL {
        repositoryRoot(from: filePath).appendingPathComponent("assets/themes", isDirectory: true)
    }

    public static func keyboardsDirectory(from filePath: String = #filePath) -> URL {
        repositoryRoot(from: filePath).appendingPathComponent("assets/kb_layouts", isDirectory: true)
    }

    public static func audioDirectory(from filePath: String = #filePath) -> URL {
        repositoryRoot(from: filePath).appendingPathComponent("assets/audio", isDirectory: true)
    }

    public static func fileIconsCatalogURL(from filePath: String = #filePath) -> URL {
        repositoryRoot(from: filePath).appendingPathComponent("assets/icons/file-icons.json")
    }

    public static func fileIconsMatchRulesURL(from filePath: String = #filePath) -> URL {
        repositoryRoot(from: filePath).appendingPathComponent("assets/misc/file-icons-match.json")
    }
}

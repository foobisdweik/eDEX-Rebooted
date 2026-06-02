import Foundation

// Phase 7.1 filesystem panel support — pure, FFI-free module.
//
// Encodes the legacy filesystem.class.js behavior independent of AppKit/FFI:
// byte formatting, POSIX path math, text/media type detection, directory-listing
// assembly (sorting + the "Show disks"/"Go up" special rows + eDEX userdata
// tagging), disk-view rows, and the disk-usage bar math. ShellState bridges the
// FFI records (FfiDirEntry / FfiDiskUsage / FfiBlockDevice) into these inputs.

// MARK: - Byte formatting

public enum FilesystemFormatter {
    private static let units = ["Bytes", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"]

    /// Human-readable size, mirroring the legacy `_formatBytes` (1024-based,
    /// 2-decimal precision with trailing zeros stripped: 1024 → "1 KB",
    /// 1536 → "1.5 KB").
    public static func formatBytes(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "0 Bytes" }
        let value = Double(bytes)
        let exponent = min(Int(floor(log(value) / log(1024.0))), units.count - 1)
        let scaled = value / pow(1024.0, Double(exponent))
        return "\(trimmed(scaled)) \(units[exponent])"
    }

    /// Rounds to 2 decimals and strips trailing zeros (parseFloat(x.toFixed(2))).
    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

// MARK: - Path math (POSIX, macOS-only)

public enum PathUtils {
    /// Joins path components, dropping empties and collapsing repeated slashes.
    public static func join(_ parts: [String]) -> String {
        let joined = parts.filter { !$0.isEmpty }.joined(separator: "/")
        var result = ""
        var lastWasSlash = false
        for char in joined {
            if char == "/" {
                if !lastWasSlash { result.append(char) }
                lastWasSlash = true
            } else {
                result.append(char)
                lastWasSlash = false
            }
        }
        return result
    }

    /// Normalizes `base` + components into an absolute path, resolving `.`/`..`.
    public static func resolve(_ base: String, _ rest: String...) -> String {
        let combined = join([base] + rest)
        var out: [String] = []
        for component in combined.split(separator: "/", omittingEmptySubsequences: false) {
            let part = String(component)
            if part.isEmpty || part == "." { continue }
            if part == ".." { if !out.isEmpty { out.removeLast() }; continue }
            out.append(part)
        }
        return "/" + out.joined(separator: "/")
    }

    /// Last path component, ignoring trailing slashes. "/" → "".
    public static func basename(_ path: String) -> String {
        var stripped = path
        while stripped.hasSuffix("/") { stripped.removeLast() }
        guard let slash = stripped.lastIndex(of: "/") else { return stripped }
        return String(stripped[stripped.index(after: slash)...])
    }

    /// Parent directory. parent("/") → "/".
    public static func parent(_ path: String) -> String {
        resolve(path, "..")
    }
}

// MARK: - Type detection

public enum MediaKind: Equatable, Sendable { case image, audio, video }

public enum FileTypeDetector {
    // Tiny mime table replacing the `mime-types` npm package (CommonJS-only),
    // copied from filesystem.class.js MIME_EXT.
    private static let mimeByExtension: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
        "webp": "image/webp", "svg": "image/svg+xml", "bmp": "image/bmp", "ico": "image/x-icon",
        "mp3": "audio/mpeg", "wav": "audio/wav", "ogg": "audio/ogg", "flac": "audio/flac", "m4a": "audio/mp4",
        "mp4": "video/mp4", "webm": "video/webm", "mov": "video/quicktime", "mkv": "video/x-matroska",
        "pdf": "application/pdf",
        "txt": "text/plain", "md": "text/markdown", "json": "application/json", "xml": "text/xml",
        "js": "text/javascript", "ts": "text/typescript", "html": "text/html", "css": "text/css",
        "py": "text/x-python", "rs": "text/x-rust", "go": "text/x-go", "c": "text/x-c", "cpp": "text/x-c++",
        "rb": "text/x-ruby", "sh": "text/x-sh", "yaml": "text/yaml", "yml": "text/yaml", "toml": "text/toml",
        "log": "text/plain", "csv": "text/csv", "ini": "text/plain", "conf": "text/plain"
    ]

    private static func mime(forName name: String) -> String? {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        let ext = String(name[name.index(after: dot)...]).lowercased()
        return mimeByExtension[ext]
    }

    public static func isText(name: String) -> Bool {
        guard let mime = mime(forName: name) else { return false }
        return mime.hasPrefix("text/") || mime == "application/json" || mime == "application/xml"
    }

    public static func isPdf(name: String) -> Bool {
        mime(forName: name) == "application/pdf"
    }

    public static func mediaKind(name: String) -> MediaKind? {
        guard let mime = mime(forName: name) else { return nil }
        if mime.hasPrefix("image/") { return .image }
        if mime.hasPrefix("audio/") { return .audio }
        if mime.hasPrefix("video/") { return .video }
        return nil
    }
}

// MARK: - Entry model

public enum FileKind: Equatable, Sendable { case directory, symlink, file, other }

/// A raw directory entry, bridged from `FfiDirEntry` by ShellState.
public struct FilesystemEntry: Equatable, Sendable {
    public let name: String
    public let category: String
    public let hidden: Bool
    public let size: UInt64

    public init(name: String, category: String, hidden: Bool, size: UInt64) {
        self.name = name
        self.category = category
        self.hidden = hidden
        self.size = size
    }

    public var kind: FileKind {
        switch category {
        case "dir": return .directory
        case "symlink": return .symlink
        case "file": return .file
        default: return .other
        }
    }
}

// MARK: - Display item

public enum FilesystemRole: Equatable, Sendable {
    case goUp, showDisks
    case directory, symlink, file
    case themesDir, keyboardsDir, themeFile, keyboardFile, settingsFile, shortcutsFile
    case disk, rom, usb
}

public struct FilesystemItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let role: FilesystemRole
    public let hidden: Bool
    public let size: UInt64?

    public init(id: String, name: String, path: String, role: FilesystemRole, hidden: Bool, size: UInt64?) {
        self.id = id
        self.name = name
        self.path = path
        self.role = role
        self.hidden = hidden
        self.size = size
    }

    /// Formatted size for files; "--" for directories and special rows.
    public var sizeText: String {
        size.map(FilesystemFormatter.formatBytes) ?? "--"
    }

    /// Whether activating this row navigates into a new directory.
    public var isNavigable: Bool {
        switch role {
        case .goUp, .directory, .symlink, .themesDir, .keyboardsDir, .disk, .rom, .usb:
            return true
        default:
            return false
        }
    }
}

// MARK: - userdata tagging context

/// Paths that trigger eDEX-specific item roles (themes/keyboards dirs + the
/// settings/shortcuts/theme/keyboard config files). `.none` disables tagging.
public struct FilesystemContext: Equatable, Sendable {
    public let userDataDir: String?
    public let themesDir: String?
    public let keyboardsDir: String?

    public init(userDataDir: String?, themesDir: String?, keyboardsDir: String?) {
        self.userDataDir = userDataDir
        self.themesDir = themesDir
        self.keyboardsDir = keyboardsDir
    }

    public static let none = FilesystemContext(userDataDir: nil, themesDir: nil, keyboardsDir: nil)
}

// MARK: - Disk-view inputs

public struct DiskDevice: Equatable, Sendable {
    public let name: String
    public let deviceType: String
    public let mount: String
    public let removable: Bool
    public let label: String

    public init(name: String, deviceType: String, mount: String, removable: Bool, label: String) {
        self.name = name
        self.deviceType = deviceType
        self.mount = mount
        self.removable = removable
        self.label = label
    }
}

public struct DiskUsage: Equatable, Sendable {
    public let mount: String
    public let usePct: Double

    public init(mount: String, usePct: Double) {
        self.mount = mount
        self.usePct = usePct
    }
}

// MARK: - List builder

public enum FilesystemListBuilder {
    private static let kindOrder: [FileKind: Int] = [.directory: 0, .symlink: 1, .file: 2, .other: 3]

    /// Builds the displayed item list for a directory: sorted entries (dirs →
    /// symlinks → files → other, then localized name) with the "Show disks" row
    /// prepended (always) and "Go up" (unless already at root).
    public static func items(entries: [FilesystemEntry], path: String, context: FilesystemContext) -> [FilesystemItem] {
        let sorted = entries.sorted { lhs, rhs in
            let lo = kindOrder[lhs.kind] ?? 3
            let ro = kindOrder[rhs.kind] ?? 3
            if lo != ro { return lo < ro }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }

        var items: [FilesystemItem] = []
        items.append(FilesystemItem(id: "__showDisks__", name: "Show disks", path: "", role: .showDisks, hidden: false, size: nil))
        if path != "/" {
            items.append(FilesystemItem(id: "__goUp__", name: "Go up", path: PathUtils.parent(path), role: .goUp, hidden: false, size: nil))
        }

        for entry in sorted {
            let fullPath = PathUtils.resolve(path, entry.name)
            let role = self.role(for: entry, path: path, context: context)
            let size: UInt64? = entry.kind == .file ? entry.size : nil
            items.append(FilesystemItem(id: fullPath, name: entry.name, path: fullPath, role: role, hidden: entry.hidden, size: size))
        }
        return items
    }

    private static func role(for entry: FilesystemEntry, path: String, context: FilesystemContext) -> FilesystemRole {
        // eDEX userdata tagging (only when the context supplies the dirs).
        if entry.kind == .directory, path == context.userDataDir {
            if entry.name == "themes" { return .themesDir }
            if entry.name == "keyboards" { return .keyboardsDir }
        }
        if entry.kind == .file {
            if path == context.userDataDir {
                if entry.name == "settings.json" { return .settingsFile }
                if entry.name == "shortcuts.json" { return .shortcutsFile }
            }
            if path == context.themesDir, entry.name.hasSuffix(".json") { return .themeFile }
            if path == context.keyboardsDir, entry.name.hasSuffix(".json") { return .keyboardFile }
        }

        switch entry.kind {
        case .directory: return .directory
        case .symlink: return .symlink
        case .file, .other: return .file
        }
    }

    /// Builds the "Show disks" view rows from block devices, mirroring the legacy
    /// `readDevices()` classification and naming.
    public static func diskItems(devices: [DiskDevice]) -> [FilesystemItem] {
        devices.map { device in
            let role: FilesystemRole
            if device.deviceType == "rom" {
                role = .rom
            } else if device.removable {
                role = .usb
            } else {
                role = .disk
            }
            let name = device.label.isEmpty
                ? "\(device.mount) (\(device.name))"
                : "\(device.label) (\(device.name))"
            return FilesystemItem(id: device.mount, name: name, path: device.mount, role: role, hidden: false, size: nil)
        }
    }
}

// MARK: - Disk usage bar

public enum DiskUsageFormatter {
    /// Picks the mount that best contains `path` — the longest mount that is a
    /// true ancestor of the path (more specific than the legacy last-match-wins).
    /// Matches the exact mount or the mount followed by a separator, so a sibling
    /// whose name merely extends the mount (e.g. `/Volumes/x` vs a `/Vol` mount)
    /// is not falsely attributed.
    public static func select(disks: [DiskUsage], forPath path: String) -> DiskUsage? {
        disks
            .filter { disk in
                if path == disk.mount { return true }
                let prefix = disk.mount.hasSuffix("/") ? disk.mount : disk.mount + "/"
                return path.hasPrefix(prefix)
            }
            .max { $0.mount.count < $1.mount.count }
    }

    /// Shortens a long mount to ".../lastComponent"; mounts under 18 chars are
    /// shown in full (matches the legacy bar text).
    public static func displayMount(_ mount: String) -> String {
        guard mount.count >= 18 else { return mount }
        let last = mount.split(separator: "/").last.map(String.init) ?? ""
        return ".../\(last)"
    }

    public static func percent(_ disk: DiskUsage) -> Int {
        // Guard the cast: a non-finite or out-of-range usePct (the public
        // initializer permits one) would otherwise crash `Int(_:)`. The strict
        // upper bound matters because Double(Int.max) rounds up past Int.max.
        guard disk.usePct.isFinite,
              disk.usePct >= Double(Int.min),
              disk.usePct < Double(Int.max) else {
            return 0
        }
        return Int(disk.usePct.rounded())
    }
}

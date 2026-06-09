import XCTest
@testable import EdexDomainSupport

final class NativeFilesystemTests: XCTestCase {

    // MARK: - FilesystemFormatter.formatBytes (mirrors JS _formatBytes)

    func testFormatBytesZero() {
        XCTAssertEqual(FilesystemFormatter.formatBytes(0), "0 Bytes")
    }

    func testFormatBytesUnderOneKB() {
        XCTAssertEqual(FilesystemFormatter.formatBytes(512), "512 Bytes")
        XCTAssertEqual(FilesystemFormatter.formatBytes(1023), "1023 Bytes")
    }

    func testFormatBytesExactKB() {
        // 1024 → "1 KB" (toFixed(2) then parseFloat strips trailing zeros).
        XCTAssertEqual(FilesystemFormatter.formatBytes(1024), "1 KB")
    }

    func testFormatBytesFractionalKB() {
        XCTAssertEqual(FilesystemFormatter.formatBytes(1536), "1.5 KB")
    }

    func testFormatBytesMB() {
        XCTAssertEqual(FilesystemFormatter.formatBytes(1_048_576), "1 MB")
    }

    func testFormatBytesGB() {
        XCTAssertEqual(FilesystemFormatter.formatBytes(1_073_741_824), "1 GB")
    }

    // MARK: - PathUtils

    func testPathJoinCollapsesSlashes() {
        XCTAssertEqual(PathUtils.join(["/Users", "foo", "bar"]), "/Users/foo/bar")
        XCTAssertEqual(PathUtils.join(["/Users/", "/foo/", "bar"]), "/Users/foo/bar")
    }

    func testPathJoinSkipsEmpty() {
        XCTAssertEqual(PathUtils.join(["/a", "", "b"]), "/a/b")
    }

    func testPathResolveSimple() {
        XCTAssertEqual(PathUtils.resolve("/Users/foo", "bar"), "/Users/foo/bar")
    }

    func testPathResolveParent() {
        XCTAssertEqual(PathUtils.resolve("/Users/foo/bar", ".."), "/Users/foo")
    }

    func testPathResolveCurrentAndParent() {
        XCTAssertEqual(PathUtils.resolve("/Users/foo", "./bar/../baz"), "/Users/foo/baz")
    }

    func testPathResolveAboveRootStaysAtRoot() {
        XCTAssertEqual(PathUtils.resolve("/", ".."), "/")
    }

    func testBasename() {
        XCTAssertEqual(PathUtils.basename("/Users/foo/bar.txt"), "bar.txt")
        XCTAssertEqual(PathUtils.basename("/Users/foo/"), "foo")
        XCTAssertEqual(PathUtils.basename("/"), "")
    }

    func testParent() {
        XCTAssertEqual(PathUtils.parent("/Users/foo/bar"), "/Users/foo")
        XCTAssertEqual(PathUtils.parent("/"), "/")
    }

    // MARK: - FileTypeDetector

    func testIsTextFile() {
        XCTAssertTrue(FileTypeDetector.isText(name: "notes.txt"))
        XCTAssertTrue(FileTypeDetector.isText(name: "config.json"))
        XCTAssertTrue(FileTypeDetector.isText(name: "README.md"))
        XCTAssertTrue(FileTypeDetector.isText(name: "main.rs"))
        XCTAssertFalse(FileTypeDetector.isText(name: "photo.png"))
        XCTAssertFalse(FileTypeDetector.isText(name: "clip.mp4"))
        XCTAssertFalse(FileTypeDetector.isText(name: "noextension"))
    }

    func testMediaKind() {
        XCTAssertEqual(FileTypeDetector.mediaKind(name: "photo.PNG"), .image)
        XCTAssertEqual(FileTypeDetector.mediaKind(name: "song.mp3"), .audio)
        XCTAssertEqual(FileTypeDetector.mediaKind(name: "movie.mov"), .video)
        XCTAssertNil(FileTypeDetector.mediaKind(name: "notes.txt"))
    }

    func testIsPdf() {
        XCTAssertTrue(FileTypeDetector.isPdf(name: "doc.pdf"))
        XCTAssertFalse(FileTypeDetector.isPdf(name: "doc.txt"))
    }

    // MARK: - FilesystemEntry

    func testEntryKindFromCategory() {
        XCTAssertEqual(FilesystemEntry(name: "a", category: "dir", hidden: false, size: 0).kind, .directory)
        XCTAssertEqual(FilesystemEntry(name: "b", category: "symlink", hidden: false, size: 0).kind, .symlink)
        XCTAssertEqual(FilesystemEntry(name: "c", category: "file", hidden: false, size: 4).kind, .file)
        XCTAssertEqual(FilesystemEntry(name: "d", category: "weird", hidden: false, size: 0).kind, .other)
    }

    // MARK: - FilesystemListBuilder

    private func sampleEntries() -> [FilesystemEntry] {
        [
            FilesystemEntry(name: "zebra.txt", category: "file", hidden: false, size: 10),
            FilesystemEntry(name: "alpha", category: "dir", hidden: false, size: 0),
            FilesystemEntry(name: "link", category: "symlink", hidden: false, size: 0),
            FilesystemEntry(name: "beta.txt", category: "file", hidden: false, size: 20),
            FilesystemEntry(name: ".hidden", category: "file", hidden: true, size: 5)
        ]
    }

    func testBuilderSortsDirsThenSymlinksThenFiles() {
        let items = FilesystemListBuilder.items(
            entries: sampleEntries(),
            path: "/Users/foo",
            context: .none
        )
        // First two are the special rows.
        let names = items.dropFirst(2).map(\.name)
        XCTAssertEqual(names, ["alpha", "link", ".hidden", "beta.txt", "zebra.txt"])
    }

    func testBuilderPrependsShowDisksAndGoUp() {
        let items = FilesystemListBuilder.items(
            entries: sampleEntries(),
            path: "/Users/foo",
            context: .none
        )
        XCTAssertEqual(items[0].role, .showDisks)
        XCTAssertEqual(items[1].role, .goUp)
    }

    func testBuilderOmitsGoUpAtRoot() {
        let items = FilesystemListBuilder.items(
            entries: sampleEntries(),
            path: "/",
            context: .none
        )
        XCTAssertEqual(items[0].role, .showDisks)
        XCTAssertNotEqual(items[1].role, .goUp)
    }

    func testBuilderResolvesPaths() {
        let items = FilesystemListBuilder.items(
            entries: [FilesystemEntry(name: "alpha", category: "dir", hidden: false, size: 0)],
            path: "/Users/foo",
            context: .none
        )
        let alpha = items.first { $0.name == "alpha" }
        XCTAssertEqual(alpha?.path, "/Users/foo/alpha")
    }

    func testBuilderPreservesHiddenFlag() {
        let items = FilesystemListBuilder.items(
            entries: sampleEntries(),
            path: "/Users/foo",
            context: .none
        )
        let hidden = items.first { $0.name == ".hidden" }
        XCTAssertEqual(hidden?.hidden, true)
    }

    func testBuilderTagsSpecialUserdataItems() {
        let context = FilesystemContext(
            userDataDir: "/data",
            themesDir: "/data/themes",
            keyboardsDir: "/data/keyboards"
        )
        let entries = [
            FilesystemEntry(name: "themes", category: "dir", hidden: false, size: 0),
            FilesystemEntry(name: "keyboards", category: "dir", hidden: false, size: 0),
            FilesystemEntry(name: "settings.json", category: "file", hidden: false, size: 100),
            FilesystemEntry(name: "shortcuts.json", category: "file", hidden: false, size: 50)
        ]
        let items = FilesystemListBuilder.items(entries: entries, path: "/data", context: context)
        XCTAssertEqual(items.first { $0.name == "themes" }?.role, .themesDir)
        XCTAssertEqual(items.first { $0.name == "keyboards" }?.role, .keyboardsDir)
        XCTAssertEqual(items.first { $0.name == "settings.json" }?.role, .settingsFile)
        XCTAssertEqual(items.first { $0.name == "shortcuts.json" }?.role, .shortcutsFile)
    }

    func testBuilderTagsThemeAndKeyboardFiles() {
        let context = FilesystemContext(
            userDataDir: "/data",
            themesDir: "/data/themes",
            keyboardsDir: "/data/keyboards"
        )
        let themeItems = FilesystemListBuilder.items(
            entries: [FilesystemEntry(name: "tron.json", category: "file", hidden: false, size: 100)],
            path: "/data/themes",
            context: context
        )
        XCTAssertEqual(themeItems.first { $0.name == "tron.json" }?.role, .themeFile)

        let kbItems = FilesystemListBuilder.items(
            entries: [FilesystemEntry(name: "en-US.json", category: "file", hidden: false, size: 100)],
            path: "/data/keyboards",
            context: context
        )
        XCTAssertEqual(kbItems.first { $0.name == "en-US.json" }?.role, .keyboardFile)
    }

    func testItemSizeText() {
        let fileItem = FilesystemItem(
            id: "/a/b.txt", name: "b.txt", path: "/a/b.txt",
            role: .file, hidden: false, size: 1024
        )
        XCTAssertEqual(fileItem.sizeText, "1 KB")

        let dirItem = FilesystemItem(
            id: "/a/dir", name: "dir", path: "/a/dir",
            role: .directory, hidden: false, size: nil
        )
        XCTAssertEqual(dirItem.sizeText, "--")
    }

    // MARK: - Disk view items

    func testDiskItemsClassifyTypes() {
        let devices = [
            DiskDevice(name: "disk0s1", deviceType: "disk", mount: "/", removable: false, label: "Macintosh HD"),
            DiskDevice(name: "disk2s1", deviceType: "rom", mount: "/Volumes/CD", removable: true, label: ""),
            DiskDevice(name: "disk3s1", deviceType: "disk", mount: "/Volumes/USB", removable: true, label: "MyStick")
        ]
        let items = FilesystemListBuilder.diskItems(devices: devices)
        XCTAssertEqual(items.first { $0.path == "/" }?.role, .disk)
        XCTAssertEqual(items.first { $0.path == "/Volumes/CD" }?.role, .rom)
        XCTAssertEqual(items.first { $0.path == "/Volumes/USB" }?.role, .usb)
    }

    func testDiskItemNameUsesLabelWhenPresent() {
        let withLabel = DiskDevice(name: "disk0s1", deviceType: "disk", mount: "/", removable: false, label: "Macintosh HD")
        let noLabel = DiskDevice(name: "disk1s1", deviceType: "disk", mount: "/Volumes/X", removable: false, label: "")
        let items = FilesystemListBuilder.diskItems(devices: [withLabel, noLabel])
        XCTAssertEqual(items.first { $0.path == "/" }?.name, "Macintosh HD (disk0s1)")
        XCTAssertEqual(items.first { $0.path == "/Volumes/X" }?.name, "/Volumes/X (disk1s1)")
    }

    // MARK: - DiskUsageFormatter

    func testDiskUsageSelectsLongestMatchingMount() {
        let disks = [
            DiskUsage(mount: "/", usePct: 40),
            DiskUsage(mount: "/Volumes/Data", usePct: 75)
        ]
        let selected = DiskUsageFormatter.select(disks: disks, forPath: "/Volumes/Data/projects")
        XCTAssertEqual(selected?.mount, "/Volumes/Data")
    }

    func testDiskUsageFallsBackToRoot() {
        let disks = [
            DiskUsage(mount: "/", usePct: 40),
            DiskUsage(mount: "/Volumes/Data", usePct: 75)
        ]
        let selected = DiskUsageFormatter.select(disks: disks, forPath: "/Users/foo")
        XCTAssertEqual(selected?.mount, "/")
    }

    func testDiskUsageDisplayMountShort() {
        XCTAssertEqual(DiskUsageFormatter.displayMount("/"), "/")
        XCTAssertEqual(DiskUsageFormatter.displayMount("/Volumes/Data"), "/Volumes/Data")
    }

    func testDiskUsageDisplayMountTruncatesLong() {
        // length >= 18 → ".../" + last component
        XCTAssertEqual(
            DiskUsageFormatter.displayMount("/Volumes/SomeVeryLongDriveName"),
            ".../SomeVeryLongDriveName"
        )
    }

    func testDiskUsagePercent() {
        XCTAssertEqual(DiskUsageFormatter.percent(DiskUsage(mount: "/", usePct: 42.7)), 43)
    }

    func testDiskUsageDoesNotFalsePrefixMatch() {
        // "/Volumes/x" must NOT be attributed to a "/Vol" mount just because the
        // string shares a prefix; it should fall back to the root mount.
        let disks = [
            DiskUsage(mount: "/", usePct: 10),
            DiskUsage(mount: "/Vol", usePct: 90)
        ]
        let selected = DiskUsageFormatter.select(disks: disks, forPath: "/Volumes/x")
        XCTAssertEqual(selected?.mount, "/")
    }

    func testDiskUsageExactMountMatches() {
        let disks = [DiskUsage(mount: "/Volumes/Data", usePct: 55)]
        XCTAssertEqual(
            DiskUsageFormatter.select(disks: disks, forPath: "/Volumes/Data")?.mount,
            "/Volumes/Data"
        )
    }

    func testDiskUsagePercentHandlesNonFinite() {
        XCTAssertEqual(DiskUsageFormatter.percent(DiskUsage(mount: "/", usePct: .nan)), 0)
        XCTAssertEqual(DiskUsageFormatter.percent(DiskUsage(mount: "/", usePct: .infinity)), 0)
    }
}

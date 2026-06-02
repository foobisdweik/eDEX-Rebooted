// swift-tools-version: 6.0
import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let repoRoot = URL(fileURLWithPath: packageDirectory)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .path
let rustReleaseDirectory = "\(repoRoot)/crates/edex-ffi/target/release"
let generatedDirectory = "\(packageDirectory)/Generated"

let package = Package(
    name: "eDEXNative",
    platforms: [
        // Tahoe is the target for the migration. The current shell uses APIs
        // that are available earlier, so keep the SwiftPM floor conservative
        // while running the spike on current Apple-Silicon macOS.
        .macOS(.v15)
    ],
    products: [
        .executable(name: "eDEXNative", targets: ["eDEXNative"])
    ],
    targets: [
        .target(
            name: "LayoutSupport",
            path: "Sources/LayoutSupport"
        ),
        .target(
            name: "BorderSupport",
            path: "Sources/BorderSupport"
        ),
        .target(
            name: "ClockSupport",
            path: "Sources/ClockSupport"
        ),
        .target(
            name: "SysinfoSupport",
            path: "Sources/SysinfoSupport"
        ),
        .target(
            name: "HardwareSupport",
            path: "Sources/HardwareSupport"
        ),
        .target(
            name: "KeyboardSupport",
            path: "Sources/KeyboardSupport"
        ),
        .target(
            name: "CpuinfoSupport",
            path: "Sources/CpuinfoSupport"
        ),
        .target(
            name: "RamwatcherSupport",
            path: "Sources/RamwatcherSupport"
        ),
        .target(
            name: "ToplistSupport",
            path: "Sources/ToplistSupport"
        ),
        .target(
            name: "SettingsEditorSupport",
            path: "Sources/SettingsEditorSupport"
        ),
        .target(
            name: "ShortcutsSupport",
            path: "Sources/ShortcutsSupport"
        ),
        .target(
            name: "BootSupport",
            path: "Sources/BootSupport"
        ),
        .target(
            name: "FilesystemSupport",
            path: "Sources/FilesystemSupport"
        ),
        .target(
            name: "FuzzyFinderSupport",
            dependencies: ["FilesystemSupport"],
            path: "Sources/FuzzyFinderSupport"
        ),
        .target(
            name: "TextEditorSupport",
            dependencies: ["FilesystemSupport"],
            path: "Sources/TextEditorSupport"
        ),
        .target(
            name: "AudioSupport",
            path: "Sources/AudioSupport"
        ),
        .target(
            name: "ModalSupport",
            dependencies: ["AudioSupport"],
            path: "Sources/ModalSupport"
        ),
        .target(
            name: "ThemeSupport",
            path: "Sources/ThemeSupport"
        ),
        .executableTarget(
            name: "eDEXNative",
            dependencies: ["AudioSupport", "BootSupport", "BorderSupport", "ClockSupport", "CpuinfoSupport", "FilesystemSupport", "FuzzyFinderSupport", "HardwareSupport", "KeyboardSupport", "LayoutSupport", "ModalSupport", "RamwatcherSupport", "SettingsEditorSupport", "ShortcutsSupport", "SysinfoSupport", "TextEditorSupport", "ThemeSupport", "ToplistSupport"],
            path: ".",
            exclude: [
                "README.md",
                "Scripts",
                "Sources/AudioSupport",
                "Sources/BootSupport",
                "Sources/BorderSupport",
                "Sources/ClockSupport",
                "Sources/CpuinfoSupport",
                "Sources/FilesystemSupport",
                "Sources/FuzzyFinderSupport",
                "Sources/HardwareSupport",
                "Sources/KeyboardSupport",
                "Sources/LayoutSupport",
                "Sources/ModalSupport",
                "Sources/RamwatcherSupport",
                "Sources/SettingsEditorSupport",
                "Sources/ShortcutsSupport",
                "Sources/SysinfoSupport",
                "Sources/TextEditorSupport",
                "Sources/ThemeSupport",
                "Sources/ToplistSupport",
                "Tests"
            ],
            sources: [
                "Sources/App",
                "Sources/Services",
                "Sources/Stores",
                "Sources/Support",
                "Sources/Views",
                "Generated/edex_ffi.swift"
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-I", generatedDirectory,
                    "-Xcc", "-fmodule-map-file=\(generatedDirectory)/edex_ffiFFI.modulemap"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", rustReleaseDirectory,
                    "-ledex_ffi",
                    "-Xlinker", "-rpath",
                    "-Xlinker", rustReleaseDirectory
                ])
            ]
        ),
        .testTarget(
            name: "eDEXNativeTests",
            dependencies: ["AudioSupport", "BootSupport", "BorderSupport", "ClockSupport", "CpuinfoSupport", "FilesystemSupport", "FuzzyFinderSupport", "HardwareSupport", "KeyboardSupport", "LayoutSupport", "ModalSupport", "RamwatcherSupport", "SettingsEditorSupport", "ShortcutsSupport", "SysinfoSupport", "TextEditorSupport", "ThemeSupport", "ToplistSupport"],
            path: "Tests"
        )
    ],
    swiftLanguageModes: [.v5]
)

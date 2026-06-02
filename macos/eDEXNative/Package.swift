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
            name: "CpuinfoSupport",
            path: "Sources/CpuinfoSupport"
        ),
        .target(
            name: "RamwatcherSupport",
            path: "Sources/RamwatcherSupport"
        ),
        .target(
            name: "AudioSupport",
            path: "Sources/AudioSupport"
        ),
        .target(
            name: "ThemeSupport",
            path: "Sources/ThemeSupport"
        ),
        .executableTarget(
            name: "eDEXNative",
            dependencies: ["AudioSupport", "BorderSupport", "ClockSupport", "CpuinfoSupport", "HardwareSupport", "LayoutSupport", "RamwatcherSupport", "SysinfoSupport", "ThemeSupport"],
            path: ".",
            exclude: [
                "README.md",
                "Scripts",
                "Sources/AudioSupport",
                "Sources/BorderSupport",
                "Sources/ClockSupport",
                "Sources/CpuinfoSupport",
                "Sources/HardwareSupport",
                "Sources/LayoutSupport",
                "Sources/RamwatcherSupport",
                "Sources/SysinfoSupport",
                "Sources/ThemeSupport",
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
            dependencies: ["AudioSupport", "BorderSupport", "ClockSupport", "CpuinfoSupport", "HardwareSupport", "LayoutSupport", "RamwatcherSupport", "SysinfoSupport", "ThemeSupport"],
            path: "Tests"
        )
    ],
    swiftLanguageModes: [.v5]
)

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
            name: "EdexCoreBridge",
            path: "Generated",
            sources: [
                "edex_ffi.swift"
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
        .target(
            name: "EdexDomainSupport",
            path: "Sources/EdexDomainSupport"
        ),
        .target(
            name: "EdexRenderingSupport",
            path: "Sources/EdexRenderingSupport"
        ),
        .executableTarget(
            name: "eDEXNative",
            dependencies: [
                "EdexCoreBridge",
                "EdexDomainSupport",
                "EdexRenderingSupport"
            ],
            path: ".",
            exclude: [
                "AGENTS.md",
                "README.md",
                "Scripts",
                "Generated",
                "Sources/EdexDomainSupport",
                "Sources/EdexRenderingSupport",
                "Tests"
            ],
            sources: [
                "Sources/App",
                "Sources/Services",
                "Sources/Stores",
                "Sources/Support",
                "Sources/Views"
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-I", generatedDirectory,
                    "-Xcc", "-fmodule-map-file=\(generatedDirectory)/edex_ffiFFI.modulemap"
                ])
            ]
        ),
        .testTarget(
            name: "eDEXNativeTests",
            dependencies: [
                "EdexDomainSupport",
                "EdexRenderingSupport"
            ],
            path: "Tests"
        )
    ],
    swiftLanguageModes: [.v5]
)

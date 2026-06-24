// swift-tools-version: 6.4
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
        // macOS 27 floor: the HDR/EDR GPU-rendering arc requires the Metal 4.1
        // baseline and the macOS-27 EDR/Metal host APIs. `.v27` is the verified
        // SupportedPlatform symbol in the Xcode 27 PackageDescription.
        .macOS(.v27)
    ],
    products: [
        .executable(name: "eDEXNative", targets: ["eDEXNative"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0")
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
                "EdexRenderingSupport",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: ".",
            exclude: [
                "AGENTS.md",
                "README.md",
                "Scripts",
                "Generated",
                "Sources/EdexDomainSupport",
                "Sources/EdexRenderingSupport",
                // `.metal` source is compiled offline (Scripts/build-shaders.sh)
                // into the bundled `default.metallib`; excluded so SwiftPM does
                // not attempt to compile it (no runtime shader compilation).
                "Sources/Shaders/default.metal",
                "Tests"
            ],
            sources: [
                "Sources/App",
                "Sources/Services",
                "Sources/Stores",
                "Sources/Support",
                "Sources/Views"
            ],
            resources: [
                .process("Sources/Shaders/default.metallib")
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

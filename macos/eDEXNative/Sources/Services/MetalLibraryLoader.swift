import Foundation
import Metal
import EdexRenderingSupport

/// Smoke-check plumbing: proves the precompiled-`.metallib` delivery path works
/// end to end — the offline-built `default.metallib` (bundled with
/// `EdexRenderingSupport`) loads via `makeDefaultLibrary(bundle:)` with no runtime
/// shader compilation, and exposes the aesthetic shader's entry points (Spike C).
enum MetalLibraryLoader {
    /// The aesthetic fragment function compiled into `default.metallib`. Asserting
    /// its presence confirms the loaded library is the real, current one.
    static let requiredFunctionName = AestheticMetalLibrary.fragmentFunctionName

    enum LoadResult: Equatable {
        /// No Metal device (e.g. a headless CI VM). Not a failure — there is
        /// nothing to load against, and the smoke check must not gate on a GPU.
        case unavailable
        case loaded(functionNames: [String])
        case failed(reason: String)
    }

    /// Loads the bundled `default.metallib` from `EdexRenderingSupport`'s resource
    /// bundle. Never throws; callers inspect the `LoadResult`.
    static func loadDefaultLibrary() -> LoadResult {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return .unavailable
        }
        do {
            let library = try AestheticMetalLibrary.makeLibrary(device: device)
            let functionNames = library.functionNames
            // Finding *a* default.metallib is not enough: a stale or wrong library
            // would still load. Assert the offline-compiled aesthetic fragment is
            // actually present so the smoke check verifies the delivery path.
            guard functionNames.contains(requiredFunctionName) else {
                return .failed(
                    reason: "default.metallib is missing \(requiredFunctionName); found \(functionNames)"
                )
            }
            return .loaded(functionNames: functionNames)
        } catch {
            return .failed(reason: String(describing: error))
        }
    }
}

import Foundation
import Metal

/// Spike 0 plumbing: proves the precompiled-`.metallib` delivery path works end
/// to end — the offline-built `default.metallib` is bundled as a package
/// resource and loads via `makeDefaultLibrary(bundle:)` with no runtime shader
/// compilation. It is otherwise inert; real shaders arrive in Spike C.
enum MetalLibraryLoader {
    /// The placeholder fragment function compiled into `default.metallib`.
    /// Used only to confirm the loaded library exposes its functions.
    static let placeholderFunctionName = "edexPlaceholderFragment"

    enum LoadResult: Equatable {
        /// No Metal device (e.g. a headless CI VM). Not a failure — there is
        /// nothing to load against, and Spike 0 must not gate CI on a GPU.
        case unavailable
        case loaded(functionNames: [String])
        case failed(reason: String)
    }

    /// Loads the bundled `default.metallib` from the executable target's resource
    /// bundle. Never throws; callers inspect the `LoadResult`.
    static func loadDefaultLibrary() -> LoadResult {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return .unavailable
        }
        do {
            let library = try device.makeDefaultLibrary(bundle: .module)
            let functionNames = library.functionNames
            // Finding *a* default.metallib is not enough: a stale or wrong
            // library would still load. Assert the offline-compiled placeholder
            // function is actually present so the smoke check verifies the
            // delivery path end to end.
            guard functionNames.contains(placeholderFunctionName) else {
                return .failed(
                    reason: "default.metallib is missing \(placeholderFunctionName); found \(functionNames)"
                )
            }
            return .loaded(functionNames: functionNames)
        } catch {
            return .failed(reason: String(describing: error))
        }
    }
}

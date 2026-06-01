import AppKit

enum WindowChrome {
    private static let aspectRatio = NSSize(width: 16.0, height: 10.0)

    @MainActor
    static func configure(_ window: NSWindow, keepGeometry: Bool) {
        window.title = "eDEX Native"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isMovableByWindowBackground = true

        // Match src-tauri/src/window_chrome.rs: keepGeometry controls the
        // content-area aspect lock. NSZeroSize clears the live resize ratio.
        window.contentAspectRatio = keepGeometry ? aspectRatio : .zero

        // The standard titled/resizable/closable masks remain intact, so
        // windowed mode keeps normal traffic-light controls.
        if CommandLine.arguments.contains("--smoke-window") {
            print("eDEXNative window chrome OK transparentTitlebar=true trafficLights=standard contentAspect=\(keepGeometry ? "16:10" : "freeform")")
        }
    }
}

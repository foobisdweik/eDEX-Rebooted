import SwiftUI

@main
struct EDEXNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var shellState = ShellState()

    var body: some Scene {
        WindowGroup("eDEX Native") {
            ContentView(state: shellState)
                .frame(minWidth: 960, minHeight: 600)
                .background(WindowAccessor(keepGeometry: shellState.keepGeometry) { window, keepGeometry in
                    WindowChrome.configure(window, keepGeometry: keepGeometry)
                    appDelegate.registerMainWindow(window)
                })
                .task {
                    await shellState.bootstrap()
                }
        }
        .commands {
            CommandGroup(after: .windowSize) {
                Button("Toggle Full Screen") {
                    appDelegate.toggleFullScreen()
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var mainWindow: NSWindow?
    private var f11Monitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if CommandLine.arguments.contains("--smoke-window") {
            print("eDEXNative window smoke: app launched; waiting for FFI bootstrap")
            switch MetalLibraryLoader.loadDefaultLibrary() {
            case .unavailable:
                print("eDEXNative metallib smoke: no Metal device (headless); skipping load check")
            case let .loaded(functionNames):
                print("eDEXNative metallib smoke: default.metallib loaded; functions=\(functionNames)")
            case let .failed(reason):
                // Hard-fail the smoke run (non-zero exit) so a broken metallib
                // delivery path cannot pass verification silently.
                fatalError("eDEXNative metallib smoke: FAILED to load default.metallib: \(reason)")
            }
        }

        f11Monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // F11's hardware key code is 103. This mirrors the Tauri shell's
            // windowed/fullscreen toggle without involving the old frontend.
            if event.keyCode == 103 {
                self?.toggleFullScreen()
                return nil
            }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let f11Monitor {
            NSEvent.removeMonitor(f11Monitor)
        }
    }

    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
    }

    func toggleFullScreen() {
        (NSApp.keyWindow ?? NSApp.mainWindow ?? mainWindow)?.toggleFullScreen(nil)
    }
}

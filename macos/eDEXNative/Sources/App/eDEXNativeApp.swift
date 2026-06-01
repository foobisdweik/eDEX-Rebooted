import SwiftUI

@main
struct EDEXNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var shellState = ShellState()

    var body: some Scene {
        WindowGroup("eDEX Native") {
            ContentView(state: shellState)
                .frame(minWidth: 960, minHeight: 600)
                .background(WindowAccessor { window in
                    WindowChrome.configure(window, keepGeometry: shellState.keepGeometry)
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

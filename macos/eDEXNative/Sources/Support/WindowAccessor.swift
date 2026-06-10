import AppKit
import SwiftUI

/// Resolves the hosting `NSWindow` and configures it **idempotently**
/// (Finding #6). The old version fired `onResolve` on every `updateNSView`,
/// re-running `WindowChrome.configure(...)` on each SwiftUI update even when
/// nothing relevant changed. Now a coordinator remembers the last window and
/// the last `keepGeometry` it configured for, so `onConfigure` runs only when
/// the window identity or `keepGeometry` actually changes.
struct WindowAccessor: NSViewRepresentable {
    var keepGeometry: Bool
    var onConfigure: (NSWindow, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var lastWindow: NSWindow?
        var lastKeepGeometry: Bool?
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureIfNeeded(view, context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureIfNeeded(nsView, context.coordinator)
    }

    private func configureIfNeeded(_ view: NSView, _ coordinator: Coordinator) {
        // Synchronous fast path: `updateNSView` runs on the main thread, so when
        // the window is already attached and nothing changed we can bail without
        // scheduling a main-queue closure on every SwiftUI update. The async
        // branch remains for the case where the window isn't resolved yet.
        if let window = view.window,
           coordinator.lastWindow === window,
           coordinator.lastKeepGeometry == keepGeometry {
            return
        }
        let keepGeometry = self.keepGeometry
        let onConfigure = self.onConfigure
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            let unchanged = coordinator.lastWindow === window
                && coordinator.lastKeepGeometry == keepGeometry
            guard !unchanged else { return }
            coordinator.lastWindow = window
            coordinator.lastKeepGeometry = keepGeometry
            onConfigure(window, keepGeometry)
        }
    }
}

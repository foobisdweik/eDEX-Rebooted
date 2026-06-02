import AppKit
import Darwin
import Foundation
import Observation
import SwiftUI
import ThemeSupport

@Observable
@MainActor
final class ShellState {
    private let client = EdexCoreClient()

    var statusText = "booting"
    var paths: FfiPaths?
    var settingsSummary = SettingsSummary()
    var keepGeometry = true
    var theme = NativeTheme.fallback

    func bootstrap() async {
        do {
            let snapshot = try client.bootstrap()
            paths = snapshot.paths
            settingsSummary = snapshot.settings
            keepGeometry = snapshot.settings.keepGeometry
            theme = snapshot.theme
            statusText = "ok — EdexCore.paths(), ensureUserdata(), loadSettingsJson(), loadThemeJson() returned"
            print("eDEXNative FFI OK userData=\(snapshot.paths.userData) settingsBytes=\(snapshot.settings.byteCount ?? 0) theme=\(snapshot.settings.theme) keepGeometry=\(snapshot.settings.keepGeometry)")
            terminateIfSmokeWindow()
        } catch {
            statusText = "error — \(error.localizedDescription)"
            print("eDEXNative FFI ERROR \(error.localizedDescription)")
            terminateIfSmokeWindow()
        }
    }

    private func terminateIfSmokeWindow() {
        guard CommandLine.arguments.contains("--smoke-window") else { return }
        DispatchQueue.main.async {
            print("eDEXNative window smoke: bootstrap complete; terminating")
            NSApp.terminate(nil)
            Darwin.exit(0)
        }
    }
}

struct SettingsSummary: Sendable {
    var theme = "pending"
    var keepGeometry = true
    var byteCount: Int?
}

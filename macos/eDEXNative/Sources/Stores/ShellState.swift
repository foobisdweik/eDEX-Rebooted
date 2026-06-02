import AppKit
import CpuinfoSupport
import Darwin
import Foundation
import HardwareSupport
import Observation
import SwiftUI
import SysinfoSupport
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
    var uptimeSeconds: UInt64 = 0
    var battery: FfiBattery?
    var hardware: FfiHardware?
    var cpu: FfiCpuSnapshot?
    /// Timestamp of the last appended CPU sample; the graph interpolates its
    /// horizontal scroll against this so motion is smooth between 1 Hz samples.
    var cpuLastSampleDate = Date()
    private var cpuBuffer = CpuSeriesBuffer(coreCount: 0, capacity: cpuSampleCapacity)
    /// Per-core CPU load history feeding the two scrolling graphs.
    var cpuSeries: [[Double]] { cpuBuffer.series }
    private static let cpuSampleCapacity = 64

    /// Bridges the FFI battery record into the FFI-free `SysinfoSupport` input.
    /// Falls back to a wired/no-battery state (POWER → "ON") before the first poll.
    var powerState: EdexPowerState {
        guard let battery else {
            return EdexPowerState(hasBattery: false, isCharging: false, acConnected: true, percent: 0)
        }
        return EdexPowerState(
            hasBattery: battery.hasBattery,
            isCharging: battery.isCharging,
            acConnected: battery.acConnected,
            percent: Int(battery.percent)
        )
    }

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

    /// Pulls uptime + battery from the Rust core for the sysinfo panel. The
    /// battery query hits IOKit (a few ms), so the FFI calls are offloaded to a
    /// background task to keep the main thread free; results land back on the
    /// MainActor. The panel polls this on a timer (see ContentView).
    func refreshSysinfo() async {
        let client = self.client
        let (uptime, battery) = await Task.detached(priority: .background) {
            (client.uptimeSeconds(), client.battery())
        }.value
        uptimeSeconds = uptime
        self.battery = battery
    }

    /// Pulls host hardware identity from the Rust core for the hardware-inspector
    /// panel. Offloaded off the MainActor like `refreshSysinfo()`. The data is
    /// effectively static at runtime; the panel re-polls on the legacy 20s cadence.
    func refreshHardware() async {
        let client = self.client
        hardware = await Task.detached(priority: .background) {
            client.hardware()
        }.value
    }

    /// Pulls a fresh CPU snapshot for the cpuinfo panel, appends it to the
    /// per-core sample buffer, and stamps the sample time. The FFI call (a full
    /// system refresh) is offloaded off the MainActor; the panel polls 1 Hz.
    func refreshCpu() async {
        let client = self.client
        guard let snapshot = await Task.detached(priority: .background, operation: {
            client.cpuSnapshot()
        }).value else { return }

        if cpuBuffer.coreCount != Int(snapshot.cores) {
            cpuBuffer = CpuSeriesBuffer(coreCount: Int(snapshot.cores), capacity: Self.cpuSampleCapacity)
        }
        cpuBuffer.append(loads: snapshot.loads)
        cpuLastSampleDate = Date()
        cpu = snapshot
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
    var clockHours = 24
    var byteCount: Int?
}

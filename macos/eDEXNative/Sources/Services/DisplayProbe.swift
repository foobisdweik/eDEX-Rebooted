import AppKit
import EdexRenderingSupport

/// Spike B — the live-display half of the color/brightness platform.
///
/// Reads a screen's EDR triad and resolves it against the selected
/// `BrightnessProfile` into a `DisplayHeadroom`. `NSScreen`'s EDR properties are
/// MainActor-bound AppKit reads, so the raw read happens on the MainActor here;
/// the resolution (`DisplayHeadroom.init`) is pure, non-blocking math, so unlike
/// the FFI/IOKit reads in `ShellState.refreshSysinfo()` there is nothing heavy to
/// detach — forcing a `Task.detached` would only mean smuggling a non-Sendable
/// `NSScreen` across an actor boundary, which is exactly what the read-on-Main
/// discipline forbids.
@MainActor
enum DisplayProbe {
    /// Resolve live headroom for `profile` off the given screen (defaulting to the
    /// main screen). Returns `.sdr` when there is no screen (headless / detached
    /// session) so the render path falls back cleanly to the SDR surface.
    static func headroom(
        profile: BrightnessProfile,
        screen: NSScreen? = nil
    ) -> DisplayHeadroom {
        guard let screen = screen ?? NSScreen.main else { return .sdr }
        return DisplayHeadroom(
            profile: profile,
            maximumEDR: Double(screen.maximumExtendedDynamicRangeColorComponentValue),
            maximumPotentialEDR: Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue),
            maximumReferenceEDR: Double(screen.maximumReferenceExtendedDynamicRangeColorComponentValue)
        )
    }
}

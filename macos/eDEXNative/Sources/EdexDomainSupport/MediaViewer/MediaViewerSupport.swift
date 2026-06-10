import Foundation

/// Pure logic for the native media viewer control bar — time formatting, seek
/// math, volume clamping, and control-glyph names — mirroring
/// `mediaPlayer.class.js`. FFI-free so it unit-tests without AVFoundation.
public enum MediaPlayerSupport: Sendable {

    /// Zero-padded `HH:MM:SS`, matching legacy `mediaTimeToHMS`.
    public static func timeHMS(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00:00" }
        let total = safeInt(seconds.rounded(.down)) ?? 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    /// Playback position as a 0…1 fraction; 0 when inputs are unusable.
    public static func progressFraction(current: Double, duration: Double) -> Double {
        guard current.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(max(current / duration, 0), 1)
    }

    /// Seek target in seconds from a normalized scrub fraction.
    public static func seekTime(fraction: Double, duration: Double) -> Double {
        guard fraction.isFinite, duration.isFinite, duration > 0 else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        return clamped * duration
    }

    /// Volume slider value clamped to 0…1; non-finite input defaults to 1.
    public static func clampVolume(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, 0), 1)
    }

    /// Legacy `updateVolumeIcon`: mute glyph when muted or silent.
    public static func volumeIconName(volume: Double, muted: Bool) -> String {
        if muted || volume == 0 { return "mute" }
        return "volume"
    }

    /// Legacy `changeButtonState`: pause while playing, play otherwise.
    public static func playPauseIconName(isPlaying: Bool) -> String {
        isPlaying ? "pause" : "play"
    }

    private static func safeInt(_ value: Double) -> Int? {
        // `Int(exactly:)` is failable on non-finite, fractional, or
        // out-of-range input — unlike a bounds-checked trapping cast, where
        // `Double(Int.max)` rounding up to 2^63 leaks one trapping value.
        Int(exactly: value)
    }
}

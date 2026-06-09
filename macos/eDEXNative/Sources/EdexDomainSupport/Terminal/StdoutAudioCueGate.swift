import Foundation

/// Throttles the terminal stdout audio cue exactly like the legacy
/// `terminal.class.js`, which played `audioManager.stdout` on each PTY data
/// chunk but at most once per 30ms (`now - lastSoundFX > 30`) and never while
/// the on-screen keyboard is in password mode.
///
/// Pure and time-injected so the throttle can be exercised deterministically;
/// the live store stamps it with `Date()` on each drain.
public struct StdoutAudioCueGate: Sendable {
    /// Minimum gap between cues. Legacy used a strict `> 30ms` comparison.
    public let minimumInterval: TimeInterval
    private var lastFire: Date?

    public init(minimumInterval: TimeInterval = 0.030) {
        self.minimumInterval = minimumInterval
    }

    /// Whether the stdout cue should play for output observed at `now`.
    ///
    /// Matches the legacy ordering: the throttle window is evaluated first and
    /// the timestamp is stamped whenever it opens — even in password mode, where
    /// only the `play()` call was suppressed, not the stamp. So a normal poll
    /// arriving just after a password-mode poll stays throttled.
    public mutating func shouldPlay(at now: Date, passwordMode: Bool) -> Bool {
        if let lastFire, now.timeIntervalSince(lastFire) <= minimumInterval {
            return false
        }
        lastFire = now
        return !passwordMode
    }
}

/// The outcome of evaluating a freshly-observed terminal working directory
/// against the filesystem panel's follow state.
public enum TerminalCwdFollowDecision: Equatable, Sendable {
    /// The filesystem panel should navigate to (and start following) this path.
    case navigate(String)
    /// Leave the panel where it is.
    case ignore
}

/// Pure decision for whether the filesystem panel should follow the active
/// terminal's working directory.
///
/// Mirrors the legacy `followTab` in `filesystem.class.js`: the panel navigates
/// only when the cwd is present, the panel is not showing the block-device
/// ("Show disks") view, and the cwd differs from the one last followed. Comparing
/// against the *last followed* cwd — not the panel's current path — is what lets
/// the user browse away manually without being yanked back on every 1 Hz poll;
/// only a real `cd` in the active shell (which changes the cwd) re-navigates.
public enum TerminalCwdFollow {
    public static func decide(
        newCwd: String?,
        lastFollowedCwd: String?,
        isDiskView: Bool
    ) -> TerminalCwdFollowDecision {
        guard let cwd = newCwd, !cwd.isEmpty else { return .ignore }
        guard !isDiskView else { return .ignore }
        guard cwd != lastFollowedCwd else { return .ignore }
        return .navigate(cwd)
    }
}

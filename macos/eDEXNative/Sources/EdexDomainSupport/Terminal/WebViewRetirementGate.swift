import Foundation

/// Phase 9.7 manual burn-in scenarios that must pass on SwiftTerm before the
/// WKWebView frontend is deleted. Ordering matches
/// `docs/plans/phase-9-terminal-strategy-2026-06-08.md`.
public enum TerminalBurnInScenario: String, CaseIterable, Sendable, Hashable {
    case shell
    case vim
    case nano
    case top
    case htop
    case tmux
    case ssh
    case ansiColors
    case unicode
    case resize
    case scrollback
}

/// Native surfaces that must be owned before WKWebView retirement. Mirrors the
/// authoritative deletion gate in `full-native-swift-rust-conversion-2026-05-30.md`.
public enum NativeSurfaceReadiness: String, CaseIterable, Sendable, Hashable {
    case windowLifecycle
    case themeLoading
    case bootScreen
    case terminalDailyUse
    case terminalTabs
    case filesystemCwdFollow
    case keyboardInput
    case shortcuts
    case settingsEditor
    case modals
    case processListModal
    case audioCues
    case mediaViewer
}

/// Pure checklist for Phase 9.7 burn-in and WKWebView deletion readiness.
/// Manual smoke records pass/fail; CI exercises the aggregation rules only.
public struct WebViewRetirementGate: Equatable, Sendable {
    /// Surfaces intentionally deferred past 9.7 but waived for WKWebView removal.
    public static let waivedSurfaces: Set<NativeSurfaceReadiness> = [.mediaViewer]

    /// Surfaces that must be green (or waived) before `src/` can be deleted.
    public static let requiredSurfaces: Set<NativeSurfaceReadiness> = Set(
        NativeSurfaceReadiness.allCases.filter { !waivedSurfaces.contains($0) }
    )

    public private(set) var passedBurnIn: Set<TerminalBurnInScenario> = []
    public private(set) var skippedBurnIn: Set<TerminalBurnInScenario> = []
    public private(set) var passedSurfaces: Set<NativeSurfaceReadiness> = []

    public init() {}

    public mutating func recordBurnIn(_ scenario: TerminalBurnInScenario, passed: Bool) {
        skippedBurnIn.remove(scenario)
        if passed {
            passedBurnIn.insert(scenario)
        } else {
            passedBurnIn.remove(scenario)
        }
    }

    /// Records a scenario skipped because a local tool was unavailable during burn-in.
    public mutating func recordBurnInSkipped(_ scenario: TerminalBurnInScenario) {
        skippedBurnIn.insert(scenario)
        passedBurnIn.remove(scenario)
    }

    public mutating func recordSurface(_ surface: NativeSurfaceReadiness, passed: Bool) {
        if passed {
            passedSurfaces.insert(surface)
        } else {
            passedSurfaces.remove(surface)
        }
    }

    public var missingBurnIn: [TerminalBurnInScenario] {
        TerminalBurnInScenario.allCases.filter {
            !passedBurnIn.contains($0) && !skippedBurnIn.contains($0)
        }
    }

    public var missingSurfaces: [NativeSurfaceReadiness] {
        Self.requiredSurfaces
            .sorted { $0.rawValue < $1.rawValue }
            .filter { !passedSurfaces.contains($0) }
    }

    public var isBurnInComplete: Bool {
        missingBurnIn.isEmpty
    }

    public var isSurfaceGateComplete: Bool {
        missingSurfaces.isEmpty
    }

    public var isDeletionReady: Bool {
        isBurnInComplete && isSurfaceGateComplete
    }
}

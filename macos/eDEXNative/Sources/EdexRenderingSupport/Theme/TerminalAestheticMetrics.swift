import Foundation

/// Pure geometry for the eDEX terminal aesthetic overlay drawn over SwiftTerm:
/// faint CRT scanlines plus an accent glow. Mirrors the legacy CSS, which
/// expressed the terminal glow as `0 0 0.6vh rgba(accent, 0.6)` — radius and
/// alpha both scale with the viewport so the effect is resolution-independent.
///
/// All inputs are sanitized (the project crashes on non-finite `Double` math and
/// the Canvas loop must never run on a degenerate height), so callers can hand
/// raw layout values straight in.
public struct TerminalAestheticMetrics: Equatable, Sendable {
    /// Distance in points between scanline centers.
    public let scanlineSpacing: Double
    /// Stroke width of each scanline.
    public let scanlineThickness: Double
    /// Per-line alpha (kept low so text stays legible).
    public let scanlineOpacity: Double
    /// Blur radius of the accent glow.
    public let glowRadius: Double
    /// Alpha of the accent glow.
    public let glowOpacity: Double

    public init(surfaceHeight: Double, vh: Double, intensity: Double = 1.0) {
        let safeVh = (vh.isFinite && vh > 0) ? vh : 0
        let safeIntensity = intensity.isFinite ? max(0, intensity) : 1

        // Legacy `0.6vh` glow radius and 0.6 alpha, both scaled by intensity. A
        // zero radius (degenerate viewport) means no glow, so its alpha is 0 too.
        let radius = safeVh * 0.6 * safeIntensity
        glowRadius = radius
        glowOpacity = radius > 0 ? 0.6 * safeIntensity : 0
        // ~3pt scanlines at a 1000px viewport, with a 2pt floor so the lines
        // never collapse on small windows.
        scanlineSpacing = max(2.0, safeVh * 0.3)
        scanlineThickness = 1.0
        scanlineOpacity = 0.06 * safeIntensity
    }

    /// Number of scanlines that fill `height` at the current spacing. Returns 0
    /// for any non-finite or non-positive height so the drawing loop is a no-op.
    public func scanlineCount(forHeight height: Double) -> Int {
        guard height.isFinite, height > 0, scanlineSpacing > 0 else { return 0 }
        let count = (height / scanlineSpacing).rounded(.down)
        // Guard the Double -> Int cast: `Int(_:)` traps past Int.max. An absurd
        // height is degenerate, so collapse to no lines rather than crash.
        guard count.isFinite, count >= 0, count <= Double(Int.max) else { return 0 }
        return Int(count)
    }
}

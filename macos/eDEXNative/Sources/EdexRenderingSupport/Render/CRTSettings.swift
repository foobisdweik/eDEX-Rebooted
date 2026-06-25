import Foundation

/// User-toggled CRT post-FX for the GPU terminal aesthetic (Spike C). Each effect
/// is independently flagged in `settings.json` and defaults OFF, so the all-off
/// state is the SDR-parity baseline (the GPU output matches the legacy overlay).
/// Amounts have sensible fixed defaults; only the on/off flags are user-facing.
public struct CRTSettings: Equatable, Sendable {
    public var curvature: Bool
    public var bloom: Bool
    public var chromaticAberration: Bool

    /// Barrel-distortion strength (normalized-coord radial gain).
    public var curvatureAmount: Double
    /// Extra glow multiplier above paper white (the HDR bloom payoff).
    public var bloomAmount: Double
    /// Per-channel glow offset, in points (scaled to px by the renderer).
    public var chromaticAmount: Double

    public init(
        curvature: Bool,
        bloom: Bool,
        chromaticAberration: Bool,
        curvatureAmount: Double = 0.12,
        bloomAmount: Double = 1.5,
        chromaticAmount: Double = 1.5
    ) {
        self.curvature = curvature
        self.bloom = bloom
        self.chromaticAberration = chromaticAberration
        self.curvatureAmount = curvatureAmount.isFinite ? max(0, curvatureAmount) : 0
        self.bloomAmount = bloomAmount.isFinite ? max(0, bloomAmount) : 0
        self.chromaticAmount = chromaticAmount.isFinite ? max(0, chromaticAmount) : 0
    }

    /// All effects off — the SDR-parity baseline.
    public static let off = CRTSettings(curvature: false, bloom: false, chromaticAberration: false)
}

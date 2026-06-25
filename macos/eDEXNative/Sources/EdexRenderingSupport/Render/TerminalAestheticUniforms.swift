import Foundation

/// The GPU uniform block for the terminal-aesthetic fragment shader (Spike C).
///
/// This is the *seam* between the pure geometry (`TerminalAestheticMetrics`,
/// authored in points), the live display state (`DisplayHeadroom`), the CRT
/// toggles (`CRTSettings`), and the MSL `AestheticUniforms` struct. It is a
/// faithful, layout-compatible mirror of that MSL struct: **19 contiguous
/// four-byte scalars, 4-byte alignment, no padding** (`size == stride == 76`), so
/// it can be uploaded verbatim via `setFragmentBytes`. The layout is pinned by a
/// unit test — keep the field order, types, and count identical on both sides.
///
/// Geometry is converted points→pixels here (metric × content scale) so the MSL
/// never hard-codes a geometry constant; the metrics struct stays the single
/// source of truth.
public struct TerminalAestheticUniforms: Equatable {
    public var surfaceWidthPx: Float
    public var surfaceHeightPx: Float
    public var scanlineSpacingPx: Float
    public var scanlineThicknessPx: Float
    public var scanlineOpacity: Float
    public var glowRadiusPx: Float
    public var glowOpacity: Float
    public var headroom: Float
    public var floorRatio: Float
    public var accentR: Float          // linear
    public var accentG: Float
    public var accentB: Float
    public var encodeToGamma: UInt32   // 1 = SDR (encode to gamma), 0 = HDR linear
    public var crtCurvature: UInt32
    public var crtBloom: UInt32
    public var crtChromaticAberration: UInt32
    public var crtCurvatureAmount: Float
    public var crtBloomAmount: Float
    public var crtChromaticAmount: Float

    public init(
        metrics: TerminalAestheticMetrics,
        surfaceWidthPx: Double,
        surfaceHeightPx: Double,
        contentScale: Double,
        accentLinear: (r: Double, g: Double, b: Double),
        headroom: DisplayHeadroom,
        crt: CRTSettings
    ) {
        let scale = (contentScale.isFinite && contentScale > 0) ? contentScale : 1.0
        self.surfaceWidthPx = Self.f(surfaceWidthPx)
        self.surfaceHeightPx = Self.f(surfaceHeightPx)
        // Metrics are in points; the shader works in pixels.
        self.scanlineSpacingPx = Self.f(metrics.scanlineSpacing * scale)
        self.scanlineThicknessPx = Self.f(metrics.scanlineThickness * scale)
        self.scanlineOpacity = Self.f(metrics.scanlineOpacity)
        self.glowRadiusPx = Self.f(metrics.glowRadius * scale)
        self.glowOpacity = Self.f(metrics.glowOpacity)
        self.headroom = Self.f(headroom.headroom)
        self.floorRatio = Self.f(headroom.tonemap.floor)
        self.accentR = Self.f(accentLinear.r)
        self.accentG = Self.f(accentLinear.g)
        self.accentB = Self.f(accentLinear.b)
        // SDR surfaces are gamma-encoded; extended-range surfaces stay linear.
        self.encodeToGamma = headroom.supportsExtendedRange ? 0 : 1
        self.crtCurvature = crt.curvature ? 1 : 0
        self.crtBloom = crt.bloom ? 1 : 0
        self.crtChromaticAberration = crt.chromaticAberration ? 1 : 0
        self.crtCurvatureAmount = Self.f(crt.curvatureAmount)
        self.crtBloomAmount = Self.f(crt.bloomAmount)
        // Chromatic offset is authored in points; scale to pixels like the geometry.
        self.crtChromaticAmount = Self.f(crt.chromaticAmount * scale)
    }

    /// Sanitized Double→Float: non-finite collapses to 0 (the project crashes on
    /// non-finite GPU math; a degenerate uniform must render nothing, not NaN).
    private static func f(_ value: Double) -> Float {
        value.isFinite ? Float(value) : 0
    }

    /// sRGB transfer → linear light, for converting a theme's gamma-encoded accent
    /// into the linear values the shader (and `accentLinear` above) expect.
    public static func srgbToLinear(_ c: Double) -> Double {
        guard c.isFinite else { return 0 }
        let x = min(max(c, 0), 1)
        return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }
}

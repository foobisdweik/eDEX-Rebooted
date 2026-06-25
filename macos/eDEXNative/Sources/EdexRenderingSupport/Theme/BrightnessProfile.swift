import Foundation

/// Native gamut a brightness profile authors into. Display P3 is the Apple wide
/// gamut; sRGB covers generic SDR panels.
public enum DisplayGamut: String, Sendable, CaseIterable, Codable {
    case sRGB
    case displayP3
}

/// Pure, `Sendable` description of a display's luminance + gamut characteristics
/// (Spike A). This is *selectable data* — the user picks a profile in
/// `settings.json` (no auto-detection per `Ultraplan.md`). It is the single source
/// of the luminance constants a tonemapper and, later, a GPU shader read from;
/// it performs no rendering and touches no `NSScreen`.
///
/// Luminances are absolute nits. `paperWhiteNits` is the fixed, app-configured SDR
/// reference white; HDR content blooms above it up to `maxWindow10Nits`. All inputs
/// are sanitized so callers can pass raw settings values (mirrors
/// `TerminalAestheticMetrics`).
public struct BrightnessProfile: Equatable, Sendable, Identifiable, Codable {
    public let id: String
    public let displayName: String
    /// Reference-mode label as macOS presents it (e.g. "P3-1600").
    public let referenceModeName: String
    public let gamut: DisplayGamut
    /// Fixed SDR reference (paper) white. Always `>= 1` nit so headroom math is safe.
    public let paperWhiteNits: Double
    /// 100%-window maintained luminance (full-screen sustained).
    public let maxWindow100Nits: Double
    /// 10%-window maintained / peak luminance (the HDR peak).
    public let maxWindow10Nits: Double
    /// Minimum displayable luminance (the floor; 0 nits on an XDR panel).
    public let minLuminanceNits: Double

    public init(
        id: String,
        displayName: String,
        referenceModeName: String,
        gamut: DisplayGamut,
        paperWhiteNits: Double,
        maxWindow100Nits: Double,
        maxWindow10Nits: Double,
        minLuminanceNits: Double
    ) {
        self.id = id
        self.displayName = displayName
        self.referenceModeName = referenceModeName
        self.gamut = gamut
        // Paper white divides into headroom, so it must be finite and positive.
        self.paperWhiteNits = (paperWhiteNits.isFinite && paperWhiteNits >= 1) ? paperWhiteNits : 1
        self.maxWindow100Nits = Self.sanitizeNits(maxWindow100Nits)
        self.maxWindow10Nits = Self.sanitizeNits(maxWindow10Nits)
        self.minLuminanceNits = Self.sanitizeNits(minLuminanceNits)
    }

    private static func sanitizeNits(_ value: Double) -> Double {
        (value.isFinite && value > 0) ? value : 0
    }

    /// Maximum EDR headroom this profile targets, paper-white-relative. `>= 1.0`
    /// (an SDR profile whose peak equals paper white yields exactly `1.0`).
    public var referenceHeadroom: Double {
        max(1.0, maxWindow10Nits / paperWhiteNits)
    }

    /// Whether the profile can show content above paper white.
    public var isHDR: Bool {
        referenceHeadroom > 1.0 + 1e-9
    }

    /// Luminance floor expressed paper-white-relative, for the tonemapper.
    public var luminanceFloorRatio: Double {
        minLuminanceNits / paperWhiteNits
    }

    /// The tonemapper this profile implies at its reference headroom. Spike B
    /// rebuilds the operator per-frame from *live* headroom; this is the static
    /// reference-mode operator used in tests and as a default.
    public func makeReferenceTonemap() -> Tonemap {
        Tonemap(headroom: referenceHeadroom, floor: luminanceFloorRatio)
    }
}

public extension BrightnessProfile {
    /// This machine's panel (MacBookPro18,1, 16-inch Liquid Retina XDR) and the
    /// app's out-of-box default: 1600-nit 100%/10% maintained, 0-nit floor,
    /// P3-1600 reference mode, 203-nit paper white.
    static let builtInLiquidRetinaXDR = BrightnessProfile(
        id: "liquid-retina-xdr-16",
        displayName: "Liquid Retina XDR (16-inch)",
        referenceModeName: "P3-1600",
        gamut: .displayP3,
        paperWhiteNits: 203,
        maxWindow100Nits: 1600,
        maxWindow10Nits: 1600,
        minLuminanceNits: 0
    )

    /// Apple Pro Display XDR (1000-nit sustained full-screen, 1600-nit peak).
    static let proDisplayXDR = BrightnessProfile(
        id: "pro-display-xdr",
        displayName: "Pro Display XDR",
        referenceModeName: "P3-1600",
        gamut: .displayP3,
        paperWhiteNits: 203,
        maxWindow100Nits: 1000,
        maxWindow10Nits: 1600,
        minLuminanceNits: 0
    )

    /// Apple Studio Display (600-nit, no HDR headroom beyond its SDR peak).
    static let studioDisplay = BrightnessProfile(
        id: "studio-display",
        displayName: "Studio Display",
        referenceModeName: "P3-600",
        gamut: .displayP3,
        paperWhiteNits: 200,
        maxWindow100Nits: 600,
        maxWindow10Nits: 600,
        minLuminanceNits: 0
    )

    /// Generic HDR panel (modest 1000-nit peak over a 203-nit paper white).
    static let genericHDR = BrightnessProfile(
        id: "generic-hdr",
        displayName: "Generic HDR",
        referenceModeName: "Generic HDR",
        gamut: .displayP3,
        paperWhiteNits: 203,
        maxWindow100Nits: 1000,
        maxWindow10Nits: 1000,
        minLuminanceNits: 0
    )

    /// Generic SDR panel — peak equals paper white, so headroom is exactly 1.0
    /// and the reference tonemapper is the identity (the SDR-parity baseline).
    static let genericSDR = BrightnessProfile(
        id: "generic-sdr",
        displayName: "Generic SDR",
        referenceModeName: "sRGB",
        gamut: .sRGB,
        paperWhiteNits: 200,
        maxWindow100Nits: 200,
        maxWindow10Nits: 200,
        minLuminanceNits: 0
    )

    /// Out-of-box default profile (this machine's built-in XDR display).
    static let `default` = builtInLiquidRetinaXDR

    /// All selectable presets, default first.
    static let presets: [BrightnessProfile] = [
        builtInLiquidRetinaXDR,
        proDisplayXDR,
        studioDisplay,
        genericHDR,
        genericSDR
    ]

    /// Looks up a preset by its stable `id` (the value stored in `settings.json`),
    /// or `nil` if unknown.
    static func preset(id: String) -> BrightnessProfile? {
        presets.first { $0.id == id }
    }
}

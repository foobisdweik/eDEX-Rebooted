// Spike B — color/brightness platform, live-display half.
//
// Pure, AppKit-free resolution of a display's live EDR capability against the
// user-selected `BrightnessProfile`. This is the *seam* between the off-MainActor
// `DisplayProbe` (which reads the raw `NSScreen` EDR triad) and the Metal
// presentation host (which needs a single resolved headroom + a pixel-format
// decision + the per-frame `Tonemap`). Keeping it pure keeps it unit-testable
// without a window, mirroring how `BrightnessProfile`/`Tonemap` are tested.
//
// NSScreen exposes three paper-white-relative headroom multipliers (all `1.0`
// means SDR / no headroom):
//   • maximumExtendedDynamicRangeColorComponentValue — the *current, live* ceiling
//     (drops to ~1.0 on battery / low brightness even on an XDR panel).
//   • maximumPotentialExtendedDynamicRangeColorComponentValue — the panel's best
//     case (capability indicator, independent of current conditions).
//   • maximumReferenceExtendedDynamicRangeColorComponentValue — non-zero only when
//     the display is in an HDR *reference* mode; `0` otherwise.

import Foundation

/// A display's live EDR state resolved against a `BrightnessProfile`, reduced to
/// the three things the render path needs: the effective `headroom`, whether to
/// allocate an `extended-range` surface, and the `Tonemap` to apply per frame.
public struct DisplayHeadroom: Equatable, Sendable {
    /// Live max EDR headroom the display can show *right now*, paper-white-relative.
    /// Sanitized to `>= 1.0` (non-finite / sub-unity inputs collapse to SDR `1.0`).
    public let liveMaxEDR: Double
    /// The panel's potential max EDR (capability, condition-independent), `>= 1.0`.
    public let potentialMaxEDR: Double
    /// Reference-mode EDR if the display is in an HDR reference mode, else `1.0`
    /// (a raw `0` "not in reference mode" is normalized to the SDR sentinel `1.0`).
    public let referenceMaxEDR: Double

    /// Effective headroom handed to the tonemapper: the live display ceiling,
    /// capped by what the selected profile actually authors for. `>= 1.0`, so an
    /// SDR display (or SDR profile) yields exactly `1.0` and the identity tonemap.
    public let headroom: Double
    /// Whether extended-range content can be shown *now* — the gate the Metal host
    /// uses to pick `rgba16Float`/extended-linear-P3 over the `bgra8Unorm`/sRGB
    /// fallback. False whenever live headroom is at SDR, even on a capable panel.
    public let supportsExtendedRange: Bool
    /// The per-frame operator: identity on `[0, 1]` at `headroom == 1.0` (SDR
    /// parity), soft roll-off into `headroom` above paper white otherwise.
    public let tonemap: Tonemap

    private static let epsilon = 1e-9

    /// Sanitize a paper-white-relative EDR multiplier: non-finite or sub-unity
    /// values mean "no headroom", i.e. SDR `1.0`.
    private static func sanitize(_ value: Double) -> Double {
        (value.isFinite && value > 1.0) ? value : 1.0
    }

    /// Resolve a live `NSScreen` EDR triad against the selected profile.
    ///
    /// The effective headroom is `min(profileReferenceHeadroom, liveMaxEDR)`:
    /// never promise more than the display can currently show, never exceed what
    /// the profile authors for. Extended-range allocation follows the *live*
    /// ceiling — a capable panel sitting at SDR (e.g. on battery) gets the SDR
    /// path until its headroom actually opens up.
    public init(
        profile: BrightnessProfile,
        maximumEDR: Double,
        maximumPotentialEDR: Double,
        maximumReferenceEDR: Double
    ) {
        let live = Self.sanitize(maximumEDR)
        let potential = max(Self.sanitize(maximumPotentialEDR), live)
        self.liveMaxEDR = live
        self.potentialMaxEDR = potential
        self.referenceMaxEDR = Self.sanitize(maximumReferenceEDR)

        let effective = max(1.0, min(profile.referenceHeadroom, live))
        self.headroom = effective
        self.supportsExtendedRange = effective > 1.0 + Self.epsilon
        self.tonemap = Tonemap(headroom: effective, floor: profile.luminanceFloorRatio)
    }

    private init(
        liveMaxEDR: Double,
        potentialMaxEDR: Double,
        referenceMaxEDR: Double,
        headroom: Double,
        supportsExtendedRange: Bool,
        tonemap: Tonemap
    ) {
        self.liveMaxEDR = liveMaxEDR
        self.potentialMaxEDR = potentialMaxEDR
        self.referenceMaxEDR = referenceMaxEDR
        self.headroom = headroom
        self.supportsExtendedRange = supportsExtendedRange
        self.tonemap = tonemap
    }

    /// The unconditional SDR state: headroom `1.0`, identity tonemap, no extended
    /// range. The probe's value before any screen is read, and the value on any
    /// display (internal or external) that exposes no live headroom. The Metal
    /// host renders pixel-identical to a plain SDR fill in this state.
    public static let sdr = DisplayHeadroom(
        liveMaxEDR: 1.0,
        potentialMaxEDR: 1.0,
        referenceMaxEDR: 1.0,
        headroom: 1.0,
        supportsExtendedRange: false,
        tonemap: Tonemap(headroom: 1.0, floor: 0)
    )
}

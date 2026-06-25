import Foundation

/// Pure, `Sendable` reference-white-relative tonemapping operator (Spike A).
///
/// macOS composites in extended-linear space where `1.0` is *paper white* and
/// HDR values may exceed `1.0` up to the display's live **headroom**
/// (`displayPeakLuminance / paperWhiteLuminance`). This operator maps an authored
/// paper-white-relative value (`1.0` == paper white) onto the displayable range
/// `[floor, headroom]`, leaving the SDR range `[0, 1]` untouched and rolling the
/// HDR excursion above paper white smoothly into the available headroom.
///
/// SDR-parity guarantee: when `headroom == 1.0` the map is the identity on `[0, 1]`
/// (excursions above `1.0` clamp to `1.0`), so a pure-SDR fill renders unchanged.
///
/// All inputs are sanitized — the project crashes on non-finite `Double` math, so
/// callers can hand raw values straight in (mirrors `TerminalAestheticMetrics`).
public struct Tonemap: Equatable, Sendable {
    /// Display headroom = peak / paper-white, in paper-white-relative units.
    /// Always `>= 1.0` (an SDR display has headroom `1.0`).
    public let headroom: Double
    /// Minimum displayable luminance, paper-white-relative (e.g. `0` for an XDR
    /// panel whose floor is 0 nits). Output never drops below this.
    public let floor: Double

    /// Knee is fixed at paper white (`1.0`): the SDR range below it is identity,
    /// the roll-off lives above it. Keeps golden-image SDR parity deterministic.
    private static let knee = 1.0
    private static let epsilon = 1e-9

    public init(headroom: Double, floor: Double = 0) {
        // An SDR display has headroom 1.0; anything non-finite or below 1.0 is
        // treated as SDR rather than allowed to invert the roll-off math.
        let resolvedHeadroom = (headroom.isFinite && headroom > 1.0) ? headroom : 1.0
        self.headroom = resolvedHeadroom
        // Floor is a paper-white-relative minimum, so it must sit in [0, 1] (at or
        // below paper white). Clamping here keeps it from exceeding the headroom
        // cap or lifting output above 1.0 — which would break the documented
        // [floor, headroom] range and the SDR-parity identity at the knee.
        if floor.isFinite, floor > 0 {
            self.floor = min(floor, min(1.0, resolvedHeadroom))
        } else {
            self.floor = 0
        }
    }

    /// Map a paper-white-relative authored value onto `[floor, headroom]`.
    /// Identity on `[0, 1]` whenever there is headroom (and entirely when
    /// `headroom == 1.0`); a hue-neutral soft roll-off compresses `(1, ∞)` into
    /// `(1, headroom]`, asymptotically approaching but never exceeding `headroom`.
    /// The roll-off curve alone — no floor lift, no peak clamp. Identity on `[0, 1]`
    /// (and entirely when `headroom == 1.0`); a smooth, C1-continuous compression
    /// above the knee (`f(1)=1`, `f'(1)=1`, `f(∞)→headroom`). Factored out so the
    /// hue-preserving RGB path can derive its scale from the *un-floored* curve.
    private func rolled(_ value: Double) -> Double {
        let v = value.isFinite ? max(0, value) : 0
        if headroom <= Self.knee + Self.epsilon {
            // SDR: identity within [0, 1], clamp HDR excursions to paper white.
            return min(v, Self.knee)
        } else if v <= Self.knee {
            // Below the knee the SDR range is untouched — the parity guarantee.
            return v
        } else {
            let excess = headroom - Self.knee
            return Self.knee + (v - Self.knee) / (1.0 + (v - Self.knee) / excess)
        }
    }

    public func map(_ value: Double) -> Double {
        min(max(rolled(value), floor), max(headroom, floor))
    }

    /// Hue-preserving map of an extended-linear paper-white-relative RGB triple:
    /// tonemaps the Rec.709 luminance and scales all channels by the same factor,
    /// so chromaticity is preserved (channels are clamped to `[0, headroom]`).
    public func map(red: Double, green: Double, blue: Double) -> (red: Double, green: Double, blue: Double) {
        let r = red.isFinite ? max(0, red) : 0
        let g = green.isFinite ? max(0, green) : 0
        let b = blue.isFinite ? max(0, blue) : 0
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        guard luminance > Self.epsilon else { return (floor, floor, floor) }
        // Derive the scale from the *un-floored* rolled luminance. Using the
        // floor-clamped `map(luminance)` would send the scale to infinity as
        // luminance → 0 (floor/luminance), boosting near-black colors to saturated
        // near-cap values. The roll-off keeps the scale ≈ 1 for darks; the
        // per-channel floor clamp below then desaturates them toward the neutral
        // floor — continuous and hue-faithful.
        let scale = rolled(luminance) / luminance
        let cap = max(headroom, floor)
        return (
            min(max(r * scale, floor), cap),
            min(max(g * scale, floor), cap),
            min(max(b * scale, floor), cap)
        )
    }
}

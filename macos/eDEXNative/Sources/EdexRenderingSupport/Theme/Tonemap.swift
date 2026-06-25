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
        self.headroom = (headroom.isFinite && headroom > 1.0) ? headroom : 1.0
        self.floor = (floor.isFinite && floor > 0) ? floor : 0
    }

    /// Map a paper-white-relative authored value onto `[floor, headroom]`.
    /// Identity on `[0, 1]` whenever there is headroom (and entirely when
    /// `headroom == 1.0`); a hue-neutral soft roll-off compresses `(1, ∞)` into
    /// `(1, headroom]`, asymptotically approaching but never exceeding `headroom`.
    public func map(_ value: Double) -> Double {
        let v = value.isFinite ? max(0, value) : 0
        let rolled: Double
        if headroom <= Self.knee + Self.epsilon {
            // SDR: identity within [0, 1], clamp HDR excursions to paper white.
            rolled = min(v, Self.knee)
        } else if v <= Self.knee {
            // Below the knee the SDR range is untouched — the parity guarantee.
            rolled = v
        } else {
            // Smooth, C1-continuous roll-off: f(1)=1, f'(1)=1, f(∞)→headroom.
            let excess = headroom - Self.knee
            rolled = Self.knee + (v - Self.knee) / (1.0 + (v - Self.knee) / excess)
        }
        return min(max(rolled, floor), max(headroom, floor))
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
        let scale = map(luminance) / luminance
        let cap = max(headroom, floor)
        return (
            min(max(r * scale, 0), cap),
            min(max(g * scale, 0), cap),
            min(max(b * scale, 0), cap)
        )
    }
}

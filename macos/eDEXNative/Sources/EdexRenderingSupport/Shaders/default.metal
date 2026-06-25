#include <metal_stdlib>
using namespace metal;

// eDEX terminal aesthetic — single fragment pass (Spike C).
// Reproduces the legacy Canvas+blur overlay (faint CRT scanlines + accent edge
// glow) procedurally, driven ENTIRELY by `AestheticUniforms` — the geometry is
// owned by Swift's `TerminalAestheticMetrics` and uploaded here; no geometry
// constants are duplicated in MSL. Authored in linear light so the glow can bloom
// above paper white into live EDR headroom via the Spike-A tonemap; an SDR encode
// path keeps headroom==1.0 output identical to the gamma-space Canvas overlay.
//
// Offline-compiled (Scripts/build-shaders.sh, metal -std=metal4.1) into the
// bundled default.metallib; there is no runtime shader compilation.

#if __METAL_VERSION__ < 410
#error "eDEX shaders require the Metal 4.1 baseline (macOS 27 toolchain floor)."
#endif

// Field order + types MUST match Swift `TerminalAestheticUniforms` exactly:
// 19 four-byte scalars, 4-byte alignment, no padding (size == 76).
struct AestheticUniforms {
    float surfaceWidthPx;
    float surfaceHeightPx;
    float scanlineSpacingPx;
    float scanlineThicknessPx;
    float scanlineOpacity;
    float glowRadiusPx;
    float glowOpacity;
    float headroom;
    float floorRatio;
    float accentR;          // linear
    float accentG;
    float accentB;
    uint  encodeToGamma;    // 1 = SDR (encode to gamma), 0 = HDR (linear out)
    uint  crtCurvature;
    uint  crtBloom;
    uint  crtChromaticAberration;
    float crtCurvatureAmount;
    float crtBloomAmount;
    float crtChromaticAmount;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Fullscreen triangle; no vertex buffer (positions derived from vertex_id).
[[vertex]] VertexOut edexAestheticVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    const float2 uvs[3]       = { float2(0.0, 1.0),  float2(2.0, 1.0),  float2(0.0, -1.0) };
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID]; // top-left origin (y down), matching layout coords
    return out;
}

// --- Spike-A tonemap, mirrored (rolled curve + hue-preserving luma scale). ---
static float edexRolled(float v, float headroom) {
    v = max(0.0, v);
    if (headroom <= 1.0 + 1e-6) {
        return min(v, 1.0);           // SDR: identity on [0,1], clamp excursions
    }
    if (v <= 1.0) {
        return v;                     // SDR range untouched (parity guarantee)
    }
    float excess = headroom - 1.0;
    return 1.0 + (v - 1.0) / (1.0 + (v - 1.0) / excess);
}

static float3 edexTonemap(float3 c, float headroom) {
    float luma = dot(c, float3(0.2126, 0.7152, 0.0722));
    if (luma <= 1e-6) {
        return clamp(c, 0.0, headroom);
    }
    float mapped = edexRolled(luma, headroom);
    return c * (mapped / luma);       // hue-preserving
}

static float3 edexLinearToSRGB(float3 c) {
    c = clamp(c, 0.0, 1.0);
    float3 lo = 12.92 * c;
    float3 hi = 1.055 * pow(c, 1.0 / 2.4) - 0.055;
    return select(lo, hi, c > 0.0031308);
}

// Barrel (CRT) warp of normalized [0,1] coords; amount 0 → identity.
static float2 edexBarrel(float2 uv, float amount) {
    float2 c = uv * 2.0 - 1.0;
    float r2 = dot(c, c);
    c *= 1.0 + amount * r2;
    return c * 0.5 + 0.5;
}

// Per-line coverage: 1 on a scanline center, 0 between, ~1px anti-aliased.
static float edexScanlineCoverage(float yPx, float spacing, float thickness) {
    if (spacing <= 0.0) {
        return 0.0;
    }
    float phase = fract(yPx / spacing);
    float dist = min(phase, 1.0 - phase) * spacing;   // px to nearest line center
    float halfW = thickness * 0.5;
    return 1.0 - smoothstep(halfW - 0.5, halfW + 0.5, dist);
}

// Soft accent edge glow: Gaussian falloff from the nearest surface edge.
// Mirrors the legacy `0 0 0.6vh rgba(accent,0.6)` inset glow.
static float edexEdgeGlow(float2 px, float2 sizePx, float radius) {
    if (radius <= 0.0) {
        return 0.0;
    }
    float d = min(min(px.x, sizePx.x - px.x), min(px.y, sizePx.y - px.y));
    float sigma = max(radius, 1e-3);
    return exp(-(d * d) / (2.0 * sigma * sigma));
}

[[fragment]] float4 edexAestheticFragment(VertexOut in [[stage_in]],
                                          constant AestheticUniforms& u [[buffer(0)]]) {
    float2 sizePx = float2(u.surfaceWidthPx, u.surfaceHeightPx);

    float2 uv = in.uv;
    if (u.crtCurvature != 0u) {
        uv = edexBarrel(uv, u.crtCurvatureAmount);
        // Curvature bends the corners past the surface; nothing to draw there.
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            return float4(0.0);
        }
    }
    float2 px = uv * sizePx;

    // --- Glow (accent), optionally bloomed + chromatically aberrated. ---
    float bloom = (u.crtBloom != 0u) ? (1.0 + u.crtBloomAmount) : 1.0;
    float3 accent = float3(u.accentR, u.accentG, u.accentB);

    float ga;
    float3 glowColor;
    if (u.crtChromaticAberration != 0u) {
        // Split the glow sample per channel along the inward radial so the accent
        // halo fringes red/blue — a CRT chromatic-aberration cue.
        float2 center = sizePx * 0.5;
        float2 dir = normalize(px - center + float2(1e-4));
        float off = u.crtChromaticAmount;
        float gr = edexEdgeGlow(px + dir * off, sizePx, u.glowRadiusPx);
        float gg = edexEdgeGlow(px,             sizePx, u.glowRadiusPx);
        float gb = edexEdgeGlow(px - dir * off, sizePx, u.glowRadiusPx);
        ga = gg * u.glowOpacity;
        // Per-channel alpha folded into a single straight color, normalized to gg.
        float denom = max(gg, 1e-5);
        glowColor = accent * bloom * float3(gr / denom, 1.0, gb / denom);
    } else {
        ga = edexEdgeGlow(px, sizePx, u.glowRadiusPx) * u.glowOpacity;
        glowColor = accent * bloom;
    }
    glowColor = edexTonemap(glowColor, u.headroom);

    // --- Scanlines (black), drawn over the glow. ---
    float sa = edexScanlineCoverage(px.y, u.scanlineSpacingPx, u.scanlineThicknessPx) * u.scanlineOpacity;

    // Composite scanline (black) over glow, premultiplied output.
    float outA = sa + ga * (1.0 - sa);
    float3 straight = (u.encodeToGamma != 0u) ? edexLinearToSRGB(glowColor) : glowColor;
    // Scanline is black (premult rgb 0); only the glow contributes color.
    float3 premulRGB = straight * (ga * (1.0 - sa));
    return float4(premulRGB, outA);
}

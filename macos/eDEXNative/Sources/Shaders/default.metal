#include <metal_stdlib>
using namespace metal;

// Spike 0 placeholder. This shader exists only to prove the offline-compiled
// `.metallib` delivery path end to end:
//   metal -std=metal4.1 -> metallib -> bundled resource -> makeDefaultLibrary(bundle:)
// There is intentionally no runtime shader compilation anywhere in the app.
// Real shaders (terminal aesthetic + CRT FX) arrive in Spike C and replace this.
// Rebuild the bundled library with: macos/eDEXNative/Scripts/build-shaders.sh

#if __METAL_VERSION__ < 410
#error "eDEX shaders require the Metal 4.1 baseline (macOS 27 toolchain floor)."
#endif

[[vertex]] float4 edexPlaceholderVertex(uint vertexID [[vertex_id]]) {
    // A degenerate fullscreen-triangle stand-in; never drawn in Spike 0.
    const float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    return float4(positions[vertexID], 0.0, 1.0);
}

[[fragment]] float4 edexPlaceholderFragment() {
    return float4(0.0, 0.0, 0.0, 1.0);
}

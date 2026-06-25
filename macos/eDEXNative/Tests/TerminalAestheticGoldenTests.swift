import XCTest
import Metal
@testable import EdexRenderingSupport

/// Golden-image harness for the GPU terminal aesthetic (Spike C). Renders the
/// fragment pass offscreen and asserts the structural + SDR-parity properties the
/// Ultraplan requires: with CRT flags off and headroom 1.0 the output is a plain
/// SDR overlay (transparent interior, darkened scanline rows, accent edge glow),
/// it never exceeds the SDR range, and it is deterministic.
///
/// GPU-dependent: skips cleanly where no Metal device exists (the unit suite runs
/// on a real Apple-Silicon machine via `verify --full`; there is no GPU CI).
final class TerminalAestheticGoldenTests: XCTestCase {
    private let width = 400
    private let height = 400

    private func makeRenderer() throws -> TerminalAestheticRenderer {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device (headless); GPU golden test skipped.")
        }
        return try TerminalAestheticRenderer(device: device, pixelFormat: .bgra8Unorm)
    }

    /// SDR baseline uniforms: headroom 1.0, all CRT off. vh chosen so the glow
    /// radius (0.6·vh) is small relative to the surface, leaving a transparent core.
    private func sdrUniforms() -> TerminalAestheticUniforms {
        let metrics = TerminalAestheticMetrics(surfaceHeight: Double(height), vh: 100)
        return TerminalAestheticUniforms(
            metrics: metrics,
            surfaceWidthPx: Double(width),
            surfaceHeightPx: Double(height),
            contentScale: 1.0,
            accentLinear: (r: 0.0, g: 0.8, b: 0.9), // tron-ish cyan, linear
            headroom: .sdr,
            crt: .off
        )
    }

    private func alpha(_ px: [UInt8], _ x: Int, _ y: Int) -> Int {
        Int(px[(y * width + x) * 4 + 3])
    }
    // bgra8Unorm byte order: B, G, R, A
    private func rgb(_ px: [UInt8], _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * width + x) * 4
        return (r: Int(px[i + 2]), g: Int(px[i + 1]), b: Int(px[i]))
    }

    func testSdrInteriorIsTransparent() throws {
        let renderer = try makeRenderer()
        let px = try renderer.renderForReadback(uniforms: sdrUniforms(), width: width, height: height)
        // Center, far from every edge (glow ~0) and chosen off a scanline row.
        let a = alpha(px, width / 2, 199)
        XCTAssertLessThan(a, 8, "SDR interior should be ~transparent (got alpha \(a))")
    }

    func testScanlineRowsAreDarkenedRelativeToInterior() throws {
        let renderer = try makeRenderer()
        let u = sdrUniforms()
        let px = try renderer.renderForReadback(uniforms: u, width: width, height: height)
        // Spacing = max(2, 0.3·vh) = 30px; a line center sits at y = 180.
        let spacing = Int(u.scanlineSpacingPx.rounded())
        XCTAssertEqual(spacing, 30)
        let onLine = alpha(px, width / 2, 180)
        let offLine = alpha(px, width / 2, 195)
        XCTAssertGreaterThan(onLine, offLine, "scanline row should be more opaque than the gap")
    }

    func testEdgeGlowIsPresentAndAccentColored() throws {
        let renderer = try makeRenderer()
        let px = try renderer.renderForReadback(uniforms: sdrUniforms(), width: width, height: height)
        let edge = alpha(px, 1, height / 2)       // hard against the left edge
        let center = alpha(px, width / 2, 199)
        XCTAssertGreaterThan(edge, center, "edge glow should be far more opaque than the core")
        XCTAssertGreaterThan(edge, 60, "edge glow should be clearly visible")
        // Accent is cyan: green/blue dominate red in the glow.
        let c = rgb(px, 1, height / 2)
        XCTAssertGreaterThan(c.g, c.r)
        XCTAssertGreaterThan(c.b, c.r)
    }

    func testDeterministicAcrossRenders() throws {
        let renderer = try makeRenderer()
        let u = sdrUniforms()
        let a = try renderer.renderForReadback(uniforms: u, width: width, height: height)
        let b = try renderer.renderForReadback(uniforms: u, width: width, height: height)
        XCTAssertEqual(a, b, "identical uniforms must produce byte-identical output")
    }

    func testCurvatureFlagChangesOutput() throws {
        let renderer = try makeRenderer()
        let off = try renderer.renderForReadback(uniforms: sdrUniforms(), width: width, height: height)
        let metrics = TerminalAestheticMetrics(surfaceHeight: Double(height), vh: 100)
        let curved = TerminalAestheticUniforms(
            metrics: metrics,
            surfaceWidthPx: Double(width),
            surfaceHeightPx: Double(height),
            contentScale: 1.0,
            accentLinear: (r: 0.0, g: 0.8, b: 0.9),
            headroom: .sdr,
            crt: CRTSettings(curvature: true, bloom: false, chromaticAberration: false)
        )
        let on = try renderer.renderForReadback(uniforms: curved, width: width, height: height)
        XCTAssertNotEqual(off, on, "curvature flag must visibly change the output")
    }
}

import AppKit
import Metal
import QuartzCore
import SwiftUI
import EdexRenderingSupport

// MARK: - NSViewRepresentable wrapper

/// CAMetalLayer-backed host for the GPU terminal aesthetic (Spike C, built on the
/// Spike B substrate). Renders the scanline + accent-glow + CRT pass into a
/// transparent overlay via `TerminalAestheticRenderer`. Strict on-demand
/// presentation: draws once per content change, never per vsync — mirrors the
/// `CpuGraphNSView` cadence (occlusion-gated, no free-running loop).
struct MetalHostView: NSViewRepresentable {
    let theme: NativeTheme
    let vh: Double
    let headroom: DisplayHeadroom
    let crt: CRTSettings
    let reducedMotion: Bool
    let isEnabled: Bool

    init(
        theme: NativeTheme,
        vh: Double,
        headroom: DisplayHeadroom,
        crt: CRTSettings,
        reducedMotion: Bool,
        isEnabled: Bool
    ) {
        self.theme = theme
        self.vh = vh
        self.headroom = headroom
        self.crt = crt
        self.reducedMotion = reducedMotion
        self.isEnabled = isEnabled
    }

    func makeNSView(context: Context) -> MetalHostNSView {
        MetalHostNSView()
    }

    func updateNSView(_ view: MetalHostNSView, context: Context) {
        view.apply(
            theme: theme,
            vh: vh,
            headroom: headroom,
            crt: crt,
            reducedMotion: reducedMotion,
            isEnabled: isEnabled
        )
    }
}

// MARK: - CAMetalLayer-backed NSView

@MainActor
final class MetalHostNSView: NSView {
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private var renderer: TerminalAestheticRenderer?
    private var rendererFormat: MTLPixelFormat?

    private var theme: NativeTheme = .fallback
    private var vh: Double = 0
    private var headroom: DisplayHeadroom = .sdr
    private var crt: CRTSettings = .off
    private var reducedMotion = false
    private var isEnabled = false

    // A draw deferred because the surface was occluded / unsized / a transient GPU
    // allocation failed. Cleared only after a successful commit.
    private var pendingDraw = false
    // Coalesces the one-shot retry for transient GPU-allocation failures while
    // visible (no other wake-up would re-fire them).
    private var retryScheduled = false

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override init(frame: NSRect) {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        self.commandQueue = device?.makeCommandQueue()
        super.init(frame: frame)
        wantsLayer = true // triggers makeBackingLayer()
        guard let device, let ml = layer as? CAMetalLayer else { return }
        ml.device = device
        ml.framebufferOnly = true
        ml.isOpaque = false // transparent overlay over the terminal beneath
        configureLayerFormat(ml, supportsExtendedRange: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MetalHostNSView is code-only")
    }

    /// Return a `CAMetalLayer` as the backing layer — AppKit retains it via `layer`.
    override func makeBackingLayer() -> CALayer {
        CAMetalLayer()
    }

    // MARK: - Layer format / renderer

    private func configureLayerFormat(_ ml: CAMetalLayer, supportsExtendedRange: Bool) {
        // EDR: extended-linear Display P3 in 16-bit float so the glow can bloom
        // above paper white. SDR fallback: standard Display P3 in 8-bit bgra
        // (lower bandwidth, no EDR compositing overhead on incapable panels).
        if supportsExtendedRange {
            ml.wantsExtendedDynamicRangeContent = true
            ml.pixelFormat = .rgba16Float
            ml.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        } else {
            ml.wantsExtendedDynamicRangeContent = false
            ml.pixelFormat = .bgra8Unorm
            ml.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        }
        ensureRenderer(for: ml.pixelFormat)
    }

    /// (Re)build the render pipeline only when the pixel format actually changes —
    /// the pipeline is bound to one color format.
    private func ensureRenderer(for format: MTLPixelFormat) {
        guard let device else { return }
        if rendererFormat == format, renderer != nil { return }
        do {
            renderer = try TerminalAestheticRenderer(device: device, pixelFormat: format)
            rendererFormat = format
        } catch {
            renderer = nil
            rendererFormat = nil
            // No pipeline → the view stays inert rather than crashing. The metallib
            // is validated end-to-end by the smoke check; this guards headless/edge.
            NSLog("MetalHostView: renderer unavailable for \(format): \(error)")
        }
    }

    // MARK: - Update seam (called from updateNSView on every SwiftUI diff pass)

    func apply(
        theme: NativeTheme,
        vh: Double,
        headroom: DisplayHeadroom,
        crt: CRTSettings,
        reducedMotion: Bool,
        isEnabled: Bool
    ) {
        let formatChanged = headroom.supportsExtendedRange != self.headroom.supportsExtendedRange
        let changed = vh != self.vh
            || headroom != self.headroom
            || crt != self.crt
            || theme.name != self.theme.name
            || reducedMotion != self.reducedMotion
        let justEnabled = isEnabled && !self.isEnabled

        self.theme = theme
        self.vh = vh
        self.headroom = headroom
        self.crt = crt
        self.reducedMotion = reducedMotion
        self.isEnabled = isEnabled

        guard isEnabled else {
            pendingDraw = false
            return
        }

        if formatChanged, let ml = layer as? CAMetalLayer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            configureLayerFormat(ml, supportsExtendedRange: headroom.supportsExtendedRange)
            CATransaction.commit()
        }
        // On-demand discipline: redraw only when content actually changed or the
        // host just turned on — not on every SwiftUI diff pass (those fire at the
        // unrelated telemetry-refresh cadence).
        if changed || formatChanged || justEnabled {
            setNeedsDraw()
        }
    }

    // MARK: - Layout / HiDPI

    override func layout() {
        super.layout()
        resizeDrawableIfNeeded()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        resizeDrawableIfNeeded()
    }

    /// Resize the drawable to bounds × backing scale and redraw — but only when the
    /// size actually changed, so a redundant layout pass costs no Metal present.
    private func resizeDrawableIfNeeded() {
        guard let ml = layer as? CAMetalLayer else { return }
        let scale = window?.backingScaleFactor ?? 1.0
        let newSize = CGSize(
            width: max(1, bounds.width * scale),
            height: max(1, bounds.height * scale)
        )
        guard ml.contentsScale != scale || ml.drawableSize != newSize else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ml.contentsScale = scale
        ml.drawableSize = newSize
        CATransaction.commit()
        setNeedsDraw()
    }

    // MARK: - Window / occlusion observation

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didChangeOcclusionStateNotification,
            object: nil
        )
        if let win = window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(occlusionStateDidChange),
                name: NSWindow.didChangeOcclusionStateNotification,
                object: win
            )
            setNeedsDraw()
        }
    }

    @objc private func occlusionStateDidChange() {
        guard pendingDraw else { return }
        performDraw()
    }

    // MARK: - Draw scheduling

    func setNeedsDraw() {
        guard isEnabled else { return }
        performDraw()
    }

    private func performDraw() {
        guard isEnabled else { return }
        guard let renderer, let ml = layer as? CAMetalLayer else { return } // inert when headless
        guard ml.drawableSize.width > 0, ml.drawableSize.height > 0 else {
            pendingDraw = true // layout() will re-fire once bounds are known
            return
        }
        guard window?.occlusionState.contains(.visible) ?? false else {
            pendingDraw = true // occlusionStateDidChange() re-fires when visible
            return
        }
        guard let commandQueue else {
            pendingDraw = true
            return
        }
        guard let drawable = ml.nextDrawable() else {
            pendingDraw = true
            scheduleRetryWhileVisible()
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            pendingDraw = true
            scheduleRetryWhileVisible()
            return
        }
        renderer.encode(
            uniforms: makeUniforms(drawableSize: ml.drawableSize),
            into: drawable.texture,
            commandBuffer: commandBuffer
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
        pendingDraw = false // cleared only on a successful commit
    }

    /// Build the per-frame uniforms from the current bounds, theme accent, live
    /// headroom, and CRT toggles. Geometry comes from `TerminalAestheticMetrics`
    /// (points); the uniforms init scales to the drawable's pixels.
    private func makeUniforms(drawableSize: CGSize) -> TerminalAestheticUniforms {
        let scale = window?.backingScaleFactor ?? 1.0
        let metrics = TerminalAestheticMetrics(surfaceHeight: Double(bounds.height), vh: vh)
        let accent = theme.palette.accent
        return TerminalAestheticUniforms(
            metrics: metrics,
            surfaceWidthPx: Double(drawableSize.width),
            surfaceHeightPx: Double(drawableSize.height),
            contentScale: Double(scale),
            accentLinear: (
                r: TerminalAestheticUniforms.srgbToLinear(accent.red),
                g: TerminalAestheticUniforms.srgbToLinear(accent.green),
                b: TerminalAestheticUniforms.srgbToLinear(accent.blue)
            ),
            headroom: headroom,
            crt: crt
        )
    }

    /// One-shot, coalesced retry for transient GPU-allocation failures while
    /// visible — they have no other wake-up event. Bounded by `retryScheduled`.
    private func scheduleRetryWhileVisible() {
        guard !retryScheduled else { return }
        retryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0) { [weak self] in
            guard let self else { return }
            self.retryScheduled = false
            if self.pendingDraw { self.performDraw() }
        }
    }
}

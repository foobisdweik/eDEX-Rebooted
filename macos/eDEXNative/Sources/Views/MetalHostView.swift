import AppKit
import Metal
import QuartzCore
import SwiftUI
import EdexRenderingSupport

// MARK: - NSViewRepresentable wrapper

/// CAMetalLayer-backed host for the Spike B Metal presentation substrate.
/// Strict on-demand presentation: draws once per content change, never per vsync.
struct MetalHostView: NSViewRepresentable {
    let headroom: DisplayHeadroom
    let reducedMotion: Bool
    let isEnabled: Bool

    init(headroom: DisplayHeadroom, reducedMotion: Bool, isEnabled: Bool) {
        self.headroom = headroom
        self.reducedMotion = reducedMotion
        self.isEnabled = isEnabled
    }

    func makeNSView(context: Context) -> MetalHostNSView {
        MetalHostNSView()
    }

    func updateNSView(_ view: MetalHostNSView, context: Context) {
        view.apply(headroom: headroom, reducedMotion: reducedMotion, isEnabled: isEnabled)
    }
}

// MARK: - CAMetalLayer-backed NSView

@MainActor
final class MetalHostNSView: NSView {
    private var commandQueue: MTLCommandQueue?

    private var headroom: DisplayHeadroom = .sdr
    private var reducedMotion = false
    private var isEnabled = false

    // True when a draw was deferred (occluded, zero drawable size, drawable unavailable).
    // Cleared only after a successful buffer.commit(); re-fired by occlusionStateDidChange.
    private var pendingDraw = false
    // Coalesces the one-shot retry for transient GPU-allocation failures (drawable
    // pool exhausted, command buffer/encoder unavailable) that happen while visible
    // — those have no other wake-up trigger, so without this they could park forever.
    private var retryScheduled = false

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true  // triggers makeBackingLayer()

        // Guard headless: view stays inert for the session if no GPU is available.
        guard let dev = MTLCreateSystemDefaultDevice() else { return }
        commandQueue = dev.makeCommandQueue()

        guard let ml = layer as? CAMetalLayer else { return }
        ml.device = dev
        ml.framebufferOnly = true
        configureLayerFormat(ml, headroom: .sdr)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MetalHostNSView is code-only")
    }

    /// Return a `CAMetalLayer` as the backing layer — AppKit retains it via `layer`.
    override func makeBackingLayer() -> CALayer {
        CAMetalLayer()
    }

    // MARK: - Layer format

    private func configureLayerFormat(_ ml: CAMetalLayer, headroom: DisplayHeadroom) {
        // EDR: extended-linear Display P3 in 16-bit float for surfaces that can exceed
        // paper white. SDR fallback: standard Display P3 in 8-bit bgra — lower bandwidth
        // and no EDR compositing overhead on panels that can't benefit from it.
        if headroom.supportsExtendedRange {
            ml.wantsExtendedDynamicRangeContent = true
            ml.pixelFormat = .rgba16Float
            ml.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        } else {
            ml.wantsExtendedDynamicRangeContent = false
            ml.pixelFormat = .bgra8Unorm
            ml.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        }
    }

    // MARK: - Update seam (called from updateNSView on every SwiftUI diff pass)

    func apply(headroom: DisplayHeadroom, reducedMotion: Bool, isEnabled: Bool) {
        let formatChanged = headroom.supportsExtendedRange != self.headroom.supportsExtendedRange
        let headroomChanged = headroom != self.headroom
        let justEnabled = isEnabled && !self.isEnabled
        self.headroom = headroom
        self.reducedMotion = reducedMotion
        self.isEnabled = isEnabled

        guard isEnabled else {
            // Suppress any parked draw while the feature flag is off.
            pendingDraw = false
            return
        }

        if formatChanged, let ml = layer as? CAMetalLayer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            configureLayerFormat(ml, headroom: headroom)
            CATransaction.commit()
        }
        // On-demand discipline: draw only when content actually changed (headroom /
        // tonemap / pixel format) or the host just turned on — not on every SwiftUI
        // diff pass, which fires at the unrelated telemetry-refresh cadence.
        if headroomChanged || formatChanged || justEnabled {
            setNeedsDraw()
        }
    }

    // MARK: - Layout / HiDPI

    override func layout() {
        super.layout()
        resizeDrawableIfNeeded()
    }

    /// Called when the view moves between screens or the backing store resolution changes.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        resizeDrawableIfNeeded()
    }

    /// Resize the drawable to the current bounds × backing scale, and redraw — but
    /// only when the size actually changed. A redundant layout/backing pass (SwiftUI
    /// fires these at the unrelated telemetry cadence) must not trigger a Metal
    /// present, per the on-demand discipline.
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
        // Always remove then re-add so the view tracks exactly its current window,
        // including the move-between-windows case.
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
            // Fire any draw that was parked before we had a window.
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
        guard let queue = commandQueue else { return }  // nil when headless
        guard let ml = layer as? CAMetalLayer else { return }
        guard ml.drawableSize.width > 0, ml.drawableSize.height > 0 else {
            // Layout hasn't run yet; layout() will call setNeedsDraw() once bounds are known.
            pendingDraw = true
            return
        }
        guard window?.occlusionState.contains(.visible) ?? false else {
            // Window is occluded; occlusionStateDidChange() will re-fire when it becomes visible.
            pendingDraw = true
            return
        }

        // Reference fill: paper-white-relative (0.05, 0.05, 0.06) — a dark near-black with a
        // slight blue shift matching the eDEX terminal background. At headroom 1.0 the tonemap
        // is identity on [0, 1], so the output is unchanged → pixel-identical SDR clear
        // (Spike B acceptance: SDR parity when headroom == 1.0).
        let mapped = headroom.tonemap.map(red: 0.05, green: 0.05, blue: 0.06)

        guard let drawable = ml.nextDrawable() else {
            // Drawable pool transiently exhausted; no external trigger will wake us
            // (we're visible, sized, enabled), so schedule a bounded one-shot retry.
            pendingDraw = true
            scheduleRetryWhileVisible()
            return
        }

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColor(
            red: mapped.red, green: mapped.green, blue: mapped.blue, alpha: 1.0
        )

        guard let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: passDesc) else {
            pendingDraw = true
            scheduleRetryWhileVisible()
            return
        }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
        // Clear only on successful commit so a transient failure is retried.
        pendingDraw = false
    }

    /// One-shot, coalesced retry for transient GPU-allocation failures. Unlike the
    /// occlusion/zero-size parks (which have their own wake-up events), an allocation
    /// failure while visible would otherwise never retry. Bounded by `retryScheduled`
    /// so repeated failures can't spin a tight loop — at most one retry per frame.
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

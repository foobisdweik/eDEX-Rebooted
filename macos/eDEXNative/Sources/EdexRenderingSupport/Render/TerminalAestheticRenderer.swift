import Metal

/// Loads the offline-compiled `default.metallib` bundled with this target and
/// names the aesthetic shader's entry points. The metallib lives in
/// `EdexRenderingSupport` (not the app target) so both the runtime host and the
/// golden-image tests can load it via `Bundle.module` — there is no runtime
/// shader compilation (`makeLibrary(source:)` is never used).
public enum AestheticMetalLibrary {
    public static let vertexFunctionName = "edexAestheticVertex"
    public static let fragmentFunctionName = "edexAestheticFragment"

    public static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
        try device.makeDefaultLibrary(bundle: .module)
    }
}

/// Renders the terminal aesthetic (scanlines + accent glow + CRT FX) in a single
/// fragment pass. Owns the render-pipeline state for one pixel format; the host
/// rebuilds the renderer when the surface format flips (SDR ⇄ extended-range).
/// Not actor-isolated: the runtime host drives it on the MainActor, the
/// golden-image test drives it off-main — both serialize their own access.
public final class TerminalAestheticRenderer {
    public enum RendererError: Error, Equatable {
        case missingFunction(String)
        case noCommandQueue
        case noTexture
    }

    public let device: MTLDevice
    public let pixelFormat: MTLPixelFormat
    private let pipeline: MTLRenderPipelineState
    private let queue: MTLCommandQueue

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        self.device = device
        self.pixelFormat = pixelFormat
        let library = try AestheticMetalLibrary.makeLibrary(device: device)
        guard let vertexFn = library.makeFunction(name: AestheticMetalLibrary.vertexFunctionName) else {
            throw RendererError.missingFunction(AestheticMetalLibrary.vertexFunctionName)
        }
        guard let fragmentFn = library.makeFunction(name: AestheticMetalLibrary.fragmentFunctionName) else {
            throw RendererError.missingFunction(AestheticMetalLibrary.fragmentFunctionName)
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        guard let queue = device.makeCommandQueue() else {
            throw RendererError.noCommandQueue
        }
        self.queue = queue
    }

    /// Encode the aesthetic into `texture` on a caller-supplied command buffer.
    /// The pass clears to fully transparent so the overlay composites over the
    /// terminal beneath; the fragment writes premultiplied RGBA.
    public func encode(
        uniforms: TerminalAestheticUniforms,
        into texture: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        var u = uniforms
        encoder.setFragmentBytes(&u, length: MemoryLayout<TerminalAestheticUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Offscreen render + CPU readback, for the golden-image harness. Returns
    /// tightly-packed BGRA8 bytes (row stride == width*4). Synchronous.
    public func renderForReadback(
        uniforms: TerminalAestheticUniforms,
        width: Int,
        height: Int
    ) throws -> [UInt8] {
        guard width > 0, height > 0 else { throw RendererError.noTexture }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.noTexture
        }
        guard let commandBuffer = queue.makeCommandBuffer() else {
            throw RendererError.noCommandQueue
        }
        encode(uniforms: uniforms, into: texture, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Match the texture's bytes-per-pixel to the configured format — an
        // .rgba16Float (HDR) target is 8 bytes/px, not 4. Hardcoding 4 would let
        // getBytes overrun the buffer on an extended-range renderer.
        let bytesPerPixel = pixelFormat == .rgba16Float ? 8 : 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!,
                bytesPerRow: bytesPerRow,
                from: MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: width, height: height, depth: 1)
                ),
                mipmapLevel: 0
            )
        }
        return bytes
    }
}

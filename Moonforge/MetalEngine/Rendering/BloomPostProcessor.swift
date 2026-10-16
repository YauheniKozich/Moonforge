@preconcurrency import MetalKit

/// Mutable CPU state is accessed only under BaseRenderer.bloomLock. Frame textures are
/// encoded on the renderer's single command queue; Metal tracks the pass hazards.
final class BloomPostProcessor: @unchecked Sendable {
    static let scenePixelFormat: MTLPixelFormat = .rgba16Float
    struct Frame: @unchecked Sendable {
        let scene: MTLTexture
        let multisample: MTLTexture?
        let bright: MTLTexture
        let blurred: MTLTexture
    }

    private let device: MTLDevice
    private let extract: MTLComputePipelineState
    private let blur: MTLComputePipelineState
    private let composite: MTLRenderPipelineState
    private var cachedFrame: Frame?
    private var cachedSampleCount = 0

    init(device: MTLDevice, format: MTLPixelFormat) throws {
        self.device = device
        let library = try device.makeDefaultLibrary(bundle: .main)
        func function(_ name: String) throws -> MTLFunction {
            guard let function = library.makeFunction(name: name) else { throw MetalError.shaderFunctionNotFound(name) }
            return function
        }
        extract = try device.makeComputePipelineState(function: function("bloom_extract"))
        blur = try device.makeComputePipelineState(function: function("bloom_blur"))
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try function("vertex_bloom_composite")
        descriptor.fragmentFunction = try function("fragment_bloom_composite")
        descriptor.colorAttachments[0].pixelFormat = format
        composite = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func frame(for pass: MTLRenderPassDescriptor) -> Frame? {
        guard let target = pass.colorAttachments[0].texture else { return nil }
        if let cachedFrame, cachedFrame.scene.width == target.width,
           cachedFrame.scene.height == target.height, cachedSampleCount == target.sampleCount {
            return cachedFrame
        }
        func texture(width: Int, height: Int, format: MTLPixelFormat, usage: MTLTextureUsage) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = usage
            return device.makeTexture(descriptor: descriptor)
        }
        guard let scene = texture(width: target.width, height: target.height, format: Self.scenePixelFormat, usage: [.renderTarget,.shaderRead]),
              let bright = texture(width: max(1,(target.width+3)/4), height: max(1,(target.height+3)/4), format: .rgba16Float, usage: [.shaderRead,.shaderWrite]),
              let blurred = texture(width: bright.width, height: bright.height, format: .rgba16Float, usage: [.shaderRead,.shaderWrite]) else { return nil }
        var multisample: MTLTexture?
        if target.sampleCount > 1 {
            let descriptor = MTLTextureDescriptor()
            descriptor.textureType = .type2DMultisample
            descriptor.pixelFormat = Self.scenePixelFormat
            descriptor.width = target.width
            descriptor.height = target.height
            descriptor.sampleCount = target.sampleCount
            descriptor.storageMode = .private
            descriptor.usage = .renderTarget
            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
            multisample = texture
        }
        let frame = Frame(scene: scene, multisample: multisample, bright: bright, blurred: blurred)
        cachedFrame = frame
        cachedSampleCount = target.sampleCount
        return frame
    }

    func scenePass(frame: Frame, original: MTLRenderPassDescriptor) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = frame.multisample ?? frame.scene
        pass.colorAttachments[0].resolveTexture = frame.multisample == nil ? nil : frame.scene
        pass.colorAttachments[0].loadAction = original.colorAttachments[0].loadAction
        pass.colorAttachments[0].clearColor = original.colorAttachments[0].clearColor
        pass.colorAttachments[0].storeAction = frame.multisample == nil ? .store : .multisampleResolve
        pass.depthAttachment.texture = original.depthAttachment.texture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        return pass
    }

    func encode(frame: Frame, original: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        let threads = MTLSize(width: 8, height: 8, depth: 1)
        // Dispatch full groups for GPUs without non-uniform threadgroup support.
        // Kernels guard pixels outside the texture bounds in the final groups.
        let groups = MTLSize(
            width: (frame.bright.width + threads.width - 1) / threads.width,
            height: (frame.bright.height + threads.height - 1) / threads.height,
            depth: 1
        )
        // Tracked textures are synchronized across encoder boundaries. Explicit
        // compute memory barriers are unavailable on some simulator GPUs.
        func dispatch(_ pipeline: MTLComputePipelineState, source: MTLTexture,
                      destination: MTLTexture, direction: SIMD2<Int32>? = nil) -> Bool {
            guard let compute = commandBuffer.makeComputeCommandEncoder() else { return false }
            compute.label = direction == nil ? "Bloom extraction" : "Bloom blur"
            compute.setComputePipelineState(pipeline)
            compute.setTexture(source, index: 0)
            compute.setTexture(destination, index: 1)
            if var direction {
                compute.setBytes(&direction, length: MemoryLayout<SIMD2<Int32>>.stride, index: 0)
            }
            compute.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
            compute.endEncoding()
            return true
        }
        guard dispatch(extract, source: frame.scene, destination: frame.bright),
              dispatch(blur, source: frame.bright, destination: frame.blurred, direction: SIMD2<Int32>(1,0)),
              dispatch(blur, source: frame.blurred, destination: frame.bright, direction: SIMD2<Int32>(0,1)) else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = original.colorAttachments[0].resolveTexture ?? original.colorAttachments[0].texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Bloom composite"
        encoder.setRenderPipelineState(composite)
        encoder.setFragmentTexture(frame.scene, index: 0)
        encoder.setFragmentTexture(frame.bright, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

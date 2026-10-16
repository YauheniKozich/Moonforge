import Metal

// MARK: - Pipeline Descriptor Factory

/// Factory for creating MTLRenderPipelineDescriptor instances.
/// 
/// This factory encapsulates the boilerplate of pipeline descriptor creation,
/// making PipelineManager cleaner and easier to test.
/// 
/// Thread safety:
/// - This is a stateless struct — all methods are pure functions
/// - Safe to call from any thread
///
/// Usage:
/// ```swift
/// let descriptor = PipelineDescriptorFactory.makeRenderPipelineDescriptor(
///     vertexFunction: vertexFunc,
///     fragmentFunction: fragmentFunc,
///     vertexDescriptor: vertexDesc,
///     colorPixelFormat: .bgra8Unorm,
///     depthStencilPixelFormat: .depth32Float
/// )
///
/// let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
/// ```
struct PipelineDescriptorFactory {

    /// Создать render pipeline descriptor
    static func makeRenderPipelineDescriptor(
        vertexFunction: MTLFunction,
        fragmentFunction: MTLFunction,
        vertexDescriptor: MTLVertexDescriptor,
        colorPixelFormat: MTLPixelFormat,
        depthStencilPixelFormat: MTLPixelFormat,
        label: String = "RenderPipeline",
        sampleCount: Int = 1
    ) -> MTLRenderPipelineDescriptor {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
        descriptor.rasterSampleCount = sampleCount
        
        // Standard configuration
        descriptor.colorAttachments[0].isBlendingEnabled = fragmentFunction.name == MetalConfiguration.Shaders.modelFragment
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        return descriptor
    }

    /// Создать render pipeline descriptor с blending
    static func makeBlendedRenderPipelineDescriptor(
        vertexFunction: MTLFunction,
        fragmentFunction: MTLFunction,
        vertexDescriptor: MTLVertexDescriptor,
        colorPixelFormat: MTLPixelFormat,
        depthStencilPixelFormat: MTLPixelFormat,
        label: String = "RenderPipelineBlended"
    ) -> MTLRenderPipelineDescriptor {
        let descriptor = makeRenderPipelineDescriptor(
            vertexFunction: vertexFunction,
            fragmentFunction: fragmentFunction,
            vertexDescriptor: vertexDescriptor,
            colorPixelFormat: colorPixelFormat,
            depthStencilPixelFormat: depthStencilPixelFormat,
            label: label
        )
        
        descriptor.colorAttachments[0].isBlendingEnabled = true
        
        return descriptor
    }
}

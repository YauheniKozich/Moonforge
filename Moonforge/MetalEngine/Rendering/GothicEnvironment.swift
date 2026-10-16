import MetalKit
import simd

/// Sendable invariant: buffers and textures are private, fully populated during init,
/// and never mutated by the CPU afterward. The shadow texture is written then read
/// on the renderer's single command queue, with one ordered pass per frame. Pipeline
/// and sampler states are immutable; publication/removal is protected by the renderer lock.
final class GothicEnvironment: @unchecked Sendable {
    private struct StoneVertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
        var tint: SIMD3<Float>
    }

    private let vertices: MTLBuffer
    private let vertexCount: Int
    private let stonePipeline: MTLRenderPipelineState
    private let skyPipeline: MTLRenderPipelineState
    private let fireflyPipeline: MTLRenderPipelineState
    private let stoneDepth: MTLDepthStencilState
    private let skyDepth: MTLDepthStencilState
    private let panorama: MTLTexture
    private let moonAtlas: MTLTexture
    private let stoneTexture: MTLTexture
    private let sampler: MTLSamplerState
    private let shadowTexture: MTLTexture
    private let shadowSampler: MTLSamplerState
    private let shadowStonePipeline: MTLRenderPipelineState
    private let shadowModelPipeline: MTLRenderPipelineState
    private let lightMatrix: simd_float4x4

    @MainActor
    init(device: MTLDevice, view: MTKView) throws {
        let library = try device.makeDefaultLibrary(bundle: .main)
        func pipeline(_ vertex: String, _ fragment: String, descriptor: MTLVertexDescriptor? = nil, additive: Bool = false) throws -> MTLRenderPipelineState {
            guard let v = library.makeFunction(name: vertex), let f = library.makeFunction(name: fragment) else {
                throw MetalError.shaderFunctionNotFound("\(vertex)/\(fragment)")
            }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = v
            desc.fragmentFunction = f
            desc.vertexDescriptor = descriptor
            desc.colorAttachments[0].pixelFormat = BloomPostProcessor.scenePixelFormat
            desc.depthAttachmentPixelFormat = view.depthStencilPixelFormat
            desc.rasterSampleCount = view.sampleCount
            if additive {
                desc.colorAttachments[0].isBlendingEnabled = true
                desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                desc.colorAttachments[0].destinationRGBBlendFactor = .one
                desc.colorAttachments[0].sourceAlphaBlendFactor = .zero
                desc.colorAttachments[0].destinationAlphaBlendFactor = .one
            }
            return try device.makeRenderPipelineState(descriptor: desc)
        }
        let descriptor = MTLVertexDescriptor()
        for (index, offset) in [0, 16, 32].enumerated() {
            descriptor.attributes[index].format = .float3
            descriptor.attributes[index].offset = offset
            descriptor.attributes[index].bufferIndex = 0
        }
        descriptor.layouts[0].stride = MemoryLayout<StoneVertex>.stride
        stonePipeline = try pipeline("vertex_stone", "fragment_stone", descriptor: descriptor)
        func shadowPipeline(vertex: String, fragment: String?, layout: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
            let desc = MTLRenderPipelineDescriptor()
            guard let function = library.makeFunction(name: vertex) else { throw MetalError.shaderFunctionNotFound(vertex) }
            desc.vertexFunction = function
            if let fragment {
                guard let function = library.makeFunction(name: fragment) else { throw MetalError.shaderFunctionNotFound(fragment) }
                desc.fragmentFunction = function
            }
            desc.vertexDescriptor = layout
            desc.depthAttachmentPixelFormat = .depth32Float
            return try device.makeRenderPipelineState(descriptor: desc)
        }
        shadowStonePipeline = try shadowPipeline(vertex: "vertex_shadow_stone", fragment: nil, layout: descriptor)
        let modelLayout = MTLVertexDescriptor()
        modelLayout.attributes[0].format = .float3
        modelLayout.attributes[0].bufferIndex = 0
        modelLayout.attributes[3].format = .float2
        modelLayout.attributes[3].offset = 24
        modelLayout.attributes[3].bufferIndex = 0
        modelLayout.layouts[0].stride = 32
        shadowModelPipeline = try shadowPipeline(vertex: "vertex_shadow_model", fragment: "fragment_shadow_model", layout: modelLayout)
        let shadowDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 2048, height: 2048, mipmapped: false)
        shadowDesc.storageMode = .private
        shadowDesc.usage = [.renderTarget,.shaderRead]
        guard let map = device.makeTexture(descriptor: shadowDesc) else { throw MetalError.bufferCreationFailed }
        map.label = "Moon shadow map"
        shadowTexture = map
        let comparison = MTLSamplerDescriptor()
        comparison.minFilter = .linear
        comparison.magFilter = .linear
        comparison.compareFunction = .lessEqual
        comparison.sAddressMode = .clampToEdge
        comparison.tAddressMode = .clampToEdge
        guard let compareState = device.makeSamplerState(descriptor: comparison) else { throw MetalError.bufferCreationFailed }
        shadowSampler = compareState
        let back = MetalConfiguration.Moon.direction
        let eye = back * MetalConfiguration.Moon.shadowCameraDistance
        let referenceUp = abs(back.y) > 0.99 ? SIMD3<Float>(1,0,0) : SIMD3<Float>(0,1,0)
        let right = simd_normalize(simd_cross(referenceUp,back))
        let up = simd_cross(back,right)
        let lightView = simd_float4x4(columns: (
            SIMD4<Float>(right.x,up.x,back.x,0), SIMD4<Float>(right.y,up.y,back.y,0),
            SIMD4<Float>(right.z,up.z,back.z,0), SIMD4<Float>(-simd_dot(right,eye),-simd_dot(up,eye),-simd_dot(back,eye),1)))
        let projection = simd_float4x4(columns: (
            SIMD4<Float>(0.25,0,0,0), SIMD4<Float>(0,0.25,0,0),
            SIMD4<Float>(0,0,-1/Float(19.9),0), SIMD4<Float>(0,0,-0.1/Float(19.9),1)))
        lightMatrix = projection * lightView
        skyPipeline = try pipeline("vertex_gothic_sky", "fragment_gothic_sky")
        fireflyPipeline = try pipeline("vertex_firefly", "fragment_firefly", additive: true)
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .lessEqual
        depth.isDepthWriteEnabled = false
        guard let skyState = device.makeDepthStencilState(descriptor: depth) else { throw MetalError.bufferCreationFailed }
        skyDepth = skyState
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        guard let stoneState = device.makeDepthStencilState(descriptor: depth) else { throw MetalError.bufferCreationFailed }
        stoneDepth = stoneState
        guard let url = Bundle.main.url(forResource: "GothicPanoramaMoonless", withExtension: "png") else {
            throw MetalError.modelLoadingFailed("GothicPanoramaMoonless.png is missing")
        }
        panorama = try MTKTextureLoader(device: device).newTexture(URL: url, options: [
            .SRGB: true, .generateMipmaps: true,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ])
        guard let moonURL = Bundle.main.url(forResource: "GothicPanorama", withExtension: "png") else {
            throw MetalError.modelLoadingFailed("GothicPanorama.png is missing")
        }
        moonAtlas = try MTKTextureLoader(device: device).newTexture(URL: moonURL, options: [
            .SRGB: true, .generateMipmaps: true,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ])
        guard let stoneURL = Bundle.main.url(forResource: "GothicStone", withExtension: "png") else {
            throw MetalError.modelLoadingFailed("GothicStone.png is missing")
        }
        stoneTexture = try MTKTextureLoader(device: device).newTexture(URL: stoneURL, options: [
            .SRGB: true, .generateMipmaps: true,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ])
        let sampling = MTLSamplerDescriptor()
        sampling.minFilter = .linear
        sampling.magFilter = .linear
        sampling.mipFilter = .linear
        sampling.sAddressMode = .repeat
        sampling.tAddressMode = .repeat
        sampling.maxAnisotropy = 16
        guard let samplingState = device.makeSamplerState(descriptor: sampling) else { throw MetalError.bufferCreationFailed }
        sampler = samplingState

        var mesh: [StoneVertex] = []
        func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, tint: SIMD3<Float>) {
            let normal = simd_normalize(simd_cross(b - a, c - a))
            mesh.append(contentsOf: [a, b, c, a, c, d].map { StoneVertex(position: $0, normal: normal, tint: tint) })
        }
        let stone = SIMD3<Float>(0.19, 0.23, 0.28)
        func box(center: SIMD3<Float>, size: SIMD3<Float>, tint: SIMD3<Float>) {
            let lo = center - size * 0.5, hi = center + size * 0.5
            let p: [SIMD3<Float>] = [
                [lo.x,lo.y,lo.z], [hi.x,lo.y,lo.z], [hi.x,hi.y,lo.z], [lo.x,hi.y,lo.z],
                [lo.x,lo.y,hi.z], [hi.x,lo.y,hi.z], [hi.x,hi.y,hi.z], [lo.x,hi.y,hi.z]
            ]
            for face in [[4,5,6,7], [1,0,3,2], [0,4,7,3], [5,1,2,6], [3,7,6,2], [0,1,5,4]] {
                quad(p[face[0]], p[face[1]], p[face[2]], p[face[3]], tint: tint)
            }
        }
        func ellipsoid(center: SIMD3<Float>, radii: SIMD3<Float>, tint: SIMD3<Float>, openFace: Bool = false) {
            for latitude in 0..<16 {
                for longitude in 0..<32 {
                    func point(_ row: Int, _ column: Int) -> StoneVertex {
                        let theta = Float(row) * .pi / 16
                        let phi = Float(column) * 2 * .pi / 32
                        let direction = SIMD3<Float>(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
                        return StoneVertex(position: center + direction * radii,
                                           normal: simd_normalize(direction / radii), tint: tint)
                    }
                    let a = point(latitude, longitude), b = point(latitude+1, longitude)
                    let c = point(latitude+1, longitude+1), d = point(latitude, longitude+1)
                    let midpoint = (a.position+b.position+c.position+d.position) * 0.25 - center
                    if openFace, midpoint.z > 0 {
                        let eye = SIMD2<Float>((abs(midpoint.x)-0.062)/0.055, (midpoint.y+0.026)/0.045)
                        if simd_length_squared(eye) < 1 { continue }
                        if abs(midpoint.x) < 0.027, midpoint.y < -0.065 { continue }
                    }
                    mesh.append(contentsOf: [a,b,c,a,c,d])
                }
            }
        }
        func skullLantern(center: SIMD3<Float>) {
            let firstVertex = mesh.count
            // Negative red marks bone/cavity materials; red > 1 marks emission.
            let bone = SIMD3<Float>(-0.76,0.71,0.6)
            let cavity = SIMD3<Float>(-0.006,0.004,0.003)
            box(center: center+[0,-0.1,-0.14], size: [0.13,0.05,0.24], tint: bone)
            // Human proportions: rounded vault, broad orbital cavities and a narrow mandible.
            ellipsoid(center: center+[0,0.03,-0.025], radii: [0.13,0.12,0.105], tint: bone, openFace: true)
            for side: Float in [-1,1] {
                let eye = center + SIMD3<Float>(side*0.062,0.004,0.062)
                // Recessed dark bowls, raised orbital rims, and small glowing eyes.
                for segment in 0..<24 {
                    let a = Float(segment) * 2 * .pi / 24, b = Float(segment+1) * 2 * .pi / 24
                    func ring(_ angle: Float, inner: Bool) -> SIMD3<Float> {
                        eye + SIMD3<Float>(cos(angle)*(inner ? 0.042 : 0.055),
                                           sin(angle)*(inner ? 0.033 : 0.045), inner ? -0.014 : 0.004)
                    }
                    quad(ring(a,inner:false),ring(b,inner:false),ring(b,inner:true),ring(a,inner:true),tint: bone)
                    quad(ring(a,inner:true),ring(b,inner:true),eye+[0,0,-0.035],eye+[0,0,-0.035],tint: cavity)
                }
                ellipsoid(center: eye+[0,0,-0.026], radii: [0.027,0.018,0.004], tint: [1.5,0.32,0.045])
                ellipsoid(center: center+[side*0.062,0.047,0.045], radii: [0.054,0.012,0.027], tint: bone)
                ellipsoid(center: center+[side*0.107,-0.048,0.024], radii: [0.034,0.025,0.044], tint: bone)
                ellipsoid(center: center+[side*0.077,-0.127,0], radii: [0.018,0.063,0.027], tint: bone)
            }
            ellipsoid(center: center+[0,-0.077,0.039], radii: [0.083,0.026,0.041], tint: bone)
            ellipsoid(center: center+[0,0.006,0.05], radii: [0.014,0.035,0.021], tint: bone)
            quad(center+[-0.024,-0.059,0.087],center+[0.024,-0.059,0.087],center+[0,-0.018,0.087],center+[-0.024,-0.059,0.087],tint: cavity)
            ellipsoid(center: center+[0,-0.181,0.025], radii: [0.081,0.019,0.044], tint: bone)
            box(center: center+[0,-0.11,0.065], size: [0.145,0.027,0.017], tint: cavity)
            for tooth in 0..<6 {
                let x = (Float(tooth)-2.5)*0.024
                box(center: center+[x,-0.094,0.078], size: [0.019,0.027,0.022], tint: bone)
                box(center: center+[x,-0.135,0.077], size: [0.018,0.023,0.021], tint: bone)
            }
            // Small wall-mounted lanterns rather than oversized decorative heads.
            for index in firstVertex..<mesh.count {
                mesh[index].position = center + (mesh[index].position - center) * 0.55
            }
        }
        quad([-14,-1.2,14], [14,-1.2,14], [14,-1.2,-14], [-14,-1.2,-14], tint: stone)
        // Two concentric steps form a genuine raised stone pedestal.
        for (radius, bottom, top) in [(Float(1.18), Float(-1.2), Float(-1.1)), (1.05, -1.1, -1.0)] {
            for i in 0..<96 {
                let a = Float(i) * 2 * .pi / 96, b = Float(i + 1) * 2 * .pi / 96
                let p = SIMD3<Float>(sin(a) * radius, top, cos(a) * radius)
                let q = SIMD3<Float>(sin(b) * radius, top, cos(b) * radius)
                quad([0,top,0], p, q, [0,top,0], tint: stone * 1.25)
                quad(p, [p.x,bottom,p.z], [q.x,bottom,q.z], q, tint: stone)
            }
        }
        for centerX: Float in [-1.5, 1.5] {
            let z: Float = -2.4
            for side: Float in [-1, 1] {
                let x = centerX + side * 0.7
                for row in 0..<8 {
                    box(center: [x, -1.05 + Float(row) * 0.21, z], size: [0.28,0.205,0.4], tint: stone)
                }
                box(center: [x,-1.09,z], size: [0.43,0.22,0.56], tint: stone)
                box(center: [x,0.61,z], size: [0.38,0.13,0.5], tint: stone)
                // Pointed arches: extruded masonry wedges along each rising half.
                for segment in 0..<12 {
                    func point(_ t: Float, outer: Bool, front: Bool) -> SIMD3<Float> {
                        let width: Float = outer ? 0.91 : 0.67
                        return [centerX + side * width * (1 - t),
                                0.66 + 1.12 * sin(t * .pi / 2) + (outer ? 0.17 : 0),
                                z + (front ? 0.2 : -0.2)]
                    }
                    let t = Float(segment) / 12, u = Float(segment + 1) / 12 - 0.003
                    let a = point(t, outer: false, front: true), b = point(u, outer: false, front: true)
                    let c = point(u, outer: true, front: true), d = point(t, outer: true, front: true)
                    quad(a,b,c,d,tint: stone)
                    let shift = SIMD3<Float>(0,0,-0.4)
                    quad(d+shift,c+shift,b+shift,a+shift,tint: stone)
                    quad(a,a+shift,b+shift,b,tint: stone)
                    quad(c,c+shift,d+shift,d,tint: stone)
                }
                skullLantern(center: [x,-0.25,z+0.37])
            }
        }
        vertexCount = mesh.count
        guard let buffer = device.makeBuffer(bytes: mesh, length: mesh.count * MemoryLayout<StoneVertex>.stride, options: .storageModeShared) else {
            throw MetalError.bufferCreationFailed
        }
        vertices = buffer
    }

    func draw(using encoder: MTLRenderCommandEncoder, uniforms: Uniforms) {
        var lighting = lightMatrix
        encoder.setFragmentBytes(&lighting, length: MemoryLayout<simd_float4x4>.stride, index: 4)
        encoder.setFragmentTexture(shadowTexture, index: 5)
        encoder.setFragmentSamplerState(shadowSampler, index: 1)
        encoder.setRenderPipelineState(skyPipeline)
        encoder.setDepthStencilState(skyDepth)
        var inverse = simd_inverse(uniforms.projectionMatrix * uniforms.viewMatrix)
        encoder.setVertexBytes(&inverse, length: MemoryLayout<simd_float4x4>.stride, index: 2)
        encoder.setFragmentTexture(panorama, index: 0)
        // Separate celestial disk; shared with the subsequent stone/model reflection passes.
        encoder.setFragmentTexture(moonAtlas, index: 7)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.setRenderPipelineState(stonePipeline)
        encoder.setDepthStencilState(stoneDepth)
        var sceneUniforms = uniforms
        sceneUniforms.modelMatrix = matrix_identity_float4x4
        encoder.setVertexBytes(&sceneUniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setFragmentTexture(stoneTexture, index: 0)
        // Shared by stone and the model material pass encoded afterward.
        encoder.setFragmentTexture(panorama, index: 6)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
    }

    func encodeShadows(using commandBuffer: MTLCommandBuffer, snapshot: RenderSnapshot) {
        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = shadowTexture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .store
        pass.depthAttachment.clearDepth = 1
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Moon shadow pass"
        encoder.setDepthStencilState(stoneDepth)
        encoder.setDepthBias(1, slopeScale: 1.5, clamp: 0.01)
        encoder.setRenderPipelineState(shadowStonePipeline)
        var transform = lightMatrix
        encoder.setVertexBytes(&transform, length: MemoryLayout<simd_float4x4>.stride, index: 2)
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        encoder.setRenderPipelineState(shadowModelPipeline)
        transform = lightMatrix * snapshot.uniforms.modelMatrix
        encoder.setVertexBytes(&transform, length: MemoryLayout<simd_float4x4>.stride, index: 2)
        encoder.setFragmentSamplerState(snapshot.sampler ?? sampler, index: 0)
        for submesh in snapshot.submeshes {
            encoder.setVertexBuffer(submesh.vertexBuffer, offset: submesh.vertexBufferOffset, index: 0)
            encoder.setFragmentTexture(submesh.baseColorTexture, index: 0)
            var textured: UInt32 = submesh.useBaseColorTexture ? 1 : 0
            encoder.setFragmentBytes(&textured, length: MemoryLayout<UInt32>.stride, index: 3)
            var baseAlpha = submesh.baseColor.w
            encoder.setFragmentBytes(&baseAlpha, length: MemoryLayout<Float>.stride, index: 4)
            encoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount,
                indexType: submesh.indexType, indexBuffer: submesh.indexBuffer, indexBufferOffset: submesh.indexBufferOffset)
        }
        encoder.endEncoding()
    }

    func drawFireflies(using encoder: MTLRenderCommandEncoder, uniforms: Uniforms, time: Float) {
        encoder.setRenderPipelineState(fireflyPipeline)
        // Test scene depth but do not occlude other particles or write to the depth buffer.
        encoder.setDepthStencilState(skyDepth)
        var camera = uniforms
        var animationTime = time
        encoder.setVertexBytes(&camera, length: MemoryLayout<Uniforms>.stride, index: 2)
        encoder.setVertexBytes(&animationTime, length: MemoryLayout<Float>.stride, index: 5)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: 50)
    }
}

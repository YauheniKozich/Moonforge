//
//  ModelIOGeometry.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Metal
import MetalKit
import ModelIO
import simd
import QuartzCore

// MARK: - ModelIO Geometry

final class ModelIOGeometry: GeometrySource {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let vertexBufferOffset: Int
    let indexBufferOffset: Int
    let indexCount: Int
    let indexType: MTLIndexType
    let vertexDescriptor: MTLVertexDescriptor
    let primitiveType: MTLPrimitiveType
    let preparationSummary: String
    let loadStatus: ModelLoadStatus
    let shaderNames: (vertex: String, fragment: String) = (
        MetalConfiguration.Shaders.modelVertex,
        MetalConfiguration.Shaders.modelFragment
    )
    let submeshes: [SubmeshGeometry]
    let preferredCameraDistance: Float?
    let boundsSize: SIMD3<Float>?
    private let logger: MetalLogger?

    init(
        device: MTLDevice,
        resourceName: String,
        ext: String = "obj",
        bundle: Bundle = .main,
        preferredCameraDistance: Float? = nil,
        logger: MetalLogger? = nil
    ) throws {
        self.preferredCameraDistance = preferredCameraDistance
        self.logger = logger
        let preparationStart = CACurrentMediaTime()
        let url = bundle.url(forResource: resourceName, withExtension: ext)
            ?? bundle.url(forResource: resourceName, withExtension: ext, subdirectory: "Models")
        guard let url else {
            throw MetalError.modelLoadingFailed("Resource not found: \(resourceName).\(ext)")
        }

        let allocator = MTKMeshBufferAllocator(device: device)
        let mdlDescriptor = ModelIOGeometry.makeMDLVertexDescriptor()
        let asset = MDLAsset(url: url, vertexDescriptor: mdlDescriptor, bufferAllocator: allocator)

        try Task.checkCancellation()
        asset.loadTextures()
        let assetReady = CACurrentMediaTime()

        let mdlMeshes = asset.childObjects(of: MDLMesh.self).compactMap { $0 as? MDLMesh }
        guard !mdlMeshes.isEmpty else {
            throw MetalError.modelLoadingFailed("No mesh found in asset")
        }
        var generatedNormals = false
        var generatedUVs = false

        for mdlMesh in mdlMeshes {
            try Task.checkCancellation()
            if mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal, as: .float3) == nil {
                mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.0)
                generatedNormals = true
            }

            if mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeTextureCoordinate, as: .float2) == nil {
                mdlMesh.addUnwrappedTextureCoordinates(forAttributeNamed: MDLVertexAttributeTextureCoordinate)
                generatedUVs = true
            }

            mdlMesh.vertexDescriptor = mdlDescriptor
        }

        boundsSize = try Self.bakeTransforms(in: mdlMeshes, normalizeSize: ext.lowercased() == "usdz")

        let metalMeshes: [(mdl: MDLMesh, mtk: MTKMesh)] = try mdlMeshes.map { mdlMesh in
            do {
                return (mdlMesh, try MTKMesh(mesh: mdlMesh, device: device))
            } catch {
                throw MetalError.modelLoadingFailed("MTKMesh creation failed: \(error.localizedDescription)")
            }
        }

        guard let firstMesh = metalMeshes.first,
              let firstVertexBufferInfo = firstMesh.mtk.vertexBuffers.first,
              !firstMesh.mtk.submeshes.isEmpty else {
            throw MetalError.modelLoadingFailed("No submesh found in asset")
        }

        guard let mtlDescriptor = MTKMetalVertexDescriptorFromModelIO(mdlDescriptor) else {
            throw MetalError.modelLoadingFailed("Failed to convert ModelIO vertex descriptor")
        }

        let firstSubmesh = firstMesh.mtk.submeshes[0]
        vertexBuffer = firstVertexBufferInfo.buffer
        indexBuffer = firstSubmesh.indexBuffer.buffer
        vertexBufferOffset = firstVertexBufferInfo.offset
        indexBufferOffset = firstSubmesh.indexBuffer.offset
        indexCount = firstSubmesh.indexCount
        indexType = firstSubmesh.indexType
        primitiveType = firstSubmesh.primitiveType
        vertexDescriptor = mtlDescriptor
        let meshesReady = CACurrentMediaTime()
        
        var createdSubmeshes: [SubmeshGeometry] = []
        let textureLoader = MTKTextureLoader(device: device)

        for (mdlMesh, mtkMesh) in metalMeshes {
            try Task.checkCancellation()
            guard let vertexBufferInfo = mtkMesh.vertexBuffers.first else { continue }

            for (index, mtkSubmesh) in mtkMesh.submeshes.enumerated() {
                try Task.checkCancellation()
                guard mtkSubmesh.indexType == .uint16 || mtkSubmesh.indexType == .uint32 else {
                    continue
                }

                let indexBufferInfo = mtkSubmesh.indexBuffer

                let mdlSubmesh = index < mdlMesh.submeshes?.count ?? 0
                    ? mdlMesh.submeshes?[index] as? MDLSubmesh
                    : nil

                let material = mdlSubmesh?.material
                let materialData = try Self.resolveMaterialData(
                    from: material,
                    assetDirectory: url.deletingLastPathComponent(),
                    textureLoader: textureLoader,
                    logger: logger
                )

                var sortCenter = SIMD3<Float>.zero
                if let positions = mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3),
                   mtkSubmesh.indexCount > 0 {
                    let indices = indexBufferInfo.buffer.contents().advanced(by: indexBufferInfo.offset)
                    var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
                    var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
                    for element in 0..<mtkSubmesh.indexCount {
                        if element.isMultiple(of: 4096) { try Task.checkCancellation() }
                        let vertexIndex: Int
                        if mtkSubmesh.indexType == .uint16 {
                            vertexIndex = Int(indices.load(fromByteOffset: element * 2, as: UInt16.self))
                        } else {
                            vertexIndex = Int(indices.load(fromByteOffset: element * 4, as: UInt32.self))
                        }
                        let position = Self.readFloat3(from: positions.dataStart.advanced(by: vertexIndex * positions.stride))
                        minimum = simd_min(minimum, position)
                        maximum = simd_max(maximum, position)
                    }
                    sortCenter = (minimum + maximum) * 0.5
                }
                let submesh = SubmeshGeometry(
                    vertexBuffer: vertexBufferInfo.buffer,
                    indexBuffer: indexBufferInfo.buffer,
                    indexCount: mtkSubmesh.indexCount,
                    indexType: mtkSubmesh.indexType,
                    primitiveType: mtkSubmesh.primitiveType,
                    baseColorTexture: materialData.baseColorTexture,
                    normalTexture: materialData.normalTexture,
                    roughnessTexture: materialData.roughnessTexture,
                    metallicTexture: materialData.metallicTexture,
                    emissiveTexture: materialData.emissiveTexture,
                    baseColor: materialData.baseColor,
                    emissiveColor: materialData.emissiveColor,
                    roughness: materialData.roughness,
                    metallic: materialData.metallic,
                    vertexBufferOffset: vertexBufferInfo.offset,
                    indexBufferOffset: indexBufferInfo.offset,
                    sortCenter: sortCenter
                )
                createdSubmeshes.append(submesh)
            }
        }

        guard !createdSubmeshes.isEmpty else {
            throw MetalError.modelLoadingFailed("No supported submeshes found in asset")
        }

        submeshes = createdSubmeshes
        loadStatus = (generatedNormals || generatedUVs) ? .missingAttributes : .ok
        let now = CACurrentMediaTime()
        let assetMs = (assetReady - preparationStart) * 1000
        let meshesMs = (meshesReady - assetReady) * 1000
        let materialsMs = (now - meshesReady) * 1000
        let totalMs = (now - preparationStart) * 1000
        preparationSummary = "Model preparation '\(resourceName)': "
            + "asset_ms=\(assetMs), "
            + "meshes_ms=\(meshesMs), "
            + "materials_ms=\(materialsMs), "
            + "total_ms=\(totalMs), "
            + "mainThread=\(Thread.isMainThread)"
        logger?.log(preparationSummary, level: .debug)
        logger?.log("ModelIOGeometry: Created \(submeshes.count) submeshes across \(metalMeshes.count) meshes", level: .debug)
    }

    private static func makeMDLVertexDescriptor() -> MDLVertexDescriptor {
        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        descriptor.attributes[2] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3,
            offset: 12,
            bufferIndex: 0
        )
        descriptor.attributes[3] = MDLVertexAttribute(
            name: MDLVertexAttributeTextureCoordinate,
            format: .float2,
            offset: 24,
            bufferIndex: 0
        )
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: 32)
        return descriptor
    }

    /// Preserve the authored hierarchy, then center USDZ assets at a consistent inspection scale.
    private static func bakeTransforms(in meshes: [MDLMesh], normalizeSize: Bool) throws -> SIMD3<Float> {
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for mesh in meshes {
            guard let positions = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3) else {
                throw MetalError.modelLoadingFailed("Mesh has no position attribute: \(mesh.name)")
            }
            let transform = MDLTransform.globalTransform(with: mesh, atTime: 0)
            let linear = float3x3(SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                                   SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                                   SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
            guard abs(simd_determinant(linear)) > Float.leastNormalMagnitude else {
                throw MetalError.modelLoadingFailed("Mesh has a singular transform: \(mesh.name)")
            }
            let normalTransform = simd_transpose(simd_inverse(linear))
            let normals = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal, as: .float3)
            for index in 0..<mesh.vertexCount {
                let pointer = positions.dataStart.advanced(by: index * positions.stride)
                let local = readFloat3(from: pointer)
                let transformed = transform * SIMD4<Float>(local, 1)
                let world = SIMD3<Float>(transformed.x, transformed.y, transformed.z)
                guard world.x.isFinite, world.y.isFinite, world.z.isFinite else {
                    throw MetalError.modelLoadingFailed("Mesh has non-finite positions: \(mesh.name)")
                }
                writeFloat3(world, to: pointer)
                minimum = simd_min(minimum, world)
                maximum = simd_max(maximum, world)
                if let normals {
                    let pointer = normals.dataStart.advanced(by: index * normals.stride)
                    let normal = normalTransform * readFloat3(from: pointer)
                    if simd_length_squared(normal) > 0 {
                        writeFloat3(simd_normalize(normal), to: pointer)
                    }
                }
            }
        }
        let center = (minimum + maximum) * 0.5
        let extent = maximum - minimum
        let longestSide = max(extent.x, max(extent.y, extent.z))
        guard longestSide.isFinite, longestSide > 0 else {
            throw MetalError.modelLoadingFailed("Asset has empty bounds")
        }
        guard normalizeSize else { return extent }
        let scale: Float = 2.0 / longestSide
        for mesh in meshes {
            guard let positions = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3) else { continue }
            for index in 0..<mesh.vertexCount {
                let pointer = positions.dataStart.advanced(by: index * positions.stride)
                writeFloat3((readFloat3(from: pointer) - center) * scale, to: pointer)
            }
        }
        return extent * scale
    }

    private static func readFloat3(from pointer: UnsafeMutableRawPointer) -> SIMD3<Float> {
        SIMD3<Float>(pointer.loadUnaligned(as: Float.self),
                     pointer.loadUnaligned(fromByteOffset: 4, as: Float.self),
                     pointer.loadUnaligned(fromByteOffset: 8, as: Float.self))
    }

    private static func writeFloat3(_ value: SIMD3<Float>, to pointer: UnsafeMutableRawPointer) {
        pointer.storeBytes(of: value.x, as: Float.self)
        pointer.storeBytes(of: value.y, toByteOffset: 4, as: Float.self)
        pointer.storeBytes(of: value.z, toByteOffset: 8, as: Float.self)
    }

    private struct MaterialData {
        var baseColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
        var baseColorTexture: MTLTexture?
        var normalTexture: MTLTexture?
        var roughnessTexture: MTLTexture?
        var metallicTexture: MTLTexture?
        var emissiveTexture: MTLTexture?
        var emissiveColor: SIMD3<Float> = .zero
        var roughness: Float = 1.0
        var metallic: Float = 0.0
    }

    private static func resolveBaseColor(from material: MDLMaterial?) -> SIMD4<Float> {
        guard let property = material?.property(with: .baseColor) else {
            return SIMD4<Float>(1, 1, 1, 1)
        }

        switch property.type {
        case .float4:
            let color = property.float4Value
            return SIMD4<Float>(color.x, color.y, color.z, color.w)
        case .float3:
            let color = property.float3Value
            return SIMD4<Float>(color.x, color.y, color.z, 1)
        case .float:
            let value = property.floatValue
            return SIMD4<Float>(value, value, value, 1)
        case .color:
            let color = property.float4Value
            return SIMD4<Float>(color.x, color.y, color.z, color.w)
        default:
            return SIMD4<Float>(1, 1, 1, 1)
        }
    }

    private static func resolveFloat(from material: MDLMaterial?, semantic: MDLMaterialSemantic, fallback: Float) -> Float {
        guard let property = material?.property(with: semantic) else {
            return fallback
        }

        switch property.type {
        case .float:
            return property.floatValue
        case .float2:
            return property.float2Value.x
        case .float3:
            return property.float3Value.x
        case .float4:
            return property.float4Value.x
        default:
            return fallback
        }
    }

    private static func resolveColor3(from material: MDLMaterial?, semantic: MDLMaterialSemantic) -> SIMD3<Float> {
        guard let property = material?.property(with: semantic) else {
            return .zero
        }

        switch property.type {
        case .float3:
            let value = property.float3Value
            return SIMD3<Float>(value.x, value.y, value.z)
        case .float4:
            let value = property.float4Value
            return SIMD3<Float>(value.x, value.y, value.z)
        case .color:
            let value = property.float4Value
            return SIMD3<Float>(value.x, value.y, value.z)
        default:
            return .zero
        }
    }

    private static func resolveTexture(
        from material: MDLMaterial?, semantic: MDLMaterialSemantic,
        assetDirectory: URL, textureLoader: MTKTextureLoader,
        options: [MTKTextureLoader.Option: Any], logger: MetalLogger?
    ) throws -> MTLTexture? {
        var requested = false
        var lastFailure: String?
        let mapName = String(describing: semantic)
        for property in material?.properties(with: semantic) ?? [] {
            let candidate: () throws -> MTLTexture
            if let texture = property.textureSamplerValue?.texture {
                candidate = { try textureLoader.newTexture(texture: texture, options: options) }
            } else if property.type == .URL, let url = property.urlValue {
                candidate = { try textureLoader.newTexture(URL: url, options: options) }
            } else if property.type == .string, let path = property.stringValue, !path.isEmpty {
                candidate = { try textureLoader.newTexture(URL: assetDirectory.appendingPathComponent(path), options: options) }
            } else {
                if property.type == .texture || property.type == .URL { requested = true }
                continue
            }
            requested = true
            do {
                guard let texture = colorTextureView(try candidate(), options: options) else {
                    throw MetalError.textureCreationFailed
                }
                logger?.log("Material '\(material?.name ?? "unnamed")' map=\(mapName): \(texture.width)x\(texture.height), format=\(texture.pixelFormat.rawValue)", level: .debug)
                return texture
            } catch {
                lastFailure = String(describing: error)
                logger?.log("Material '\(material?.name ?? "unnamed")' map=\(mapName), property='\(property.name)': \(error)", level: .warning)
            }
        }
        if requested {
            throw MetalError.modelLoadingFailed("Material '\(material?.name ?? "unnamed")' texture map \(mapName) could not be loaded: \(lastFailure ?? "missing texture data or URL")")
        }
        return nil
    }

    private static func colorTextureView(
        _ texture: MTLTexture,
        options: [MTKTextureLoader.Option: Any]
    ) -> MTLTexture? {
        guard options[.SRGB] as? Bool == true else { return texture }
        // ModelIO-backed textures can ignore the loader's SRGB option. Reinterpret
        // their authored color bytes so Metal decodes them before lighting.
        switch texture.pixelFormat {
        case .rgba8Unorm:
            return texture.makeTextureView(pixelFormat: .rgba8Unorm_srgb)
        case .bgra8Unorm:
            return texture.makeTextureView(pixelFormat: .bgra8Unorm_srgb)
        default:
            return texture
        }
    }

    private static func resolveMaterialData(
        from material: MDLMaterial?,
        assetDirectory: URL,
        textureLoader: MTKTextureLoader,
        logger: MetalLogger?
    ) throws -> MaterialData {
        let colorOptions: [MTKTextureLoader.Option: Any] = [
            .generateMipmaps: true,
            .textureUsage: MTLTextureUsage.shaderRead.union(.pixelFormatView).rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .origin: MTKTextureLoader.Origin.bottomLeft,
            .SRGB: true
        ]

        var dataOptions = colorOptions
        dataOptions[.SRGB] = false
        let baseColorTexture = try resolveTexture(
            from: material,
            semantic: .baseColor,
            assetDirectory: assetDirectory,
            textureLoader: textureLoader,
            options: colorOptions, logger: logger
        )
        let emissiveTexture = try resolveTexture(
            from: material,
            semantic: .emission,
            assetDirectory: assetDirectory,
            textureLoader: textureLoader,
            options: colorOptions, logger: logger
        )
        let metallicTexture = try resolveTexture(
            from: material,
            semantic: .metallic,
            assetDirectory: assetDirectory,
            textureLoader: textureLoader,
            options: dataOptions, logger: logger
        )
        let roughnessTexture = try resolveTexture(
            from: material,
            semantic: .roughness,
            assetDirectory: assetDirectory,
            textureLoader: textureLoader,
            options: dataOptions, logger: logger
        )
        return MaterialData(
            baseColor: baseColorTexture == nil ? resolveBaseColor(from: material) : SIMD4<Float>(repeating: 1),
            baseColorTexture: baseColorTexture,
            normalTexture: try resolveTexture(
                from: material,
                semantic: .tangentSpaceNormal,
                assetDirectory: assetDirectory,
                textureLoader: textureLoader,
                options: dataOptions, logger: logger
            ),
            roughnessTexture: roughnessTexture,
            metallicTexture: metallicTexture,
            emissiveTexture: emissiveTexture,
            emissiveColor: emissiveTexture == nil ? resolveColor3(from: material, semantic: .emission) : SIMD3<Float>(repeating: 1),
            roughness: roughnessTexture == nil
                ? resolveFloat(from: material, semantic: .roughness, fallback: 1.0)
                : 1.0,
            metallic: metallicTexture == nil
                ? resolveFloat(from: material, semantic: .metallic, fallback: 0.0)
                : 1.0
        )
    }
}

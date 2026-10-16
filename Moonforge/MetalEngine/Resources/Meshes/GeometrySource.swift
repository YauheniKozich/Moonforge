//
//  GeometrySource.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Metal
import MetalKit

// MARK: - Submesh

/// Представляет один submesh с собственным материалом и текстурой
struct SubmeshGeometry {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let vertexBufferOffset: Int
    let indexBufferOffset: Int
    let indexCount: Int
    let indexType: MTLIndexType
    let primitiveType: MTLPrimitiveType
    let baseColorTexture: MTLTexture?
    let normalTexture: MTLTexture?
    let roughnessTexture: MTLTexture?
    let metallicTexture: MTLTexture?
    let emissiveTexture: MTLTexture?
    let useBaseColorTexture: Bool
    let baseColor: SIMD4<Float>
    let emissiveColor: SIMD3<Float>
    let roughness: Float
    let metallic: Float
    let sortCenter: SIMD3<Float>

    init(
        vertexBuffer: MTLBuffer,
        indexBuffer: MTLBuffer,
        indexCount: Int,
        indexType: MTLIndexType,
        primitiveType: MTLPrimitiveType = .triangle,
        baseColorTexture: MTLTexture? = nil,
        normalTexture: MTLTexture? = nil,
        roughnessTexture: MTLTexture? = nil,
        metallicTexture: MTLTexture? = nil,
        emissiveTexture: MTLTexture? = nil,
        baseColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        emissiveColor: SIMD3<Float> = .zero,
        roughness: Float = 1.0,
        metallic: Float = 0.0,
        vertexBufferOffset: Int = 0,
        indexBufferOffset: Int = 0,
        sortCenter: SIMD3<Float> = .zero
    ) {
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        self.vertexBufferOffset = vertexBufferOffset
        self.indexBufferOffset = indexBufferOffset
        self.indexCount = indexCount
        self.indexType = indexType
        self.primitiveType = primitiveType
        self.baseColorTexture = baseColorTexture
        self.normalTexture = normalTexture
        self.roughnessTexture = roughnessTexture
        self.metallicTexture = metallicTexture
        self.emissiveTexture = emissiveTexture
        self.useBaseColorTexture = baseColorTexture != nil
        self.baseColor = baseColor
        self.emissiveColor = emissiveColor
        self.roughness = roughness
        self.metallic = metallic
        self.sortCenter = sortCenter
    }
}

// MARK: - Geometry Source

/// Source of renderable geometry buffers and layout metadata.
protocol GeometrySource {
    var vertexBuffer: MTLBuffer { get }
    var indexBuffer: MTLBuffer { get }
    var vertexBufferOffset: Int { get }
    var indexBufferOffset: Int { get }
    var indexCount: Int { get }
    var indexType: MTLIndexType { get }
    var vertexDescriptor: MTLVertexDescriptor { get }
    var primitiveType: MTLPrimitiveType { get }
    var shaderNames: (vertex: String, fragment: String) { get }

    /// Массив submeshes для multi-pass рендеринга
    /// Если пустой — используется основной indexBuffer/vertexBuffer
    var submeshes: [SubmeshGeometry] { get }

    /// Предпочтительная дистанция камеры для этой геометрии.
    /// Позволяет большим моделям вроде USDZ стартовать дальше от камеры.
    var preferredCameraDistance: Float? { get }
    var boundsSize: SIMD3<Float>? { get }
}

extension GeometrySource {
    var vertexBufferOffset: Int { 0 }
    var indexBufferOffset: Int { 0 }
    var boundsSize: SIMD3<Float>? { nil }
}

//
//  RenderSnapshot.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Metal

// MARK: - Submesh Snapshot

/// Snapshot данных для одного submesh в multi-pass рендеринге
struct SubmeshSnapshot {
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
}

// MARK: - RenderSnapshot

/// Value type — безопасно копируется из Main thread в Metal thread.
/// @unchecked Sendable: MTL-ресурсы потокобезопасны для чтения,
/// но Swift Concurrency об этом не знает.
struct RenderSnapshot: @unchecked Sendable {
    let rotation:     SIMD3<Float>
    let uniforms:     Uniforms
    let pipeline:     MTLRenderPipelineState
    let depthStencil: MTLDepthStencilState
    let vertexBuffer: MTLBuffer
    let vertexBufferOffset: Int
    let indexBufferOffset: Int
    let sampler:      MTLSamplerState?

    /// Массив submeshes для multi-pass рендеринга
    /// Если пустой — используется legacy режим с одним indexBuffer/texture
    let submeshes: [SubmeshSnapshot]

    // Legacy поля для обратной совместимости (если submeshes пуст)
    let indexBuffer:  MTLBuffer
    let indexCount:   Int
    let indexType:    MTLIndexType
    let primitiveType: MTLPrimitiveType
    let texture:      MTLTexture?
    let useTexture:   Bool
}

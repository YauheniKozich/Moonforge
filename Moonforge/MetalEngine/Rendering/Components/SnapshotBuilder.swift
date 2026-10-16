//
//  SnapshotBuilder.swift
//  Moonforge
//
//  Created on 20.03.26.
//

import Metal
import simd

// MARK: - Snapshot Builder

/// Pure value-type builder for creating RenderSnapshot instances.
/// 
/// This is the core of the "double buffering" approach:
/// - Main thread mutates state (camera, rotation, etc.)
/// - Render thread reads immutable snapshot copies
/// - No data races, no locks needed during rendering
/// 
/// Thread safety:
/// - This struct is stateless — all methods are pure functions
/// - Safe to call from any thread
/// - Typically called from render thread before each frame
///
/// Usage:
/// ```swift
/// let snapshot = SnapshotBuilder.build(
///     geometry: geometry,
///     pipeline: pipeline,
///     depthStencil: depthStencil,
///     rotation: rotationState.getSnapshot(),
///     cameraState: cameraComponent.getStateSnapshot(),
///     drawableSize: view.drawableSize,
///     sampler: samplerState,
///     modelTextureEnabled: modelTextureEnabled,
///     texture: texture
/// )
/// ```
struct SnapshotBuilder {
    
    /// Build a complete render snapshot from current state.
    ///
    /// - Parameters:
    ///   - geometry: Source geometry with vertex/index buffers
    ///   - pipeline: Render pipeline state for this geometry
    ///   - depthStencil: Depth stencil state
    ///   - rotation: Current rotation state (from RotationStateManager)
    ///   - cameraState: Current camera state (from CameraComponent)
    ///   - drawableSize: Size of the drawable in points
    ///   - sampler: Sampler state for texture sampling
    ///   - modelTextureEnabled: Whether model textures should be used
    ///   - texture: Optional texture for rendering
    ///
    /// - Returns: Complete RenderSnapshot ready for rendering
    static func build(
        geometry: GeometrySource,
        pipeline: MTLRenderPipelineState,
        depthStencil: MTLDepthStencilState,
        rotation: SIMD3<Float>,
        cameraState: CameraState,
        drawableSize: CGSize,
        sampler: MTLSamplerState?,
        modelTextureEnabled: Bool,
        texture: MTLTexture?
    ) -> RenderSnapshot {
        // Build submeshes for multi-pass rendering
        let submeshSnapshots = buildSubmeshSnapshots(
            from: geometry.submeshes,
            modelTextureEnabled: modelTextureEnabled
        )

        // Calculate matrices
        let projectionMatrix = buildProjectionMatrix(for: drawableSize)
        var fittedCamera = cameraState
        // An authored camera distance takes precedence over automatic viewport fitting.
        if geometry.preferredCameraDistance == nil,
           let bounds = geometry.boundsSize, drawableSize.width > 0, drawableSize.height > 0 {
            let aspect = Float(drawableSize.width / drawableSize.height)
            let tangent = tan(MetalConfiguration.Geometry.fieldOfView * 0.5)
            let fitDistance = (max(bounds.y * 0.5 / tangent, bounds.x * 0.5 / (tangent * aspect)) + bounds.z * 0.5) * 1.05
            let referenceDistance = MetalConfiguration.Geometry.cameraDistance
            // Fit the initial frame to the viewport while preserving the user's relative zoom.
            fittedCamera.distance *= max(1, fitDistance / referenceDistance)
        }
        fittedCamera = CameraComponent.constrained(fittedCamera)
        let viewMatrix = buildViewMatrix(for: fittedCamera)
        let modelMatrix = buildModelMatrix(for: rotation)

        let uniforms = Uniforms(
            modelMatrix: modelMatrix,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix
        )

        // Determine texture and useTexture flag
        let (finalTexture, useTexture) = determineTexture(
            geometry: geometry,
            submeshSnapshots: submeshSnapshots,
            modelTextureEnabled: modelTextureEnabled,
            texture: texture
        )
        
        // Legacy fields for backward compatibility
        let legacyIndexBuffer = geometry.indexBuffer
        let legacyIndexCount = geometry.indexCount
        let legacyIndexType = geometry.indexType
        let legacyPrimitiveType = geometry.primitiveType

        return RenderSnapshot(
            rotation: rotation,
            uniforms: uniforms,
            pipeline: pipeline,
            depthStencil: depthStencil,
            vertexBuffer: geometry.vertexBuffer,
            vertexBufferOffset: geometry.vertexBufferOffset,
            indexBufferOffset: geometry.indexBufferOffset,
            sampler: sampler,
            submeshes: submeshSnapshots,
            indexBuffer: legacyIndexBuffer,
            indexCount: legacyIndexCount,
            indexType: legacyIndexType,
            primitiveType: legacyPrimitiveType,
            texture: finalTexture,
            useTexture: useTexture
        )
    }
    
    // MARK: - Private Helpers
    
    private static func buildSubmeshSnapshots(
        from submeshes: [SubmeshGeometry],
        modelTextureEnabled: Bool
    ) -> [SubmeshSnapshot] {
        submeshes.map { submesh in
            SubmeshSnapshot(
                vertexBuffer: submesh.vertexBuffer,
                indexBuffer: submesh.indexBuffer,
                vertexBufferOffset: submesh.vertexBufferOffset,
                indexBufferOffset: submesh.indexBufferOffset,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                primitiveType: submesh.primitiveType,
                baseColorTexture: modelTextureEnabled ? submesh.baseColorTexture : nil,
                normalTexture: modelTextureEnabled ? submesh.normalTexture : nil,
                roughnessTexture: modelTextureEnabled ? submesh.roughnessTexture : nil,
                metallicTexture: modelTextureEnabled ? submesh.metallicTexture : nil,
                emissiveTexture: modelTextureEnabled ? submesh.emissiveTexture : nil,
                useBaseColorTexture: submesh.useBaseColorTexture && modelTextureEnabled,
                baseColor: submesh.baseColor,
                emissiveColor: submesh.emissiveColor,
                roughness: submesh.roughness,
                metallic: submesh.metallic,
                sortCenter: submesh.sortCenter
            )
        }
    }
    
    private static func buildProjectionMatrix(for drawableSize: CGSize) -> float4x4 {
        let aspect = Float(drawableSize.width / max(drawableSize.height, 1))
        return float4x4.perspectiveFov(
            MetalConfiguration.Geometry.fieldOfView,
            aspect: aspect,
            nearZ: MetalConfiguration.Geometry.nearZ,
            farZ: MetalConfiguration.Geometry.farZ
        )
    }
    
    private static func buildViewMatrix(for cameraState: CameraState) -> float4x4 {
        let t = float4x4.translation([ -cameraState.pan.x, -cameraState.pan.y, -cameraState.distance ])
        let r = float4x4.rotationX(cameraState.pitch) * float4x4.rotationY(cameraState.yaw)
        return t * r
    }
    
    private static func buildModelMatrix(for rotation: SIMD3<Float>) -> float4x4 {
        float4x4.rotationX(rotation.x)
            * .rotationY(rotation.y)
            * .rotationZ(rotation.z)
    }
    
    private static func determineTexture(
        geometry: GeometrySource,
        submeshSnapshots: [SubmeshSnapshot],
        modelTextureEnabled: Bool,
        texture: MTLTexture?
    ) -> (texture: MTLTexture?, useTexture: Bool) {
        // If geometry has submeshes with textures, use first available
        if let firstSubmeshTexture = submeshSnapshots.first(where: { $0.baseColorTexture != nil })?.baseColorTexture {
            return (modelTextureEnabled ? firstSubmeshTexture : nil, modelTextureEnabled)
        }

        // Use provided texture
        let shouldUseTexture = texture != nil && modelTextureEnabled

        // Special handling for ModelIOGeometry
        if geometry is ModelIOGeometry {
            return (modelTextureEnabled ? texture : nil, modelTextureEnabled && texture != nil)
        }

        return (shouldUseTexture ? texture : nil, shouldUseTexture)
    }
}

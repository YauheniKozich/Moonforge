//
//  SceneRenderer.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 21.10.25.
//  Refactored by Yauheni Kozich on 17.03.26.
//

import Metal
import MetalKit
import os

// MARK: - Scene Renderer

/// Concrete renderer for 3D scene (cube, models, USDZ)
@MainActor
final class SceneRenderer: BaseRenderer {
    private(set) var initialGeometryName: String?
    private nonisolated let environment = OSAllocatedUnfairLock<GothicEnvironment?>(initialState: nil)

    init(device: MTLDevice, logger: MetalLogger, configuration: MetalConfiguration) {
        // Safe: MTLDevice always creates a command queue on iOS/macOS
        let commandQueue = device.makeCommandQueue()!
        super.init(
            device: device,
            commandQueue: commandQueue,
            pipelineManager: PipelineManager(device: device),
            textureRepository: TextureRepository(device: device, logger: logger),
            logger: logger,
            configuration: configuration
        )
        setMinimumCameraHeight(-0.85)
    }
    
    override func setup(metalView: MTKView) throws {
        try super.setup(metalView: metalView)
        let scene = try GothicEnvironment(device: device, view: metalView)
        environment.withLock { $0 = scene }

        // Prepare the initial model asynchronously; failures go to the renderer delegate.
        if let initialGeometryName, availableGeometries.contains(initialGeometryName) {
            startGeometryLoad(named: initialGeometryName)
        } else if currentGeometryName == "none", let firstGeometry = availableGeometries.first {
            startGeometryLoad(named: firstGeometry)
        }
    }

    func setInitialGeometry(named name: String) {
        initialGeometryName = name
    }

    override func switchGeometry(to geometry: GeometrySource) {
        super.switchGeometry(to: geometry)
        guard geometrySwitchError == nil else { return }
        framePedestal()
    }

    override func resetCamera() {
        super.resetCamera()
        framePedestal()
    }

    private func framePedestal() {
        // Lower the camera's target slightly to leave room for the pedestal foreground.
        pan(deltaX: 0, deltaY: -0.15 / MetalConfiguration.Camera.panSensitivity)
    }

    nonisolated override func renderSpecifics(using encoder: MTLRenderCommandEncoder, snapshot: RenderSnapshot) {
        environment.withLock { $0 }?.draw(using: encoder, uniforms: snapshot.uniforms)
    }

    nonisolated override func renderShadows(using commandBuffer: MTLCommandBuffer, snapshot: RenderSnapshot) {
        environment.withLock { $0 }?.encodeShadows(using: commandBuffer, snapshot: snapshot)
    }

    nonisolated override func renderOverlays(using encoder: MTLRenderCommandEncoder, snapshot: RenderSnapshot, time: Float) {
        environment.withLock { $0 }?.drawFireflies(using: encoder, uniforms: snapshot.uniforms, time: time)
    }

    nonisolated override func cleanup() {
        environment.withLock { $0 = nil }
        super.cleanup()
    }
}

//
//  MetalRenderable.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Metal
import MetalKit

// MARK: - Renderer Delegate Protocol

@MainActor
protocol MetalRendererDelegate: AnyObject {
    func renderer(_ renderer: MetalRenderable, didFailWithError error: Error)
    func renderer(_ renderer: MetalRenderable, didUpdateFPS fps: Double)
}

// MARK: - Renderer Protocol

@MainActor
protocol MetalRenderable: AnyObject {
    var delegate: MetalRendererDelegate? { get set }
    nonisolated var device: MTLDevice { get }

    func setup(metalView: MTKView) throws
    /// Backward-compatibility shim. New gesture flows should use `ObjectRotating`.
    func rotate(x: Float, y: Float)
    func updateRenderSnapshot(for view: MTKView)

    nonisolated func draw(drawable: MTLDrawable, renderPassDescriptor: MTLRenderPassDescriptor)
    nonisolated func cleanup()
}

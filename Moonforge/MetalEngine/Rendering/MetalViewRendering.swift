//
//  MetalViewRendering.swift
//  Moonforge
//
//  Created by Codex on 21.03.26.
//

import MetalKit

@MainActor
protocol MetalViewRendering: MetalRenderable {
    func updateRenderSnapshot(for view: MTKView)
    func makeViewDelegate() -> MTKViewDelegate
    nonisolated func updateDrawableSize(_ size: CGSize)
}

//
//  MetalRenderer.swift
//  Moonforge
//
//  Created on 21.03.26.
//

import Metal
import MetalKit

// MARK: - Metal Renderer Protocol

/// Протокол для Metal renderer
@MainActor
protocol MetalRenderer: AnyObject {
    /// Metal device
    var device: MTLDevice { get }
    
    /// Command queue
    var commandQueue: MTLCommandQueue { get }
    
    /// Delegate для получения событий рендеринга
    var delegate: MetalRendererDelegate? { get set }
    
    /// Настройка renderer
    func setup(metalView: MTKView) throws
    
    /// Отрисовка кадра
    func draw(drawable: MTLDrawable, renderPassDescriptor: MTLRenderPassDescriptor)
    
    /// Очистка ресурсов
    func cleanup()
}

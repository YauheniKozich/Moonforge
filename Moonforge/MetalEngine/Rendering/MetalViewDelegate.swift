//
//  MetalViewDelegate.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 19.03.26.
//

import Foundation
import MetalKit

/// Промежуточный делегат для MTKView.
/// Обновляет snapshot renderer'а перед каждым кадром на @MainActor.
///
/// MEMORY OWNERSHIP:
/// - MTKView (weak) → MetalViewDelegate
/// - GestureCoordinator (strong) → MetalViewDelegate (удерживаем потому что MTKView.delegate — weak)
/// - MetalViewDelegate (weak) → BaseRenderer
/// - BaseRenderer (weak) → MetalRendererDelegate (SceneViewModel)
///
/// Retain cycle: НЕТ — все ссылки weak
@MainActor
final class MetalViewDelegate: NSObject {
    private weak var renderer: (any MetalViewRendering)?

    init(renderer: any MetalViewRendering) {
        self.renderer = renderer
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer?.updateDrawableSize(size)
        renderer?.updateRenderSnapshot(for: view)
    }

    func draw(in view: MTKView) {
        renderer?.updateRenderSnapshot(for: view)

        let drawable = view.currentDrawable
        let descriptor = view.currentRenderPassDescriptor

        guard let drawable, let descriptor else { return }
        renderer?.draw(drawable: drawable, renderPassDescriptor: descriptor)
    }
}

// MARK: - MTKView Delegate

extension MetalViewDelegate: MTKViewDelegate {
    // Методы mtkView(_:drawableSizeWillChange:) и draw(in:) реализованы в классе
}

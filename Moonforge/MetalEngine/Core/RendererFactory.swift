//
//  RendererFactory.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 21.03.26.
//

import Metal
import Foundation

// MARK: - Renderer Factory Protocol

protocol IRendererFactory {
    /// Создать Metal renderer
    @MainActor
    func makeRenderer() -> SceneRenderer?
}

// MARK: - Default Renderer Factory Implementation

final class DefaultRendererFactory: IRendererFactory {
    private let device: MTLDevice?
    private let logger: MetalLogger
    private let configuration: MetalConfiguration

    init(device: MTLDevice?, logger: MetalLogger, configuration: MetalConfiguration) {
        self.device = device
        self.logger = logger
        self.configuration = configuration
    }

    @MainActor
    func makeRenderer() -> SceneRenderer? {
        guard let device = device else {
            logger.log("Cannot create SceneRenderer: Metal device is not available", level: .error)
            return nil
        }
        return SceneRenderer(
            device: device,
            logger: logger,
            configuration: configuration
        )
    }
}

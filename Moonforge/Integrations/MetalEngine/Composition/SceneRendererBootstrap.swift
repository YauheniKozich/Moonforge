//
//  SceneRendererBootstrap.swift
//  Moonforge
//
//  Created by Codex on 21.03.26.
//

import Metal

// MARK: - Scene Renderer Bootstrap

@MainActor
enum SceneRendererBootstrap {
    static func configureDemoScene(
        renderer: SceneRenderer,
        configuration: MetalConfiguration = .default,
        logger: MetalLogger? = nil
    ) {
        let geometryCache = ModelIOGeometryCache(device: renderer.device, logger: logger)

        renderer.registerGeometry(name: "cube") { device in
            try CubeGeometry(device: device, size: MetalConfiguration.Geometry.cubeSize)
        }

        renderer.registerGeometry(name: "model") { _ in
            try geometryCache.getGeometry(
                resourceName: MetalConfiguration.Geometry.defaultModelName,
                extension: MetalConfiguration.Geometry.defaultModelExtension
            )
        }

        renderer.registerGeometry(name: "usdz") { _ in
            try geometryCache.getGeometry(
                resourceName: MetalConfiguration.Geometry.usdzModelName,
                extension: MetalConfiguration.Geometry.usdzModelExtension,
                preferredCameraDistance: MetalConfiguration.Geometry.usdzCameraDistance
            )
        }

        renderer.registerGeometryAsync(name: "model") { _ in
            try await geometryCache.getGeometryAsync(
                resourceName: MetalConfiguration.Geometry.defaultModelName,
                extension: MetalConfiguration.Geometry.defaultModelExtension)
        }
        renderer.registerGeometryAsync(name: "usdz") { _ in
            try await geometryCache.getGeometryAsync(
                resourceName: MetalConfiguration.Geometry.usdzModelName,
                extension: MetalConfiguration.Geometry.usdzModelExtension,
                preferredCameraDistance: MetalConfiguration.Geometry.usdzCameraDistance)
        }

        renderer.setInitialGeometry(named: "usdz")
    }
}

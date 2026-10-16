import Foundation

// MARK: - Metal Configuration

/// Конфигурация MetalEngine — независимая от Domain
struct MetalConfiguration {
    // MARK: - Shaders

    struct Shaders {
        static let vertex = "vertex_main"
        static let fragment = "fragment_main"
        static let modelVertex = "vertex_model"
        static let modelFragment = "fragment_model"
    }

    // MARK: - Moon

    struct Moon {
        // Moonless cylindrical panorama: UV offset, vertical scale (3:1 image), lunar intensity.
        static let panoramaMapping = SIMD4<Float>(0.5, 0.60, 3.0 / (2 * .pi), 1.5)
        // Independently positioned world-space disk; angles are radians.
        static let azimuth: Float = 0.675
        static let elevation: Float = 0.52
        static let angularRadius: Float = 0.055
        // Crater texture is sampled from the preserved original image, inside its painted disk.
        static let textureRegion = SIMD4<Float>(1370.0 / 1774.0, 196.0 / 887.0,
                                                27.0 / 1774.0, 27.0 / 887.0)
        static let shadowCameraDistance: Float = 8.0
        static let direction = SIMD3<Float>(sin(azimuth) * cos(elevation), sin(elevation),
                                            -cos(azimuth) * cos(elevation))
    }

    // MARK: - Fog

    struct Fog {
        // Linear HDR color; density is inverse world units and falloff is inverse height units.
        static let color = SIMD3<Float>(0.07, 0.1, 0.15)
        static let density: Float = 0.13
        static let baseHeight: Float = -1.2
        static let heightFalloff: Float = 1.3
        static let skyDistance: Float = 30.0
    }

    // MARK: - Rotation

    struct Rotation {
        static let sensitivity: Float = 0.005
        static let dampingFactor: Float = 0.95
        static let minVelocity: Float = 0.0001
        static let autoRotateSpeed: Float = 1.0
    }

    // MARK: - Geometry
    
    struct Geometry {
        static let cubeSize: Float = 0.5
        static let cameraDistance: Float = 2.8
        static let nearZ: Float = 0.1
        static let farZ: Float = 100.0
        static let fieldOfView: Float = .pi / 4
        static let defaultModelName = "icosphere"
        static let defaultModelExtension = "obj"
        static let usdzModelName = "Sorceress"
        static let usdzModelExtension = "usdz"
        static let usdzCameraDistance: Float = 3.6
    }
    
    // MARK: - Camera
    
    struct Camera {
        static let minDistance: Float = 0.5
        static let maxDistance: Float = 5.0
        static let orbitSensitivity: Float = 0.005
        static let panSensitivity: Float = 0.003
        static let pinchSensitivity: Float = 0.75
        static let maxPitch: Float = .pi / 2 - 0.1
    }
    
    // MARK: - Performance
    
    struct Performance {
        static let targetFrameTime: Float = 1.0 / 120.0
        static let textureSize = 256
        static let pipelineCacheLimit = 128
    }
    
    // MARK: - Resources
    
    struct Resources {
        static let textureName = "texture"
        static let textureExtension = "png"
    }
}

// MARK: - Default Configuration

extension MetalConfiguration {
    /// Конфигурация по умолчанию
    static let `default` = MetalConfiguration()
}

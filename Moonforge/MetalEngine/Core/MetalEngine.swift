import Metal
import MetalKit

// MARK: - Metal Engine

/// Главный класс для доступа к MetalEngine
///
/// Использование:
/// ```swift
/// let metalEngine = MetalEngine(
///     device: MTLCreateSystemDefaultDevice()!,
///     logger: logger,
///     configuration: .default
/// )
///
/// let renderer = metalEngine.renderer
/// try await renderer.setup(metalView: view)
/// ```
@MainActor
final class MetalEngine {
    /// Renderer для работы с Metal
    let renderer: SceneRenderer
    
    /// Загрузчик текстур
    let textureLoader: TextureLoader
    
    /// Кэш текстур
    var textureCache: TextureCache
    
    /// Реестр геометрии
    var geometryRegistry: GeometryRegistry
    
    /// Конфигурация
    let configuration: MetalConfiguration
    
    /// Инициализация MetalEngine
    /// - Parameters:
    ///   - device: Metal device
    ///   - logger: Logger для диагностического вывода
    ///   - configuration: Конфигурация MetalEngine
    init(
        device: MTLDevice,
        logger: MetalLogger,
        configuration: MetalConfiguration = .default
    ) {
        self.configuration = configuration
        self.renderer = SceneRenderer(
            device: device,
            logger: logger,
            configuration: configuration
        )
        self.textureLoader = TextureLoader(device: device)
        self.textureCache = TextureCache(capacity: 32)
        self.geometryRegistry = GeometryRegistry()
    }
    
    // MARK: - Cleanup
    
    /// Очистка ресурсов
    func cleanup() {
        renderer.cleanup()
        textureCache.clear()
        geometryRegistry = GeometryRegistry()
    }
}

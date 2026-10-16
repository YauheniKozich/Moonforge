//
//  ModelIOGeometryCache.swift
//  Moonforge
//
//  Created on 21.03.26.
//

import Metal
import MetalKit
import ModelIO

// MARK: - ModelIO Geometry Cache

/// Кэш для загруженных ModelIOGeometry
///
/// Предотвращает повторную загрузку одних и тех же моделей из файлов,
/// уменьшая время переключения геометрии и нагрузку на файловую систему.
///
/// Использование:
/// ```swift
/// let cache = ModelIOGeometryCache.shared
/// let geometry = try cache.getGeometry(
///     resourceName: "cube",
///     device: device
/// )
/// ```
@MainActor
final class ModelIOGeometryCache {
    private struct CacheKey: Hashable {
        let resourceName: String
        let resourceExtension: String
        let bundleURL: URL
        let preferredCameraDistance: Float?
    }

    private let cache = LRUCache<CacheKey, ModelIOGeometry>(capacity: 5)
    private let device: MTLDevice
    private let logger: MetalLogger?

    init(device: MTLDevice, logger: MetalLogger? = nil) {
        self.device = device
        self.logger = logger
    }
    
    /// Получить геометрию из кэша или загрузить из файла
    /// - Parameters:
    ///   - resourceName: Имя ресурса (без расширения)
    ///   - extension: Расширение файла (по умолчанию "obj")
    ///   - bundle: Bundle для поиска ресурса
    /// - Returns: Загруженная или закэшированная геометрия
    /// - Throws: ModelLoadError при ошибке загрузки
    func getGeometry(
        resourceName: String,
        extension ext: String = "obj",
        bundle: Bundle = .main,
        preferredCameraDistance: Float? = nil
    ) throws -> ModelIOGeometry {
        let cacheKey = CacheKey(
            resourceName: resourceName,
            resourceExtension: ext,
            bundleURL: bundle.bundleURL.standardizedFileURL.resolvingSymlinksInPath(),
            preferredCameraDistance: preferredCameraDistance
        )
        
        // Проверяем кэш сначала
        if let cached = cache.value(forKey: cacheKey) {
            logger?.log("ModelIOGeometryCache: Hit for \(cacheKey)", level: .debug)
            return cached
        }
        
        // Загружаем из файла
        logger?.log("ModelIOGeometryCache: Miss for \(cacheKey) — loading from file", level: .debug)
        let geometry = try ModelIOGeometry(
            device: device,
            resourceName: resourceName,
            ext: ext,
            bundle: bundle,
            preferredCameraDistance: preferredCameraDistance,
            logger: logger
        )
        
        // Кэшируем результат
        cache.setValue(geometry, forKey: cacheKey)
        
        return geometry
    }
    
    func getGeometryAsync(
        resourceName: String, extension ext: String = "obj", bundle: Bundle = .main,
        preferredCameraDistance: Float? = nil
    ) async throws -> ModelIOGeometry {
        try Task.checkCancellation()
        let key = CacheKey(resourceName: resourceName, resourceExtension: ext,
                           bundleURL: bundle.bundleURL.standardizedFileURL.resolvingSymlinksInPath(),
                           preferredCameraDistance: preferredCameraDistance)
        if let geometry = cache.value(forKey: key) { return geometry }
        let geometry = try await Self.prepare(device: device, resourceName: resourceName,
                                              ext: ext, bundle: bundle,
                                              preferredCameraDistance: preferredCameraDistance)
        try Task.checkCancellation()
        logger?.log(geometry.preparationSummary, level: .debug)
        cache.setValue(geometry, forKey: key)
        return geometry
    }

    // Each request constructs an exclusively owned model off MainActor, then transfers
    // ownership once. The background task retains no alias and touches no app logger.
    @concurrent
    private static func prepare(device: MTLDevice, resourceName: String, ext: String,
                                bundle: Bundle, preferredCameraDistance: Float?) async throws -> sending ModelIOGeometry {
        try Task.checkCancellation()
        let geometry = try ModelIOGeometry(device: device, resourceName: resourceName,
                                           ext: ext, bundle: bundle,
                                           preferredCameraDistance: preferredCameraDistance)
        try Task.checkCancellation()
        return geometry
    }

    /// Очистить кэш
    func clear() {
        cache.removeAll()
        logger?.log("ModelIOGeometryCache: Cleared", level: .debug)
    }
    
    /// Удалить конкретную геометрию из кэша
    func remove(_ resourceName: String, extension ext: String = "obj") {
        cache.removeValues { $0.resourceName == resourceName && $0.resourceExtension == ext }
        logger?.log("ModelIOGeometryCache: Removed all camera-distance variants of \(resourceName).\(ext)", level: .debug)
    }
}

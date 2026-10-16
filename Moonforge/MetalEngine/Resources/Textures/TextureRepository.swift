//
//  TextureRepository.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//  Refactored on 21.03.26.
//

@preconcurrency import Metal
import MetalKit
import os

// MARK: - Texture Repository

/// Потокобезопасный загрузчик и кэш текстур с использованием паттерна композиция.
///
/// Этот repository координирует загрузку текстур через три компонента:
/// - TextureLoading: загрузка текстур из URL (MTKTextureLoader)
/// - TextureCaching: кэширование текстур с LRU вытеснением (TextureCache)
/// - TextureFactory: создание процедурных fallback текстур (MTLTextureFactory)
///
/// Модель потокобезопасности:
/// - На основе lock: всё изменяемое состояние защищено через OSAllocatedUnfairLock
/// - Асинхронная загрузка: выполняется в вызывающей задаче и учитывает её отмену
/// - Синхронный доступ: свойство texture потокобезопасно
///
/// Использование:
/// ```swift
/// let repo = TextureRepository(
///     loader: MTKTextureLoader(device: device),
///     cache: TextureCache(capacity: 10),
///     factory: MTLTextureFactory(device: device),
///     logger: logger
/// )
///
/// // Асинхронная загрузка
/// Task {
///     _ = await repo.loadTexture()
/// }
///
/// // Синхронный доступ
/// let texture = repo.texture
/// ```
final class TextureRepository: @unchecked Sendable {
    private let loader: TextureLoading
    private let cache: StringTextureCaching
    private let factory: TextureFactory
    private let logger: MetalLogger

    private let textureName: String
    private let textureExtension: String
    private let bundle: Bundle

    private struct State {
        var texture: MTLTexture?
        var isFallbackTexture = false
        var generation: UInt64 = 0
    }

    // Publication and cleanup use the same lock so an old load cannot restore cleared resources.
    private let stateLock = OSAllocatedUnfairLock<State>(uncheckedState: State())
    var texture: MTLTexture? {
        get { stateLock.withLockUnchecked { $0.texture } }
        set { stateLock.withLockUnchecked { $0.texture = newValue } }
    }

    var isFallbackTexture: Bool {
        get { stateLock.withLockUnchecked { $0.isFallbackTexture } }
        set { stateLock.withLockUnchecked { $0.isFallbackTexture = newValue } }
    }

    // MARK: - Initialization

    /// Инициализация repository с кастомными компонентами
    init(
        loader: TextureLoading,
        cache: StringTextureCaching,
        factory: TextureFactory,
        logger: MetalLogger,
        textureName: String = MetalConfiguration.Resources.textureName,
        textureExtension: String = MetalConfiguration.Resources.textureExtension,
        bundle: Bundle = .main
    ) {
        self.loader = loader
        self.cache = cache
        self.factory = factory
        self.logger = logger
        self.textureName = textureName
        self.textureExtension = textureExtension
        self.bundle = bundle
    }

    /// Инициализация repository с компонентами по умолчанию (convenience initializer)
    convenience init(
        device: MTLDevice,
        logger: MetalLogger,
        textureName: String = MetalConfiguration.Resources.textureName,
        textureExtension: String = MetalConfiguration.Resources.textureExtension,
        cacheCapacity: Int = 10,
        bundle: Bundle = .main
    ) {
        let loader = TextureLoader(device: device)
        let cache = AnyTextureCache(TextureCache(capacity: cacheCapacity))
        let factory = MTLTextureFactory(device: device)
        self.init(
            loader: loader,
            cache: cache,
            factory: factory,
            logger: logger,
            textureName: textureName,
            textureExtension: textureExtension,
            bundle: bundle
        )
    }
    
    // MARK: - Texture Loading

    private var resourceURL: URL? {
        bundle.url(forResource: textureName, withExtension: textureExtension)
            ?? bundle.url(forResource: textureName, withExtension: textureExtension, subdirectory: "Textures")
    }

    private var resourceKey: String {
        resourceURL?.absoluteString ?? "asset:\(bundle.bundleURL.absoluteString):\(textureName)"
    }

    func loadTexture() async -> MTLTexture? {
        guard !Task.isCancelled else { return nil }
        let state = stateLock.withLockUnchecked { $0 }
        if let texture = state.texture { return texture }
        let key = resourceKey
        if let texture = cache.get(key) {
            return publish(texture, isFallback: false, generation: state.generation, key: key)
        }
        do {
            let texture: MTLTexture
            if let url = resourceURL { texture = try await loader.load(from: url) }
            else { texture = try await loader.load(named: textureName, bundle: bundle) }
            return publish(texture, isFallback: false, generation: state.generation, key: key)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return nil }
            logger.log("Texture loading failed for \(textureName).\(textureExtension): \(error)", level: .warning)
            return fallback(generation: state.generation)
        }
    }

    /// Synchronous compatibility path. Prefer loadTexture() for UI-owned loading.
    func loadTextureSync() -> MTLTexture? {
        guard !Task.isCancelled else { return nil }
        let state = stateLock.withLockUnchecked { $0 }
        if let texture = state.texture { return texture }
        let key = resourceKey
        if let texture = cache.get(key) {
            return publish(texture, isFallback: false, generation: state.generation, key: key)
        }
        do {
            let texture: MTLTexture
            if let url = resourceURL { texture = try loader.loadSync(from: url) }
            else { texture = try loader.loadSync(named: textureName, bundle: bundle) }
            return publish(texture, isFallback: false, generation: state.generation, key: key)
        } catch {
            logger.log("Texture loading failed for \(textureName).\(textureExtension): \(error)", level: .warning)
            return fallback(generation: state.generation)
        }
    }

    private func fallback(generation: UInt64) -> MTLTexture? {
        guard !Task.isCancelled else { return nil }
        let key = "fallback:\(resourceKey)"
        let texture = cache.get(key) ?? factory.createFallback(size: MetalConfiguration.Performance.textureSize)
        return publish(texture, isFallback: true, generation: generation, key: key)
    }

    private func publish(_ texture: MTLTexture?, isFallback: Bool, generation: UInt64, key: String) -> MTLTexture? {
        stateLock.withLockUnchecked { state in
            guard !Task.isCancelled, state.generation == generation else { return nil }
            if let texture { cache.set(key, texture: texture) }
            state.texture = texture
            state.isFallbackTexture = isFallback
            return texture
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        stateLock.withLockUnchecked { state in
            state.generation &+= 1
            state.texture = nil
            state.isFallbackTexture = false
            cache.clear()
        }
    }
}

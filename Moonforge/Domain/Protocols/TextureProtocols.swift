//
//  TextureProtocols.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 21.03.26.
//

import Metal
import Foundation

// MARK: - Texture Loading Protocol

/// Protocol for loading textures from various sources
protocol TextureLoading {
    /// Загрузить текстуру из URL
    func load(from url: URL) async throws -> MTLTexture
    func load(named name: String, bundle: Bundle) async throws -> MTLTexture
    func loadSync(from url: URL) throws -> MTLTexture
    func loadSync(named name: String, bundle: Bundle) throws -> MTLTexture
}

// Defaults preserve existing URL-only loader conformances.
extension TextureLoading {
    func load(named name: String, bundle: Bundle) async throws -> MTLTexture { throw CocoaError(.fileNoSuchFile) }
    func loadSync(from url: URL) throws -> MTLTexture { throw CocoaError(.featureUnsupported) }
    func loadSync(named name: String, bundle: Bundle) throws -> MTLTexture { throw CocoaError(.featureUnsupported) }
}

// MARK: - Texture Caching Protocol

/// Protocol for caching textures with LRU eviction
protocol TextureCaching {
    associatedtype Key: Hashable
    associatedtype Value: AnyObject

    /// Получить текстуру из кэша
    func get(_ key: Key) -> Value?

    /// Сохранить текстуру в кэш
    func set(_ key: Key, texture: Value)

    /// Удалить текстуру из кэша
    func remove(_ key: Key)

    /// Очистить весь кэш
    func clear()

    /// Текущее количество закэшированных текстур
    var count: Int { get }

    /// Максимальная вместимость кэша
    var capacity: Int { get }
}

/// Concrete type-erased texture cache for common String -> MTLTexture use case
protocol StringTextureCaching {
    func get(_ key: String) -> MTLTexture?
    func set(_ key: String, texture: MTLTexture)
    func remove(_ key: String)
    func clear()
    var count: Int { get }
    var capacity: Int { get }
}

// MARK: - AnyTextureCache Type Erasure

/// Type-erased wrapper for any TextureCaching with String keys
final class AnyTextureCache: StringTextureCaching {
    private let _get: (String) -> MTLTexture?
    private let _set: (String, MTLTexture) -> Void
    private let _remove: (String) -> Void
    private let _clear: () -> Void
    private let _count: () -> Int
    private let _capacity: () -> Int

    init<C: TextureCaching>(_ cache: C) where C.Key == String, C.Value == MTLTexture {
        _get = cache.get
        _set = cache.set
        _remove = cache.remove
        _clear = cache.clear
        _count = { cache.count }
        _capacity = { cache.capacity }
    }

    func get(_ key: String) -> MTLTexture? {
        _get(key)
    }

    func set(_ key: String, texture: MTLTexture) {
        _set(key, texture)
    }

    func remove(_ key: String) {
        _remove(key)
    }

    func clear() {
        _clear()
    }

    var count: Int { _count() }
    var capacity: Int { _capacity() }
}

// MARK: - Texture Factory Protocol

/// Protocol for creating procedural textures programmatically
protocol TextureFactory {
    /// Создать fallback текстуру
    func createFallback(size: Int) -> MTLTexture?

    /// Создать текстуру шашечка
    func createCheckerboard(size: Int, tileSize: Int) -> MTLTexture?

    /// Создать однотонную текстуру
    func createSolidColor(
        size: Int,
        red: Float,
        green: Float,
        blue: Float,
        alpha: Float
    ) -> MTLTexture?
}

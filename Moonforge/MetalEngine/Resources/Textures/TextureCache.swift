//
//  TextureCache.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 21.03.26.
//

@preconcurrency import Metal
import Foundation
import os

// MARK: - Texture Cache Implementation

/// Thread-safe LRU cache for MTLTexture objects
final class TextureCache: TextureCaching, @unchecked Sendable {
    typealias Key = String
    typealias Value = MTLTexture

    private let cache: LRUCache<Key, Value>

    // Statistics
    private let statsLock = OSAllocatedUnfairLock<State>(initialState: State())
    private struct State: Sendable {
        var hits: Int = 0
        var misses: Int = 0
        var evictions: Int = 0
    }

    // MARK: - Initialization

    /// Initialize the cache with the specified capacity
    /// - Parameter capacity: Maximum number of textures to cache
    init(capacity: Int) {
        self.cache = LRUCache(capacity: capacity)
    }

    // MARK: - TextureCaching Protocol

    func get(_ key: Key) -> Value? {
        guard let texture = cache.value(forKey: key) else {
            statsLock.withLock { state in
                state.misses += 1
            }
            return nil
        }

        statsLock.withLock { state in
            state.hits += 1
        }

        return texture
    }

    func set(_ key: Key, texture: Value) {
        let evicted = cache.setValueReportingEviction(texture, forKey: key)
        if evicted {
            statsLock.withLock { state in
                state.evictions += 1
            }
        }
    }

    func remove(_ key: Key) {
        cache.removeValue(forKey: key)
    }

    /// Clear all textures from the cache
    func clear() {
        cache.removeAll()
        statsLock.withLock { state in
            state = State()
        }
    }

    /// The current number of cached textures
    var count: Int {
        cache.count
    }

    /// The maximum capacity of the cache
    var capacity: Int {
        cache.capacity
    }

    // MARK: - Statistics

    /// Number of cache hits (successful get operations)
    var hits: Int {
        statsLock.withLock { $0.hits }
    }

    /// Number of cache misses (failed get operations)
    var misses: Int {
        statsLock.withLock { $0.misses }
    }

    /// Number of textures evicted due to capacity limits
    var evictions: Int {
        statsLock.withLock { $0.evictions }
    }

    /// Cache hit ratio (0.0 - 1.0)
    var hitRatio: Double {
        statsLock.withLock { state in
            let total = state.hits + state.misses
            guard total > 0 else { return 0.0 }
            return Double(state.hits) / Double(total)
        }
    }

    /// Reset statistics counters
    func resetStats() {
        statsLock.withLock { state in
            state = State()
        }
    }
}

// MARK: - CustomStringConvertible

extension TextureCache: CustomStringConvertible {
    var description: String {
        "TextureCache(count: \(count), capacity: \(capacity), hitRatio: \(String(format: "%.2f", hitRatio))"
    }
}

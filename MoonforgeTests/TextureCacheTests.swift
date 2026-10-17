//
//  TextureCacheTests.swift
//  MoonforgeTests
//
//  Created by Yauheni Kozich on 21.03.26.
//

import XCTest
import os
@testable import Moonforge

final class TextureCacheTests: XCTestCase {
    var cache: TextureCache!
    var mockTexture: MTLTexture!

    override func setUp() {
        super.setUp()
        cache = TextureCache(capacity: 3)
        mockTexture = createMockTexture()
    }

    override func tearDown() {
        cache = nil
        mockTexture = nil
        super.tearDown()
    }

    // MARK: - Basic Operations

    func testSetAndGet() {
        cache.set("texture1", texture: mockTexture)
        let retrieved = cache.get("texture1")

        XCTAssertNotNil(retrieved)
        XCTAssertTrue(retrieved === mockTexture)
    }

    func testGetNonExistentKey() {
        let retrieved = cache.get("nonexistent")
        XCTAssertNil(retrieved)
    }

    func testRemove() {
        cache.set("texture1", texture: mockTexture)
        cache.remove("texture1")
        let retrieved = cache.get("texture1")

        XCTAssertNil(retrieved)
    }

    func testClear() {
        cache.set("texture1", texture: mockTexture)
        cache.set("texture2", texture: mockTexture)
        cache.clear()

        XCTAssertEqual(cache.count, 0)
    }

    // MARK: - LRU Eviction

    func testEvictsLeastRecentlyUsed() {
        let texture1 = createMockTexture()
        let texture2 = createMockTexture()
        let texture3 = createMockTexture()

        cache.set("texture1", texture: texture1)
        cache.set("texture2", texture: texture2)
        cache.set("texture3", texture: texture3)

        XCTAssertEqual(cache.count, 3)

        // Access texture1 to make it recently used
        _ = cache.get("texture1")

        // Add new texture - should evict texture2 (least recently used)
        let texture4 = createMockTexture()
        cache.set("texture4", texture: texture4)

        XCTAssertNotNil(cache.get("texture1"))
        XCTAssertNil(cache.get("texture2"))
        XCTAssertNotNil(cache.get("texture3"))
        XCTAssertNotNil(cache.get("texture4"))
    }

    func testReadUpdatesRecency() {
        let smallCache = TextureCache(capacity: 2)
        let texture1 = createMockTexture()
        let texture2 = createMockTexture()

        smallCache.set("texture1", texture: texture1)
        smallCache.set("texture2", texture: texture2)

        // Access texture1 to update its recency
        _ = smallCache.get("texture1")

        // Add new texture - should evict texture2 (least recently used)
        let texture3 = createMockTexture()
        smallCache.set("texture3", texture: texture3)

        XCTAssertNotNil(smallCache.get("texture1"))
        XCTAssertNil(smallCache.get("texture2"))
        XCTAssertNotNil(smallCache.get("texture3"))
    }


    // MARK: - Statistics

    func testTracksHitsAndMisses() {
        cache.set("texture1", texture: mockTexture)

        _ = cache.get("texture1") // hit
        _ = cache.get("texture1") // hit
        _ = cache.get("nonexistent") // miss

        XCTAssertEqual(cache.hits, 2)
        XCTAssertEqual(cache.misses, 1)
    }

    func testHitRatio() {
        cache.set("texture1", texture: mockTexture)

        _ = cache.get("texture1") // hit
        _ = cache.get("texture1") // hit
        _ = cache.get("nonexistent") // miss
        _ = cache.get("nonexistent") // miss

        XCTAssertEqual(cache.hitRatio, 0.5, accuracy: 0.01)
    }

    func testConcurrentHitRatioConsistency() {
        let testCache = TextureCache(capacity: 10)
        let texture = mockTexture!
        testCache.set("item", texture: texture)

        let iterations = 2000
        let group = DispatchGroup()
        let ratioExceededBounds = OSAllocatedUnfairLock(initialState: false)

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0..<iterations {
                if i % 2 == 0 {
                    _ = testCache.get("item")
                } else {
                    _ = testCache.get("miss_\(i)")
                }
            }
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<iterations {
                let ratio = testCache.hitRatio
                if ratio < 0.0 || ratio > 1.0 {
                    ratioExceededBounds.withLock { $0 = true }
                    break
                }
            }
            group.leave()
        }

        group.wait()
        let failed = ratioExceededBounds.withLock { $0 }
        XCTAssertFalse(failed, "hitRatio must always remain within [0.0, 1.0]")
    }

    func testResetStats() {
        cache.set("texture1", texture: mockTexture)
        _ = cache.get("texture1")
        _ = cache.get("nonexistent")

        cache.resetStats()

        XCTAssertEqual(cache.hits, 0)
        XCTAssertEqual(cache.misses, 0)
        XCTAssertEqual(cache.evictions, 0)
    }

    func testTracksEvictions() {
        let texture1 = createMockTexture()
        let texture2 = createMockTexture()
        let texture3 = createMockTexture()

        cache.set("texture1", texture: texture1)
        cache.set("texture2", texture: texture2)
        cache.set("texture3", texture: texture3)

        // Adding 4th texture should cause eviction
        let texture4 = createMockTexture()
        cache.set("texture4", texture: texture4)

        XCTAssertGreaterThan(cache.evictions, 0)
    }

    // MARK: - Capacity

    func testCapacity() {
        XCTAssertEqual(cache.capacity, 3)
    }

    func testCount() {
        XCTAssertEqual(cache.count, 0)

        cache.set("texture1", texture: mockTexture)
        XCTAssertEqual(cache.count, 1)

        cache.set("texture2", texture: mockTexture)
        XCTAssertEqual(cache.count, 2)
    }

    // MARK: - Helper Methods

    private func createMockTexture() -> MTLTexture {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal device not available")
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 64,
            height: 64,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("Failed to create mock texture")
        }

        return texture
    }
}

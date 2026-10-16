//
//  TextureRepositoryConcurrencyTests.swift
//  MoonforgeTests
//
//  Created for Swift 6 Concurrency Audit Regression Verification.
//

@preconcurrency import Metal
import XCTest
@testable import Moonforge

final class TextureRepositoryConcurrencyTests: XCTestCase {
    private var device: MTLDevice!
    private var mockTexture: MTLTexture!

    override func setUp() {
        super.setUp()
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal device not available")
        }
        self.device = defaultDevice
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 32,
            height: 32,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let texture = defaultDevice.makeTexture(descriptor: descriptor) else {
            fatalError("Failed to create mock texture")
        }
        self.mockTexture = texture
    }

    override func tearDown() {
        device = nil
        mockTexture = nil
        super.tearDown()
    }

    // MARK: - Mocks

    private actor MockControllableLoader: TextureLoading {
        private var startedContinuation: CheckedContinuation<Void, Never>?
        private var proceedContinuation: CheckedContinuation<Void, Never>?
        private var hasStarted = false
        nonisolated let texture: MTLTexture

        init(texture: MTLTexture) {
            self.texture = texture
        }

        func waitForLoadToStart() async {
            if hasStarted { return }
            await withCheckedContinuation { continuation in
                startedContinuation = continuation
            }
        }

        func allowLoadToProceed() {
            let continuation = proceedContinuation
            proceedContinuation = nil
            continuation?.resume()
        }

        func load(from url: URL) async throws -> MTLTexture {
            await signalStartedAndAwaitProceed()
            return texture
        }

        func load(named name: String, bundle: Bundle) async throws -> MTLTexture {
            await signalStartedAndAwaitProceed()
            return texture
        }

        private func signalStartedAndAwaitProceed() async {
            hasStarted = true
            let started = startedContinuation
            startedContinuation = nil
            started?.resume()

            await withCheckedContinuation { continuation in
                proceedContinuation = continuation
            }
        }

        nonisolated func loadSync(from url: URL) throws -> MTLTexture { texture }
        nonisolated func loadSync(named name: String, bundle: Bundle) throws -> MTLTexture { texture }
    }

    // MARK: - Tests

    func testStaleTextureNotResurrectedAfterCleanup() async {
        let mockLoader = MockControllableLoader(texture: mockTexture)
        let underlyingCache = TextureCache(capacity: 10)
        let cache = AnyTextureCache(underlyingCache)
        let factory = MTLTextureFactory(device: device)
        let logger = AppMetalLogger { _, _ in }

        let repository = TextureRepository(
            loader: mockLoader,
            cache: cache,
            factory: factory,
            logger: logger,
            textureName: "GothicAltar_BaseColor",
            textureExtension: "png"
        )

        // Step 1: Start async texture loading
        let loadTask = Task {
            await repository.loadTexture()
        }

        // Step 2: Deterministically wait until loader is active (generation 0 has been read)
        await mockLoader.waitForLoadToStart()

        // Step 3: Cleanup is called before load finishes (increments generation to 1, clears cache)
        repository.cleanup()
        XCTAssertEqual(underlyingCache.count, 0)
        XCTAssertNil(repository.texture)

        // Step 4: Allow the loader to complete and attempt publishing with generation 0
        await mockLoader.allowLoadToProceed()
        let publishedTexture = await loadTask.value

        // Step 5: Verify stale texture was rejected and NOT inserted into cache
        XCTAssertNil(publishedTexture, "Stale texture from prior generation must not be published")
        XCTAssertNil(repository.texture, "Repository texture must remain nil after cleanup")
        XCTAssertEqual(underlyingCache.count, 0, "Stale texture must not resurrect into cache after cleanup")
    }

    func testConcurrentCacheInvalidationAndLoads() async {
        let underlyingCache = TextureCache(capacity: 10)
        let cache = AnyTextureCache(underlyingCache)
        let factory = MTLTextureFactory(device: device)
        let logger = AppMetalLogger { _, _ in }

        final class FastMockLoader: TextureLoading, @unchecked Sendable {
            let texture: MTLTexture
            init(texture: MTLTexture) { self.texture = texture }
            func load(from url: URL) async throws -> MTLTexture { texture }
            func load(named name: String, bundle: Bundle) async throws -> MTLTexture { texture }
            func loadSync(from url: URL) throws -> MTLTexture { texture }
            func loadSync(named name: String, bundle: Bundle) throws -> MTLTexture { texture }
        }

        let repository = TextureRepository(
            loader: FastMockLoader(texture: mockTexture),
            cache: cache,
            factory: factory,
            logger: logger
        )

        let iterations = 100
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    _ = await repository.loadTexture()
                }
                group.addTask {
                    repository.cleanup()
                }
            }
        }

        // Ensure final cleanup leaves consistent state without deadlocks
        repository.cleanup()
        XCTAssertNil(repository.texture)
        XCTAssertEqual(underlyingCache.count, 0)
    }
}

//
//  MTLTextureFactoryTests.swift
//  MoonforgeTests
//
//  Created by Yauheni Kozich on 21.03.26.
//

import XCTest
@testable import Moonforge

final class MTLTextureFactoryTests: XCTestCase {
    var factory: MTLTextureFactory!
    var device: MTLDevice!

    override func setUp() {
        super.setUp()
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal device not available")
        }
        device = metalDevice
        factory = MTLTextureFactory(device: device)
    }

    override func tearDown() {
        factory = nil
        device = nil
        super.tearDown()
    }

    // MARK: - Fallback Texture Tests

    func testCreateFallbackTexture() {
        let texture = factory.createFallback(size: 256)

        XCTAssertNotNil(texture)
        XCTAssertEqual(texture?.width, 256)
        XCTAssertEqual(texture?.height, 256)
        XCTAssertEqual(texture?.pixelFormat, .rgba8Unorm)
    }

    func testCreateFallbackWithCustomSize() {
        let texture = factory.createFallback(size: 512)

        XCTAssertNotNil(texture)
        XCTAssertEqual(texture?.width, 512)
        XCTAssertEqual(texture?.height, 512)
    }

    func testCreateFallbackWithInvalidSize() {
        let texture = factory.createFallback(size: 0)
        XCTAssertNil(texture)

        let negativeTexture = factory.createFallback(size: -10)
        XCTAssertNil(negativeTexture)
    }

    // MARK: - Checkerboard Texture Tests

    func testCreateCheckerboard() {
        let texture = factory.createCheckerboard(size: 128, tileSize: 16)

        XCTAssertNotNil(texture)
        XCTAssertEqual(texture?.width, 128)
        XCTAssertEqual(texture?.height, 128)
        XCTAssertEqual(texture?.pixelFormat, .rgba8Unorm)
    }

    func testCreateCheckerboardWithStandardTileSize() {
        let texture = factory.createCheckerboard(size: 256, tileSize: 16)

        XCTAssertNotNil(texture)
        XCTAssertEqual(texture?.width, 256)
        XCTAssertEqual(texture?.height, 256)
    }

    func testCreateCheckerboardWithInvalidSize() {
        let texture = factory.createCheckerboard(size: 0, tileSize: 16)
        XCTAssertNil(texture)

        let invalidTileSize = factory.createCheckerboard(size: 64, tileSize: 0)
        XCTAssertNil(invalidTileSize)
    }

    // MARK: - Solid Color Texture Tests

    func testCreateSolidColor() {
        let texture = factory.createSolidColor(
            size: 64,
            red: 1.0,
            green: 0.5,
            blue: 0.25,
            alpha: 0.8
        )

        XCTAssertNotNil(texture)
        XCTAssertEqual(texture?.width, 64)
        XCTAssertEqual(texture?.height, 64)
        XCTAssertEqual(texture?.pixelFormat, .rgba8Unorm)
    }

    func testCreateSolidColorWithZeroValues() {
        let texture = factory.createSolidColor(
            size: 32,
            red: 0.0,
            green: 0.0,
            blue: 0.0,
            alpha: 0.0
        )

        XCTAssertNotNil(texture)
        XCTAssertEqual(texture?.width, 32)
        XCTAssertEqual(texture?.height, 32)
    }

    func testCreateSolidColorWithOneValues() {
        let texture = factory.createSolidColor(
            size: 32,
            red: 1.0,
            green: 1.0,
            blue: 1.0,
            alpha: 1.0
        )

        XCTAssertNotNil(texture)
        XCTAssertEqual(texture?.width, 32)
        XCTAssertEqual(texture?.height, 32)
    }

    func testCreateSolidColorWithInvalidSize() {
        let texture = factory.createSolidColor(
            size: 0,
            red: 1.0,
            green: 0.0,
            blue: 0.0,
            alpha: 1.0
        )
        XCTAssertNil(texture)
    }

    func testCreateSolidColorWithClampedValues() {
        // Values outside 0-1 range should be clamped
        let texture = factory.createSolidColor(
            size: 32,
            red: 1.5,   // Should clamp to 1.0
            green: -0.5, // Should clamp to 0.0
            blue: 2.0,   // Should clamp to 1.0
            alpha: -1.0  // Should clamp to 0.0
        )

        XCTAssertNotNil(texture)
    }

    // MARK: - Texture Usage Tests

    func testFallbackTextureHasCorrectUsage() {
        let texture = factory.createFallback(size: 256)

        XCTAssertNotNil(texture)
        XCTAssertTrue(texture?.usage.contains(.shaderRead) ?? false)
    }

    func testCheckerboardTextureHasCorrectUsage() {
        let texture = factory.createCheckerboard(size: 64, tileSize: 8)

        XCTAssertNotNil(texture)
        XCTAssertTrue(texture?.usage.contains(.shaderRead) ?? false)
    }

    // MARK: - Mipmap Tests

    func testFallbackTextureHasMipmaps() {
        let texture = factory.createFallback(size: 256)

        XCTAssertNotNil(texture)
        XCTAssertEqual(texture?.mipmapLevelCount, 9) // log2(256) + 1
    }

    // MARK: - Description Tests

    func testDescription() {
        let description = factory.description
        XCTAssertTrue(description.contains("MTLTextureFactory"))
        XCTAssertTrue(description.contains(device.name))
    }
}

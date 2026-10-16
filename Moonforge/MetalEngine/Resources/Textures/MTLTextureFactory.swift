//
//  MTLTextureFactory.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 21.03.26.
//

import Metal
import Foundation

// MARK: - Metal Texture Factory Implementation

/// Concrete implementation of TextureFactory for creating procedural textures
///
/// This factory creates textures programmatically without loading from files:
/// - Fallback textures (gray checkerboard pattern)
/// - Custom checkerboard patterns
/// - Solid color textures
/// - Gradient textures (future extension)
///
/// Thread safety:
/// - This factory is thread-safe for concurrent texture creation
/// - Each creation operation is independent
///
/// Usage:
/// ```swift
/// let factory = MTLTextureFactory(device: device)
///
/// // Create fallback texture
/// let fallback = factory.createFallback(size: 256)
///
/// // Create custom checkerboard
/// let checkerboard = factory.createCheckerboard(size: 512, tileSize: 32)
///
/// // Create solid color texture
/// let redTexture = factory.createSolidColor(
///     size: 64,
///     red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0
/// )
/// ```
final class MTLTextureFactory: TextureFactory {
    private let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - TextureFactory Protocol

    /// Создать fallback текстуру (серая шашечка)
    func createFallback(size: Int) -> MTLTexture? {
        createCheckerboard(size: size, tileSize: 16, light: 200, dark: 100)
    }

    /// Создать текстуру шашечка
    func createCheckerboard(size: Int, tileSize: Int) -> MTLTexture? {
        createCheckerboard(size: size, tileSize: tileSize, light: 255, dark: 0)
    }

    /// Создать однотонную текстуру
    func createSolidColor(
        size: Int,
        red: Float,
        green: Float,
        blue: Float,
        alpha: Float
    ) -> MTLTexture? {
        guard size > 0 else { return nil }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        desc.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: desc) else {
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * size
        var pixelData = [UInt8](repeating: 0, count: size * size * bytesPerPixel)

        let r = UInt8(min(max(red * 255, 0), 255))
        let g = UInt8(min(max(green * 255, 0), 255))
        let b = UInt8(min(max(blue * 255, 0), 255))
        let a = UInt8(min(max(alpha * 255, 0), 255))

        for i in 0..<pixelData.count / 4 {
            pixelData[i * 4] = r
            pixelData[i * 4 + 1] = g
            pixelData[i * 4 + 2] = b
            pixelData[i * 4 + 3] = a
        }

        texture.replace(
            region: MTLRegion(origin: .init(), size: .init(width: size, height: size, depth: 1)),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: bytesPerRow
        )

        return texture
    }

    // MARK: - Private Methods

    /// Create a checkerboard pattern with custom colors
    private func createCheckerboard(
        size: Int,
        tileSize: Int,
        light: UInt8,
        dark: UInt8
    ) -> MTLTexture? {
        guard size > 0 && tileSize > 0 else { return nil }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: true
        )
        desc.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: desc) else {
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * size
        var pixelData = [UInt8](repeating: 0, count: size * size * bytesPerPixel)

        pixelData.withUnsafeMutableBytes { ptr in
            let buffer = ptr.bindMemory(to: UInt8.self)
            for y in 0..<size {
                for x in 0..<size {
                    let pattern = (x / tileSize + y / tileSize) % 2
                    let base: UInt8 = pattern == 0 ? light : dark
                    let idx = (y * size + x) * 4
                    buffer[idx] = base
                    buffer[idx + 1] = base
                    buffer[idx + 2] = base
                    buffer[idx + 3] = 255
                }
            }
        }

        texture.replace(
            region: MTLRegion(origin: .init(), size: .init(width: size, height: size, depth: 1)),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: bytesPerRow
        )

        // Populate every level before publication; sampling may select any mip.
        // Average the previous level, including all edge pixels for odd sizes.
        var previousSize = size
        var previousPixels = pixelData
        for level in 1..<texture.mipmapLevelCount {
            let levelSize = max(1, previousSize / 2)
            var pixels = [UInt8](repeating: 0, count: levelSize * levelSize * bytesPerPixel)
            for y in 0..<levelSize {
                let startY = y * previousSize / levelSize
                let endY = (y + 1) * previousSize / levelSize
                for x in 0..<levelSize {
                    let startX = x * previousSize / levelSize
                    let endX = (x + 1) * previousSize / levelSize
                    let sampleCount = (endX - startX) * (endY - startY)
                    for channel in 0..<bytesPerPixel {
                        var sum = 0
                        for sourceY in startY..<endY {
                            for sourceX in startX..<endX {
                                sum += Int(previousPixels[(sourceY * previousSize + sourceX) * bytesPerPixel + channel])
                            }
                        }
                        pixels[(y * levelSize + x) * bytesPerPixel + channel] = UInt8((sum + sampleCount / 2) / sampleCount)
                    }
                }
            }
            texture.replace(
                region: MTLRegion(origin: .init(), size: .init(width: levelSize, height: levelSize, depth: 1)),
                mipmapLevel: level,
                withBytes: pixels,
                bytesPerRow: levelSize * bytesPerPixel
            )
            previousSize = levelSize
            previousPixels = pixels
        }

        return texture
    }
}

// MARK: - CustomStringConvertible

extension MTLTextureFactory: CustomStringConvertible {
    var description: String {
        "MTLTextureFactory(device: \(device.name))"
    }
}

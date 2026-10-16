//
//  MTKTextureLoader.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 21.03.26.
//

@preconcurrency import Metal
@preconcurrency import MetalKit
import Foundation

// MARK: - MetalKit Texture Loader Implementation

/// Concrete implementation of TextureLoading using MetalKit's MTKTextureLoader
final class TextureLoader: TextureLoading, @unchecked Sendable {
    private let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - TextureLoading Protocol

    func load(from url: URL) async throws -> MTLTexture {
        let loader = MTKTextureLoader(device: device)
        return try await loader.newTexture(URL: url, options: options)
    }

    func load(named name: String, bundle: Bundle) async throws -> MTLTexture {
        try Task.checkCancellation()
        let loader = MTKTextureLoader(device: device)
        let texture = try await loader.newTexture(name: name, scaleFactor: 1, bundle: bundle, options: options)
        try Task.checkCancellation()
        return texture
    }

    private var options: [MTKTextureLoader.Option: Any] {
        [.generateMipmaps: true, .textureUsage: MTLTextureUsage.shaderRead.rawValue,
         .textureStorageMode: MTLStorageMode.private.rawValue]
    }

    func loadSync(from url: URL) throws -> MTLTexture {
        try MTKTextureLoader(device: device).newTexture(URL: url, options: options)
    }

    func loadSync(named name: String, bundle: Bundle) throws -> MTLTexture {
        try MTKTextureLoader(device: device).newTexture(name: name, scaleFactor: 1, bundle: bundle, options: options)
    }

    /// Загрузить текстуру из данных
    func load(from data: Data) async throws -> MTLTexture {
        let loader = MTKTextureLoader(device: device)
        return try await loader.newTexture(data: data, options: options)
    }
}

// MARK: - Texture Loading Error

/// Errors that can occur during texture loading
enum TextureLoadingError: LocalizedError {
    case unknown
    case invalidURL
    case fileNotFound
    case unsupportedFormat
    case deviceCreationFailed

    var errorDescription: String? {
        switch self {
        case .unknown:
            return "An unknown error occurred during texture loading"
        case .invalidURL:
            return "The specified URL is invalid"
        case .fileNotFound:
            return "The texture file was not found"
        case .unsupportedFormat:
            return "The texture format is not supported"
        case .deviceCreationFailed:
            return "Failed to create Metal device for texture loading"
        }
    }
}

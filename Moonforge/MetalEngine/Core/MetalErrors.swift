//
//  MetalErrors.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 21.10.25.
//

import Foundation

// MARK: - MetalError

enum MetalError: Error, LocalizedError, CustomStringConvertible {
    case deviceNotFound
    case commandQueueCreationFailed
    case libraryCreationFailed
    case shaderFunctionNotFound(String)
    case pipelineCreationFailed(String)
    case textureCreationFailed
    case modelLoadingFailed(String)
    case bufferCreationFailed
    case samplerCreationFailed

    public var localizedDescription: String {
        switch self {
        case .deviceNotFound: return "Metal device not available"
        case .commandQueueCreationFailed: return "Failed to create command queue"
        case .libraryCreationFailed: return "Failed to create Metal library"
        case .shaderFunctionNotFound(let name): return "Shader function '\(name)' not found"
        case .pipelineCreationFailed(let details): return "Pipeline creation failed: \(details)"
        case .textureCreationFailed: return "Failed to create texture"
        case .modelLoadingFailed(let details): return "Model loading failed: \(details)"
        case .bufferCreationFailed: return "Failed to create buffer"
        case .samplerCreationFailed: return "Failed to create sampler"
        }
    }

    public var errorDescription: String? { localizedDescription }

    public var description: String { localizedDescription }
}

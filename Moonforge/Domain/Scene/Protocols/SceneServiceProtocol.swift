//
//  SceneServiceProtocol.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 21.03.26.
//

import Foundation

// MARK: - Scene Service Protocol

/// Protocol for scene management operations.
/// Used by ViewModel to interact with the scene without depending on MetalEngine.
@MainActor
protocol SceneServiceProtocol {
    /// Switch to a geometry by name
    func switchGeometry(to name: String) async throws
    
    /// Toggle model texture visibility
    func toggleModelTexture() async
    
    /// Adjust camera with a delta
    func adjustCamera(delta: CameraDelta) async
    
    /// Get available geometry names
    func getAvailableGeometries() -> [String]
    
    /// Get current geometry name
    func getCurrentGeometry() -> String
    
    /// Check if model texture is enabled
    func isModelTextureEnabled() -> Bool
}

// MARK: - Camera Delta

/// Camera adjustment delta for use cases
enum CameraDelta {
    case pinch(scale: Float)
}

//
//  RenderDebugInfo.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Foundation

// MARK: - Render Debug Info

/// Debug информация о состоянии рендера
struct RenderDebugInfo: Sendable {
    let sessionId: String
    let geometryName: String
    let pipelineCacheCount: Int
    let snapshotReady: Bool
    let textureReady: Bool
    let modelStatus: ModelLoadStatus
    let modelTextureEnabled: Bool
    let cameraDistance: Float
    let submeshCount: Int
    let texturedSubmeshCount: Int
}

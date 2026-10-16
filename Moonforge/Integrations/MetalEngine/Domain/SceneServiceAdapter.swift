//
//  SceneServiceAdapter.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 21.03.26.
//

import Foundation

// MARK: - Scene Service Adapter

/// Adapter, который соединяет компоненты MetalEngine с Domain SceneServiceProtocol.
/// Этот adapter реализует SceneServiceProtocol через делегирование engine capability протоколам.
@MainActor
final class SceneServiceAdapter: SceneServiceProtocol {
    // MARK: - Properties

    private weak var geometrySwitcher: GeometrySwitching?
    private weak var modelTextureSwitcher: ModelTextureSwitching?
    private weak var cameraController: CameraControlling?
    private let logger: MetalLogger

    // MARK: - Initialization

    /// Инициализация adapter с компонентами MetalEngine.
    /// - Parameters:
    ///   - renderer: Metal renderer, соответствующий протоколам switching
    ///   - logger: Logger для диагностического вывода
    init(renderer: MetalRenderable, logger: MetalLogger) {
        self.logger = logger

        self.geometrySwitcher = renderer as? GeometrySwitching
        self.modelTextureSwitcher = renderer as? ModelTextureSwitching
        self.cameraController = renderer as? CameraControlling
    }

    // MARK: - SceneServiceProtocol

    func switchGeometry(to name: String) async throws {
        guard let geometrySwitcher = geometrySwitcher else {
            throw SceneServiceError.componentNotAvailable("GeometrySwitching")
        }
        logger.log("SceneService: Switching geometry to '\(name)'", level: .info)
        try await geometrySwitcher.switchGeometryAsync(named: name)
    }

    func toggleModelTexture() async {
        guard let modelTextureSwitcher = modelTextureSwitcher else {
            logger.log("SceneService: ModelTextureSwitching not available", level: .warning)
            return
        }
        let newValue = !modelTextureSwitcher.isModelTextureEnabled()
        logger.log("SceneService: Toggling model texture to \(newValue)", level: .debug)
        modelTextureSwitcher.setModelTextureEnabled(newValue)
    }

    func adjustCamera(delta: CameraDelta) async {
        guard let cameraController = cameraController else {
            logger.log("SceneService: CameraControlling not available", level: .warning)
            return
        }
        switch delta {
        case .pinch(let scale):
            cameraController.applyPinch(scale: scale)
        }
    }

    func getAvailableGeometries() -> [String] {
        geometrySwitcher?.availableGeometries ?? []
    }

    func getCurrentGeometry() -> String {
        geometrySwitcher?.currentGeometryName ?? ""
    }

    func isModelTextureEnabled() -> Bool {
        modelTextureSwitcher?.isModelTextureEnabled() ?? true
    }

    // MARK: - Cleanup

    deinit {
        logger.log("SceneServiceAdapter deallocated", level: .debug)
    }
}

// MARK: - Geometry Switching Conformance

extension SceneServiceAdapter: GeometrySwitching {
    var geometrySwitchError: Error? { geometrySwitcher?.geometrySwitchError }
    var availableGeometries: [String] {
        getAvailableGeometries()
    }

    var currentGeometryName: String {
        getCurrentGeometry()
    }

    func switchGeometryAsync(named name: String) async throws {
        try await switchGeometry(to: name)
    }

    func switchGeometry(named name: String) {
        // Preserve the synchronous capability contract so callers can inspect the result.
        geometrySwitcher?.switchGeometry(named: name)
    }
}

// MARK: - Model Texture Switching Conformance

extension SceneServiceAdapter: ModelTextureSwitching {
    func setModelTextureEnabled(_ enabled: Bool) {
        modelTextureSwitcher?.setModelTextureEnabled(enabled)
    }
}

// MARK: - Camera Controlling Conformance

extension SceneServiceAdapter: CameraControlling {
    func orbit(deltaX: Float, deltaY: Float) {
        logger.log("SceneService: Camera orbit is not used in the current interaction model", level: .debug)
    }

    func pan(deltaX: Float, deltaY: Float) {
        // Not implemented - pan not supported in this adapter
        logger.log("SceneService: Pan not implemented", level: .warning)
    }

    func applyPinch(scale: Float) {
        Task {
            await adjustCamera(delta: .pinch(scale: scale))
        }
    }

    func resetCamera() {
        // Not implemented - reset not supported in this adapter
        logger.log("SceneService: Reset camera not implemented", level: .warning)
    }
}

// MARK: - Scene Service Error

/// Errors that can occur in SceneService operations
enum SceneServiceError: LocalizedError {
    case componentNotAvailable(String)
    case geometryNotFound(String)

    var errorDescription: String? {
        switch self {
        case .componentNotAvailable(let component):
            return "Required component '\(component)' is not available"
        case .geometryNotFound(let name):
            return "Geometry '\(name)' was not found"
        }
    }
}

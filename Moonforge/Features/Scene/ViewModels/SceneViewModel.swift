//
//  SceneViewModel.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Foundation
import Observation

// MARK: - Scene View Model

/// ViewModel для SceneView — управление состоянием с использованием Observation.
/// Использует UseCase pattern для бизнес-логики.
@MainActor
@Observable
final class SceneViewModel: MetalRendererDelegate {
    // MARK: - Properties

    var rotationSensitivity: Double = 0.005 {
        didSet {
            let clampedValue = rotationSensitivity.clamped(to: rotationSensitivityRange)
            if rotationSensitivity != clampedValue {
                rotationSensitivity = clampedValue
                return
            }

            guard oldValue != rotationSensitivity else { return }
            scheduleRotationUpdate()
        }
    }

    var velocitySensitivity: Double = 0.0001 {
        didSet {
            let clampedValue = velocitySensitivity.clamped(to: velocitySensitivityRange)
            if velocitySensitivity != clampedValue {
                velocitySensitivity = clampedValue
                return
            }

            guard oldValue != velocitySensitivity else { return }
            scheduleRotationUpdate()
        }
    }

    var errorMessage: String?

    // MARK: - Computed Properties (from debugService)

    var fps: Double? {
        get { debugService.fps }
        set { debugService.fps = newValue }
    }

    var debugInfo: RenderDebugInfo? {
        get { debugService.debugInfo }
        set { debugService.debugInfo = newValue }
    }

    var availableGeometries: [String] {
        debugService.availableGeometries
    }

    var selectedGeometry: String {
        get { debugService.selectedGeometry }
        set { debugService.selectedGeometry = newValue }
    }

    var modelTextureEnabled: Bool {
        get { debugService.modelTextureEnabled }
        set { debugService.modelTextureEnabled = newValue }
    }

    // MARK: - Configuration

    private let rotationSensitivityRange: ClosedRange<Double> = 0.000001...0.1
    private let velocitySensitivityRange: ClosedRange<Double> = 0.0000001...0.01

    // MARK: - Private Properties

    @ObservationIgnored
    private let switchGeometryUseCase: SwitchGeometryUseCase
    @ObservationIgnored
    private let toggleModelTextureUseCase: ToggleModelTextureUseCase
    @ObservationIgnored
    private let adjustCameraUseCase: AdjustCameraUseCase
    @ObservationIgnored
    private let sceneService: SceneServiceProtocol
    @ObservationIgnored
    private let logger: MetalLogger
    @ObservationIgnored
    let renderer: MetalRenderable
    @ObservationIgnored
    private let debugService: SceneDebugService

    // MARK: - Initialization

    /// Initialize the ViewModel with UseCases and renderer.
    /// - Parameters:
    ///   - switchGeometryUseCase: UseCase for switching geometry
    ///   - toggleModelTextureUseCase: UseCase for toggling model texture
    ///   - adjustCameraUseCase: UseCase for adjusting camera
    ///   - sceneService: Service for scene operations
    ///   - renderer: Metal renderer for direct operations
    ///   - logger: Logger for diagnostic output
    init(
        switchGeometryUseCase: SwitchGeometryUseCase,
        toggleModelTextureUseCase: ToggleModelTextureUseCase,
        adjustCameraUseCase: AdjustCameraUseCase,
        sceneService: SceneServiceProtocol,
        renderer: MetalRenderable,
        logger: MetalLogger
    ) {
        self.switchGeometryUseCase = switchGeometryUseCase
        self.toggleModelTextureUseCase = toggleModelTextureUseCase
        self.adjustCameraUseCase = adjustCameraUseCase
        self.sceneService = sceneService
        self.renderer = renderer
        self.logger = logger
        
        // Safe cast с fallback для renderer, который не поддерживает debug info
        let debugInfoProvider: RenderDebugInfoProvider
        if let provider = renderer as? RenderDebugInfoProvider {
            debugInfoProvider = provider
        } else {
            debugInfoProvider = EmptyDebugInfoProvider()
            logger.log("Renderer doesn't conform to RenderDebugInfoProvider — using empty provider", level: .warning)
        }
        
        self.debugService = SceneDebugService(
            debugInfoProvider: debugInfoProvider,
            sceneService: sceneService
        )

        renderer.delegate = self
    }
    // MARK: - State Updates

    func updateRotationSensitivity(_ value: Double) {
        rotationSensitivity = value
    }

    func updateVelocitySensitivity(_ value: Double) {
        velocitySensitivity = value
    }

    func clearError() {
        errorMessage = nil
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    func selectGeometry(_ name: String) {
        guard selectedGeometry != name else { return }

        Task {
            do {
                try await switchGeometryUseCase.execute(geometryName: name)
                selectedGeometry = switchGeometryUseCase.getCurrentGeometry()
                clearError()
                logger.log("Geometry switched to: \(name)", level: .info)
            } catch is CancellationError {
                return
            } catch {
                selectedGeometry = switchGeometryUseCase.getCurrentGeometry()
                logger.log("Failed to switch geometry: \(error.localizedDescription)", level: .error)
                setError(error.localizedDescription)
            }
        }
    }

    func toggleModelTexture() {
        Task {
            await toggleModelTextureUseCase.execute()
            modelTextureEnabled = toggleModelTextureUseCase.isModelTextureEnabled()
        }
    }

    func rotateObject(deltaX: Float, deltaY: Float) {
        guard let objectRotator = renderer as? ObjectRotating else {
            logger.log("Renderer doesn't conform to ObjectRotating", level: .warning)
            return
        }

        objectRotator.rotateObject(deltaX: deltaX, deltaY: deltaY)
    }

    func applyPinchScale(_ scale: Float) {
        guard let cameraController = renderer as? CameraControlling else {
            logger.log("Renderer doesn't conform to CameraControlling", level: .warning)
            return
        }

        cameraController.applyPinch(scale: scale)
    }

    // MARK: - MetalRendererDelegate

    @MainActor
    func renderer(_ renderer: MetalRenderable, didFailWithError error: Error) {
        setError(error.localizedDescription)
    }

    @MainActor
    func renderer(_ renderer: MetalRenderable, didUpdateFPS fps: Double) {
        debugService.fps = fps
    }

    // MARK: - Private Methods

    private func scheduleRotationUpdate() {
        logger.log(
            "Object rotation sensitivity updated: rotation=\(rotationSensitivity), velocityLegacy=\(velocitySensitivity)",
            level: .debug
        )
    }
}

// MARK: - Comparable Extension

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Empty Debug Info Provider

/// Fallback provider для renderer, которые не поддерживают debug info
@MainActor
private final class EmptyDebugInfoProvider: RenderDebugInfoProvider {
    var debugInfo: RenderDebugInfo {
        RenderDebugInfo(
            sessionId: "empty",
            geometryName: "unknown",
            pipelineCacheCount: 0,
            snapshotReady: false,
            textureReady: false,
            modelStatus: .notApplicable,
            modelTextureEnabled: false,
            cameraDistance: 0,
            submeshCount: 0,
            texturedSubmeshCount: 0
        )
    }
}

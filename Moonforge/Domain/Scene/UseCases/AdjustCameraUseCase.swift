//
//  AdjustCameraUseCase.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 21.03.26.
//

import Foundation

// MARK: - Adjust Camera Use Case Protocol

/// Protocol for adjusting camera with delta values
@MainActor
protocol AdjustCameraUseCase {
    /// Adjust camera with delta
    func execute(delta: CameraDelta) async
}

// MARK: - Default Implementation

/// Default implementation using CameraControlling
@MainActor
final class DefaultAdjustCameraUseCase: AdjustCameraUseCase {
    private let cameraController: CameraControlling
    private let logger: MetalLogger

    init(cameraController: CameraControlling, logger: MetalLogger) {
        self.cameraController = cameraController
        self.logger = logger
    }

    func execute(delta: CameraDelta) async {
        switch delta {
        case .pinch(let scale):
            logger.log("Applying pinch to camera: scale=\(scale)", level: .debug)
            cameraController.applyPinch(scale: scale)
        }
    }
}

//
//  SwitchGeometryUseCase.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 21.03.26.
//

import Foundation

// MARK: - Switch Geometry Use Case Protocol

/// Protocol for switching geometry in the scene
@MainActor
protocol SwitchGeometryUseCase {
    /// Переключиться на геометрию по имени
    func execute(geometryName: String) async throws

    /// Получить доступные имена геометрий
    func getAvailableGeometries() -> [String]

    /// Получить текущую геометрию
    func getCurrentGeometry() -> String
}

// MARK: - Default Implementation

/// Default implementation using GeometrySwitching
@MainActor
final class DefaultSwitchGeometryUseCase: SwitchGeometryUseCase {
    private let geometrySwitcher: GeometrySwitching
    private let logger: MetalLogger

    init(geometrySwitcher: GeometrySwitching, logger: MetalLogger) {
        self.geometrySwitcher = geometrySwitcher
        self.logger = logger
    }

    func execute(geometryName: String) async throws {
        logger.log("Switching geometry to: \(geometryName)", level: .info)
        try await geometrySwitcher.switchGeometryAsync(named: geometryName)
    }

    func getAvailableGeometries() -> [String] {
        geometrySwitcher.availableGeometries
    }

    func getCurrentGeometry() -> String {
        geometrySwitcher.currentGeometryName
    }
}

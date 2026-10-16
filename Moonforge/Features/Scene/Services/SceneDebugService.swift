//
//  SceneDebugService.swift
//  Moonforge
//
//  Сервис для обновления debug информации (FPS, render stats).
//  Выделен из SceneViewModel для соблюдения Single Responsibility.
//

import Foundation
import Observation

/// Сервис для получения и обновления debug информации о рендерере.
@Observable
@MainActor
final class SceneDebugService {
    // MARK: - Properties

    var fps: Double?
    var debugInfo: RenderDebugInfo?
    var availableGeometries: [String] = []
    var selectedGeometry: String = ""
    var modelTextureEnabled: Bool = true

    // MARK: - Private Properties

    @ObservationIgnored
    private let debugInfoProvider: RenderDebugInfoProvider
    @ObservationIgnored
    private let sceneService: SceneServiceProtocol
    @ObservationIgnored
    private var debugInfoTask: Task<Void, Never>?
    @ObservationIgnored
    private let debugInfoInterval: TimeInterval = 0.5

    // MARK: - Initialization

    init(
        debugInfoProvider: RenderDebugInfoProvider,
        sceneService: SceneServiceProtocol
    ) {
        self.debugInfoProvider = debugInfoProvider
        self.sceneService = sceneService
        setupDebugInfoUpdates()
    }

    deinit {
        debugInfoTask?.cancel()
    }

    // MARK: - Private Methods

    private func setupDebugInfoUpdates() {
        debugInfoTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.debugInfoInterval ?? 0
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

                guard let self, !Task.isCancelled else { break }

                // Получаем debug info от рендерера
                self.debugInfo = self.debugInfoProvider.debugInfo

                // Обновляем данные из scene service
                let names = self.sceneService.getAvailableGeometries()
                if !names.isEmpty {
                    self.availableGeometries = names
                }

                let current = self.sceneService.getCurrentGeometry()
                if !current.isEmpty {
                    self.selectedGeometry = current
                } else if self.selectedGeometry.isEmpty, let first = names.first {
                    self.selectedGeometry = first
                }

                self.modelTextureEnabled = self.sceneService.isModelTextureEnabled()
            }
        }
    }
}

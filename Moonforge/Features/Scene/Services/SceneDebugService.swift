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
    private var lastRunningTask: Task<Void, Never>?
    @ObservationIgnored
    private let interval: Duration
    @ObservationIgnored
    private let clock: any Clock<Duration>

    // MARK: - Initialization

    init(
        debugInfoProvider: RenderDebugInfoProvider,
        sceneService: SceneServiceProtocol,
        interval: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.debugInfoProvider = debugInfoProvider
        self.sceneService = sceneService
        self.interval = interval
        self.clock = clock
    }

    deinit {
        debugInfoTask?.cancel()
        lastRunningTask?.cancel()
    }

    // MARK: - Polling Control

    /// Указывает, активен ли в данный момент фоновый опрос debug-информации.
    var isPolling: Bool {
        debugInfoTask != nil
    }

    /// Запускает периодический опрос debug-информации.
    /// Метод идемпотентен: если опрос уже активен, повторный запуск не создает новую задачу.
    /// Перед началом ожидания интервала выполняет немедленное обновление данных.
    func startPolling() {
        if let task = debugInfoTask, !task.isCancelled {
            return
        }
        debugInfoTask?.cancel()
        debugInfoTask = nil

        // Немедленное обновление данных при старте
        updateDebugInfo()

        let clock = self.clock
        let interval = self.interval

        let task = Task { [weak self, clock, interval] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: interval)
                } catch {
                    // Обработка CancellationError: при отмене задачи прерываем цикл немедленно
                    break
                }

                guard let self, !Task.isCancelled else { break }

                self.updateDebugInfo()
            }
        }
        debugInfoTask = task
        lastRunningTask = task
    }

    /// Останавливает опрос debug-информации и отменяет текущую задачу.
    /// Метод идемпотентен: безопасен для многократного вызова.
    func stopPolling() {
        debugInfoTask?.cancel()
        debugInfoTask = nil
    }

    /// Останавливает опрос debug-информации и ожидает завершения текущей фоновой задачи.
    /// Метод отменяет текущую задачу опроса и дожидается её фактического завершения.
    func stopPollingAndWait() async {
        let task = debugInfoTask ?? lastRunningTask
        stopPolling()
        if let task {
            _ = await task.result
        }
        if lastRunningTask == task {
            lastRunningTask = nil
        }
    }

    // MARK: - Private Methods

    private func updateDebugInfo() {
        // Получаем debug info от рендерера
        debugInfo = debugInfoProvider.debugInfo

        // Обновляем данные из scene service
        let names = sceneService.getAvailableGeometries()
        if !names.isEmpty {
            availableGeometries = names
        }

        let current = sceneService.getCurrentGeometry()
        if !current.isEmpty {
            selectedGeometry = current
        } else if selectedGeometry.isEmpty, let first = names.first {
            selectedGeometry = first
        }

        modelTextureEnabled = sceneService.isModelTextureEnabled()
    }
}

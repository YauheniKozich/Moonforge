//
//  RenderTimingComponent.swift
//  Moonforge
//
//  Created on 20.03.26.
//

import Foundation
import QuartzCore
import os

// MARK: - Render Timing Component

/// Потокобезопасный компонент для отслеживания времени кадров и delta time.
///
/// Модель потокобезопасности:
/// - update: вызывается каждый кадр (render thread)
/// - deltaTime, currentFPS: чтение из любого потока
/// - reset: сброс при переходе в background
final class RenderTimingComponent: Sendable {
    private let stateLock = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var lastUpdateTime: CFTimeInterval = 0
        var deltaTime: Float = 0
        var frameCount: Int = 0
        var fpsUpdateTime: CFTimeInterval = 0
        var currentFPS: Double = 0
    }

    // MARK: - Configuration

    private let targetFrameTime: Float

    // MARK: - Initialization

    init(targetFrameTime: Float) {
        self.targetFrameTime = targetFrameTime
    }

    // MARK: - Default Initialization

    convenience init() {
        self.init(targetFrameTime: MetalConfiguration.Performance.targetFrameTime)
    }

    // MARK: - Timing Updates

    /// Обновить время и вернуть дельту с последнего вызова
    ///
    /// - Returns: Delta time в секундах, ограниченная 2x target frame time
    func update() -> Float {
        stateLock.withLock { state in
            let currentTime = CACurrentMediaTime()

            // Initialize on first call
            if state.lastUpdateTime == 0 {
                state.lastUpdateTime = currentTime
                state.deltaTime = targetFrameTime
                state.fpsUpdateTime = currentTime
                return state.deltaTime
            }

            // Calculate delta time
            var deltaTime = Float(currentTime - state.lastUpdateTime)

            // Cap delta time to avoid large jumps (e.g., after app suspension)
            let maxDelta = targetFrameTime * 2
            deltaTime = min(deltaTime, maxDelta)

            state.deltaTime = deltaTime
            state.lastUpdateTime = currentTime

            // Update FPS calculation
            state.frameCount += 1
            let fpsElapsed = currentTime - state.fpsUpdateTime
            if fpsElapsed >= 1.0 {
                state.currentFPS = Double(state.frameCount) / fpsElapsed
                state.frameCount = 0
                state.fpsUpdateTime = currentTime
            }

            return state.deltaTime
        }
    }

    /// Получить текущую дельту времени
    var deltaTime: Float {
        stateLock.withLock { $0.deltaTime }
    }

    /// Получить текущий FPS (кадров в секунду)
    var currentFPS: Double {
        stateLock.withLock { $0.currentFPS }
    }

    // MARK: - Reset

    /// Сбросить состояние
    /// Вызывать при переходе в background или при необходимости перекалибровки
    func reset() {
        stateLock.withLock { state in
            state.lastUpdateTime = 0
            state.deltaTime = 0
            state.frameCount = 0
            state.fpsUpdateTime = 0
            state.currentFPS = 0
        }
    }
}

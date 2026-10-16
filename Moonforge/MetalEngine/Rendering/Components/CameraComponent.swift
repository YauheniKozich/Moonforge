//
//  CameraComponent.swift
//  Moonforge
//
//  Created on 20.03.26.
//

import Foundation
import QuartzCore
import simd
import os

// MARK: - Camera State

/// Значение состояния камеры — безопасно для копирования между потоками.
/// Используется для double buffering: пока render thread рисует с позицией А,
/// main thread может вычислять позицию Б без интерференции.
struct CameraState: Sendable {
    var yaw: Float
    var pitch: Float
    var distance: Float
    var pan: SIMD2<Float>
    var minimumHeight: Float?

    init(
        yaw: Float = 0,
        pitch: Float = 0,
        distance: Float = MetalConfiguration.Geometry.cameraDistance,
        pan: SIMD2<Float> = .zero,
        minimumHeight: Float? = nil
    ) {
        self.yaw = yaw
        self.pitch = pitch
        self.distance = distance
        self.pan = pan
        self.minimumHeight = minimumHeight
    }
}

// MARK: - Camera Component

/// Потокобезопасный компонент камеры с использованием OSAllocatedUnfairLock.
///
/// Модель потокобезопасности:
/// - orbit, pan, zoom, reset: изменение состояния (Main thread)
/// - getStateSnapshot: копия состояния (любой поток)
/// - computeViewMatrix: чистая функция (любой поток)
final class CameraComponent: Sendable {
    private let stateLock = OSAllocatedUnfairLock(initialState: CameraState())

    // MARK: - Configuration

    private let minDistance: Float
    private let maxDistance: Float
    private let orbitSensitivity: Float
    private let panSensitivity: Float
    private let pinchSensitivity: Float
    private let maxPitch: Float

    // MARK: - Initialization

    init(
        minDistance: Float,
        maxDistance: Float,
        orbitSensitivity: Float,
        panSensitivity: Float,
        pinchSensitivity: Float,
        maxPitch: Float
    ) {
        self.minDistance = minDistance
        self.maxDistance = maxDistance
        self.orbitSensitivity = orbitSensitivity
        self.panSensitivity = panSensitivity
        self.pinchSensitivity = pinchSensitivity
        self.maxPitch = maxPitch
    }

    // MARK: - Default Initialization

    convenience init() {
        self.init(
            minDistance: MetalConfiguration.Camera.minDistance,
            maxDistance: MetalConfiguration.Camera.maxDistance,
            orbitSensitivity: MetalConfiguration.Camera.orbitSensitivity,
            panSensitivity: MetalConfiguration.Camera.panSensitivity,
            pinchSensitivity: MetalConfiguration.Camera.pinchSensitivity,
            maxPitch: MetalConfiguration.Camera.maxPitch
        )
    }

    // MARK: - Camera Controls (Mutable)

    /// Применить вращение орбиты
    func orbit(deltaX: Float, deltaY: Float) {
        guard deltaX.isFinite, deltaY.isFinite else { return }
        stateLock.withLock { state in
            state.yaw += deltaX * orbitSensitivity
            state.pitch -= deltaY * orbitSensitivity
            // Clamp pitch to avoid gimbal lock
            state.pitch = max(-maxPitch, min(maxPitch, state.pitch))
            state = Self.constrained(state, maxPitch: maxPitch)
        }
    }

    /// Применить перемещение камеры
    func pan(deltaX: Float, deltaY: Float) {
        guard deltaX.isFinite, deltaY.isFinite else { return }
        stateLock.withLock { state in
            state.pan.x += deltaX * panSensitivity
            state.pan.y += deltaY * panSensitivity
            state = Self.constrained(state, maxPitch: maxPitch)
        }
    }

    /// Apply direct pinch scale to camera-object distance.
    func applyPinch(scale: Float) {
        guard scale.isFinite, scale > 0 else { return }
        let clampedScale = max(0.01, scale)
        stateLock.withLock { state in
            let adjustedScale = pow(clampedScale, pinchSensitivity)
            state.distance *= adjustedScale
            state.distance = max(minDistance, min(maxDistance, state.distance))
            state = Self.constrained(state, maxPitch: maxPitch)
        }
    }

    /// Установить дистанцию камеры явно с clamp в допустимый диапазон.
    func setDistance(_ distance: Float) {
        guard distance.isFinite else { return }
        stateLock.withLock { state in
            state.distance = max(minDistance, min(maxDistance, distance))
            state = Self.constrained(state, maxPitch: maxPitch)
        }
    }

    /// Сбросить камеру
    func reset(distance: Float? = nil) {
        stateLock.withLock { state in
            let requestedDistance = distance ?? MetalConfiguration.Geometry.cameraDistance
            guard requestedDistance.isFinite else { return }
            state = Self.constrained(CameraState(
                distance: max(minDistance, min(maxDistance, requestedDistance)),
                minimumHeight: state.minimumHeight
            ), maxPitch: maxPitch)
        }
    }

    /// Ограничение высоты глаза камеры в мировых координатах.
    func setMinimumHeight(_ height: Float) {
        guard height.isFinite else { return }
        stateLock.withLock { state in
            state.minimumHeight = height
            state = Self.constrained(state, maxPitch: maxPitch)
        }
    }

    /// Apply to both target and interpolated camera states, including viewport fitting.
    static func constrained(
        _ input: CameraState,
        maxPitch: Float = MetalConfiguration.Camera.maxPitch
    ) -> CameraState {
        guard let height = input.minimumHeight else { return input }
        var state = input
        // For T * Rx * Ry, world eye Y = pan.y * cos(pitch) + distance * sin(pitch).
        let eyeHeight = state.pan.y * cos(state.pitch) + state.distance * sin(state.pitch)
        guard eyeHeight < height else { return state }
        let radius = hypot(state.pan.y, state.distance)
        if radius > 0 {
            let phase = atan2(state.pan.y, state.distance)
            let minPitchLimit = asin(max(-1, min(1, height / radius))) - phase
            state.pitch = min(maxPitch, max(-maxPitch, max(state.pitch, minPitchLimit)))
        }
        // Extreme panning may make the pitch limit insufficient; correct vertical pan too.
        let minimumPanY = (height - state.distance * sin(state.pitch)) / cos(state.pitch)
        state.pan.y = max(state.pan.y, minimumPanY)
        return state
    }

    // MARK: - State Access (Read-only)

    /// Получить снимок состояния — безопасно для любого потока
    func getStateSnapshot() -> CameraState {
        stateLock.withLock { $0 }
    }

    // MARK: - View Matrix Calculation

    /// Вычислить view matrix для заданного состояния
    func computeViewMatrix(for state: CameraState) -> float4x4 {
        let state = Self.constrained(state, maxPitch: maxPitch)
        let t = float4x4.translation([ -state.pan.x, -state.pan.y, -state.distance ])
        let r = float4x4.rotationX(state.pitch) * float4x4.rotationY(state.yaw)
        return t * r
    }

    /// Вычислить view matrix для текущего состояния
    func computeViewMatrix() -> float4x4 {
        let state = getStateSnapshot()
        return computeViewMatrix(for: state)
    }
}

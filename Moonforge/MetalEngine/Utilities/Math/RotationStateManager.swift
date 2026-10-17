//
//  RotationStateManager.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Foundation
import simd
import os

// MARK: - Rotation State Data

/// Value type for rotation state
struct RotationStateData: Sendable {
    var x: Float = 0
    var y: Float = 0
    var z: Float = 0

    // MARK: - State Updates

    /// Apply user input rotation
    mutating func applyInput(x: Float, y: Float) {
        self.x += x
        self.y += y
    }

    /// Reset rotation to default centered orientation.
    mutating func reset() {
        x = 0
        y = 0
        z = 0
    }
}

// MARK: - Thread-Safe Manager

/// Thread-safe rotation state manager using OSAllocatedUnfairLock.
/// Can be called from any thread (Main thread for UI input, Metal thread for rendering).
public final class RotationStateManager: Sendable {
    private let stateLock = OSAllocatedUnfairLock(initialState: RotationStateData())

    public init() {}

    /// Apply user input rotation
    func applyInput(x: Float, y: Float) {
        stateLock.withLock { $0.applyInput(x: x, y: y) }
    }

    /// Reset rotation state
    func reset() {
        stateLock.withLock { $0.reset() }
    }

    /// Reserved for future interaction extensions (inertia/auto-rotate).
    func update(deltaTime: Float) {
        _ = deltaTime
    }

    /// Get snapshot of current rotation state — safe to copy from any thread
    func getSnapshot() -> SIMD3<Float> {
        stateLock.withLock { state in
            SIMD3<Float>(state.x, state.y, state.z)
        }
    }

    /// Check if rotation is active (for rendering optimization)
    public var isMoving: Bool {
        stateLock.withLock {
            abs($0.x) > 0.0001 || abs($0.y) > 0.0001 || abs($0.z) > 0.0001
        }
    }
}

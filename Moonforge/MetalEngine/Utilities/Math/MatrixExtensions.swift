//
//  MatrixExtensions.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 21.10.25.
//

import simd

// MARK: - Matrix Extensions

public extension float4x4 {
    /// Identity matrix for fallback and initialization
    static let identity = float4x4([
        [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]
    ])

    static func rotationX(_ a: Float) -> float4x4 {
        float4x4([
            [1, 0, 0, 0], [0, cos(a), sin(a), 0], [0, -sin(a), cos(a), 0], [0, 0, 0, 1]
        ])
    }
    static func rotationY(_ a: Float) -> float4x4 {
        float4x4([
            [cos(a), 0, -sin(a), 0], [0, 1, 0, 0], [sin(a), 0, cos(a), 0], [0, 0, 0, 1]
        ])
    }
    static func rotationZ(_ a: Float) -> float4x4 {
        float4x4([
            [cos(a), sin(a), 0, 0], [-sin(a), cos(a), 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]
        ])
    }
    static func translation(_ t: SIMD3<Float>) -> float4x4 {
        float4x4([
            [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [t.x, t.y, t.z, 1]
        ])
    }
    static func perspectiveFov(_ fovY: Float, aspect: Float, nearZ: Float, farZ: Float) -> float4x4 {
        let y = 1 / tan(fovY*0.5)
        let x = y / aspect
        let z = farZ / (nearZ - farZ)
        return float4x4([
            [x, 0, 0, 0], [0, y, 0, 0], [0, 0, z, -1], [0, 0, z*nearZ, 0]
        ])
    }
}

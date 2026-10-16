//
//  MatrixExtensionsTests.swift
//  MoonforgeTests
//
//  Created on 20.03.26.
//

import XCTest
import simd
@testable import Moonforge

final class MatrixExtensionsTests: XCTestCase {
    
    // MARK: - Identity
    
    func testIdentity() {
        let identity = float4x4.identity
        
        // Diagonal should be 1
        XCTAssertEqual(identity.columns.0.x, 1, accuracy: 0.001)
        XCTAssertEqual(identity.columns.1.y, 1, accuracy: 0.001)
        XCTAssertEqual(identity.columns.2.z, 1, accuracy: 0.001)
        XCTAssertEqual(identity.columns.3.w, 1, accuracy: 0.001)
        
        // Off-diagonal should be 0
        XCTAssertEqual(identity.columns.0.y, 0, accuracy: 0.001)
        XCTAssertEqual(identity.columns.0.z, 0, accuracy: 0.001)
        XCTAssertEqual(identity.columns.0.w, 0, accuracy: 0.001)
        XCTAssertEqual(identity.columns.1.x, 0, accuracy: 0.001)
    }
    
    // MARK: - Rotation X
    
    func testRotationX() {
        let angle: Float = .pi / 2
        let rotation = float4x4.rotationX(angle)
        
        // X-axis should be unchanged
        XCTAssertEqual(rotation.columns.0.x, 1, accuracy: 0.001)
        XCTAssertEqual(rotation.columns.0.y, 0, accuracy: 0.001)
        XCTAssertEqual(rotation.columns.0.z, 0, accuracy: 0.001)
        
        // Y and Z should be rotated
        XCTAssertEqual(rotation.columns.1.y, cos(angle), accuracy: 0.001)
        XCTAssertEqual(rotation.columns.1.z, sin(angle), accuracy: 0.001)
        XCTAssertEqual(rotation.columns.2.y, -sin(angle), accuracy: 0.001)
        XCTAssertEqual(rotation.columns.2.z, cos(angle), accuracy: 0.001)
    }
    
    func testRotationXZeroAngle() {
        let rotation = float4x4.rotationX(0)
        XCTAssertEqual(rotation, .identity)
    }
    
    // MARK: - Rotation Y
    
    func testRotationY() {
        let angle: Float = .pi / 2
        let rotation = float4x4.rotationY(angle)
        
        // Y-axis should be unchanged
        XCTAssertEqual(rotation.columns.1.x, 0, accuracy: 0.001)
        XCTAssertEqual(rotation.columns.1.y, 1, accuracy: 0.001)
        XCTAssertEqual(rotation.columns.1.z, 0, accuracy: 0.001)
        
        // X and Z should be rotated
        XCTAssertEqual(rotation.columns.0.x, cos(angle), accuracy: 0.001)
        XCTAssertEqual(rotation.columns.0.z, -sin(angle), accuracy: 0.001)
        XCTAssertEqual(rotation.columns.2.x, sin(angle), accuracy: 0.001)
        XCTAssertEqual(rotation.columns.2.z, cos(angle), accuracy: 0.001)
    }
    
    func testRotationYZeroAngle() {
        let rotation = float4x4.rotationY(0)
        XCTAssertEqual(rotation, .identity)
    }
    
    // MARK: - Rotation Z
    
    func testRotationZ() {
        let angle: Float = .pi / 2
        let rotation = float4x4.rotationZ(angle)
        
        // Z-axis should be unchanged
        XCTAssertEqual(rotation.columns.2.x, 0, accuracy: 0.001)
        XCTAssertEqual(rotation.columns.2.y, 0, accuracy: 0.001)
        XCTAssertEqual(rotation.columns.2.z, 1, accuracy: 0.001)
        
        // X and Y should be rotated
        XCTAssertEqual(rotation.columns.0.x, cos(angle), accuracy: 0.001)
        XCTAssertEqual(rotation.columns.0.y, sin(angle), accuracy: 0.001)
        XCTAssertEqual(rotation.columns.1.x, -sin(angle), accuracy: 0.001)
        XCTAssertEqual(rotation.columns.1.y, cos(angle), accuracy: 0.001)
    }
    
    func testRotationZZeroAngle() {
        let rotation = float4x4.rotationZ(0)
        XCTAssertEqual(rotation, .identity)
    }
    
    // MARK: - Translation
    
    func testTranslation() {
        let translation = float4x4.translation([1, 2, 3])
        
        XCTAssertEqual(translation.columns.3.x, 1, accuracy: 0.001)
        XCTAssertEqual(translation.columns.3.y, 2, accuracy: 0.001)
        XCTAssertEqual(translation.columns.3.z, 3, accuracy: 0.001)
        XCTAssertEqual(translation.columns.3.w, 1, accuracy: 0.001)
        
        // Diagonal should be 1
        XCTAssertEqual(translation.columns.0.x, 1, accuracy: 0.001)
        XCTAssertEqual(translation.columns.1.y, 1, accuracy: 0.001)
        XCTAssertEqual(translation.columns.2.z, 1, accuracy: 0.001)
    }
    
    func testTranslationZero() {
        let translation = float4x4.translation([0, 0, 0])
        XCTAssertEqual(translation, .identity)
    }
    
    // MARK: - Perspective FOV
    
    func testPerspectiveFov() {
        let fov: Float = .pi / 4
        let aspect: Float = 16 / 9
        let nearZ: Float = 0.1
        let farZ: Float = 100.0
        
        let projection = float4x4.perspectiveFov(fov, aspect: aspect, nearZ: nearZ, farZ: farZ)
        
        // Check that projection is not identity
        XCTAssertNotEqual(projection, .identity)
        
        // W row should have -1 for perspective division
        XCTAssertEqual(projection.columns.2.w, -1, accuracy: 0.001)
    }
    
    func testPerspectiveFovIdentityAspect() {
        let fov: Float = .pi / 4
        let aspect: Float = 1.0
        let nearZ: Float = 0.1
        let farZ: Float = 100.0
        
        let projection = float4x4.perspectiveFov(fov, aspect: aspect, nearZ: nearZ, farZ: farZ)
        
        // X and Y scale should be equal for square aspect
        XCTAssertEqual(projection.columns.0.x, projection.columns.1.y, accuracy: 0.001)
    }
    
    // MARK: - Matrix Composition
    
    func testRotationComposition() {
        let angle: Float = .pi / 4
        
        let rotationX = float4x4.rotationX(angle)
        let rotationY = float4x4.rotationY(angle)
        let rotationZ = float4x4.rotationZ(angle)
        
        // Compose rotations
        let composed = rotationX * rotationY * rotationZ
        
        // Apply to a point
        let point = SIMD4<Float>(1, 0, 0, 1)
        let result = composed * point
        
        // Result should be different from original
        XCTAssertNotEqual(result.x, point.x, accuracy: 0.001)
    }
    
    func testTranslationComposition() {
        let t1 = float4x4.translation([1, 2, 3])
        let t2 = float4x4.translation([4, 5, 6])
        
        let composed = t1 * t2
        let point = SIMD4<Float>(0, 0, 0, 1)
        let result = composed * point
        
        XCTAssertEqual(result.x, 5, accuracy: 0.001)
        XCTAssertEqual(result.y, 7, accuracy: 0.001)
        XCTAssertEqual(result.z, 9, accuracy: 0.001)
    }
}

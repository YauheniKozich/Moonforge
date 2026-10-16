//
//  CameraComponentTests.swift
//  MoonforgeTests
//
//  Created on 20.03.26.
//

import XCTest
import simd
@testable import Moonforge

final class CameraComponentTests: XCTestCase {
    
    var camera: CameraComponent!
    
    override func setUp() {
        super.setUp()
        camera = CameraComponent()
    }
    
    override func tearDown() {
        camera = nil
        super.tearDown()
    }
    
    // MARK: - Initial State
    
    func testInitialState() {
        let state = camera.getStateSnapshot()
        
        XCTAssertEqual(state.yaw, 0)
        XCTAssertEqual(state.pitch, 0)
        XCTAssertEqual(state.distance, MetalConfiguration.Geometry.cameraDistance)
        XCTAssertEqual(state.pan, .zero)
    }
    
    // MARK: - Orbit
    
    func testOrbit() {
        camera.orbit(deltaX: 10, deltaY: 5)
        
        let state = camera.getStateSnapshot()
        XCTAssertEqual(state.yaw, 10 * MetalConfiguration.Camera.orbitSensitivity, accuracy: 0.001)
        XCTAssertEqual(state.pitch, -5 * MetalConfiguration.Camera.orbitSensitivity, accuracy: 0.001)
    }
    
    func testOrbitClampsPitch() {
        let maxPitch = MetalConfiguration.Camera.maxPitch
        let largeDelta = (maxPitch * 2) / MetalConfiguration.Camera.orbitSensitivity
        
        camera.orbit(deltaX: 0, deltaY: largeDelta)
        
        let state = camera.getStateSnapshot()
        XCTAssertEqual(state.pitch, -maxPitch, accuracy: 0.001)
    }
    
    func testOrbitClampsNegativePitch() {
        let maxPitch = MetalConfiguration.Camera.maxPitch
        let largeDelta = -(maxPitch * 2) / MetalConfiguration.Camera.orbitSensitivity
        
        camera.orbit(deltaX: 0, deltaY: largeDelta)
        
        let state = camera.getStateSnapshot()
        XCTAssertEqual(state.pitch, maxPitch, accuracy: 0.001)
    }

    func testMinimumHeightBlocksDownwardMovementWhilePermittingUpward() {
        camera.setMinimumHeight(-0.85)

        // Upward movement (swiping up -> negative deltaY -> pitch increases) should be allowed up to maxPitch
        camera.orbit(deltaX: 0, deltaY: -100)
        let upwardPitch = camera.getStateSnapshot().pitch
        XCTAssertGreaterThanOrEqual(upwardPitch, 0.5)

        // Downward movement (swiping down -> positive deltaY -> pitch decreases) must be clamped by minimumHeight
        camera.orbit(deltaX: 0, deltaY: 500)
        let downwardState = camera.getStateSnapshot()
        let eyeY = downwardState.pan.y * cos(downwardState.pitch) + downwardState.distance * sin(downwardState.pitch)
        XCTAssertGreaterThanOrEqual(eyeY, -0.85 - 0.001)
    }
    
    // MARK: - Pan
    
    func testPan() {
        camera.pan(deltaX: 100, deltaY: 50)
        
        let state = camera.getStateSnapshot()
        XCTAssertEqual(state.pan.x, 100 * MetalConfiguration.Camera.panSensitivity, accuracy: 0.001)
        XCTAssertEqual(state.pan.y, 50 * MetalConfiguration.Camera.panSensitivity, accuracy: 0.001)
    }
    
    // MARK: - Zoom
    
    func testPinchInBringsCameraCloser() {
        let initialDistance = camera.getStateSnapshot().distance
        camera.applyPinch(scale: 0.9)
        
        let state = camera.getStateSnapshot()
        XCTAssertEqual(
            state.distance,
            initialDistance * pow(0.9, MetalConfiguration.Camera.pinchSensitivity),
            accuracy: 0.001
        )
    }
    
    func testPinchOutMovesCameraFarther() {
        let initialDistance = camera.getStateSnapshot().distance
        camera.applyPinch(scale: 1.1)
        
        let state = camera.getStateSnapshot()
        XCTAssertEqual(
            state.distance,
            initialDistance * pow(1.1, MetalConfiguration.Camera.pinchSensitivity),
            accuracy: 0.001
        )
    }
    
    func testPinchClampsMinDistance() {
        let minDistance = MetalConfiguration.Camera.minDistance
        camera.applyPinch(scale: 0.0001)
        
        let state = camera.getStateSnapshot()
        XCTAssertEqual(state.distance, minDistance, accuracy: 0.001)
    }
    
    func testPinchClampsMaxDistance() {
        let maxDistance = MetalConfiguration.Camera.maxDistance
        camera.applyPinch(scale: 1000)
        
        let state = camera.getStateSnapshot()
        XCTAssertEqual(state.distance, maxDistance, accuracy: 0.001)
    }
    
    // MARK: - Reset
    
    func testReset() {
        camera.orbit(deltaX: 10, deltaY: 5)
        camera.pan(deltaX: 100, deltaY: 50)
        camera.applyPinch(scale: 0.8)
        
        camera.reset()
        
        let state = camera.getStateSnapshot()
        XCTAssertEqual(state.yaw, 0)
        XCTAssertEqual(state.pitch, 0)
        XCTAssertEqual(state.distance, MetalConfiguration.Geometry.cameraDistance)
        XCTAssertEqual(state.pan, .zero)
    }
    
    // MARK: - View Matrix
    
    func testComputeViewMatrix() {
        camera.orbit(deltaX: 10, deltaY: 5)
        camera.pan(deltaX: 1, deltaY: 2)
        camera.applyPinch(scale: 0.5)
        
        let state = camera.getStateSnapshot()
        let viewMatrix = camera.computeViewMatrix(for: state)
        
        // View matrix should not be identity
        XCTAssertNotEqual(viewMatrix, .identity)
    }
    
    func testComputeViewMatrixWithDefaultState() {
        let state = camera.getStateSnapshot()
        let viewMatrix = camera.computeViewMatrix(for: state)
        
        // With default state, view matrix should only have translation in Z
        let expectedTranslation = float4x4.translation([0, 0, -MetalConfiguration.Geometry.cameraDistance])
        XCTAssertEqual(viewMatrix.columns.3.x, expectedTranslation.columns.3.x, accuracy: 0.001)
        XCTAssertEqual(viewMatrix.columns.3.y, expectedTranslation.columns.3.y, accuracy: 0.001)
        XCTAssertEqual(viewMatrix.columns.3.z, expectedTranslation.columns.3.z, accuracy: 0.001)
    }
    
    // MARK: - Thread Safety
    
    func testConcurrentAccess() {
        let expectation = XCTestExpectation(description: "Concurrent access completes")
        
        guard let camera else {
            XCTFail("camera is nil")
            return
        }
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            camera.orbit(deltaX: 0.1, deltaY: 0.1)
            camera.pan(deltaX: 1, deltaY: 1)
            camera.applyPinch(scale: 0.99)
            _ = camera.getStateSnapshot()
        }
        
        expectation.fulfill()
        wait(for: [expectation], timeout: 5.0)
        
        // Should not crash - thread safety verified by lack of exceptions
        let state = camera.getStateSnapshot()
        XCTAssertNotNil(state)
    }
}

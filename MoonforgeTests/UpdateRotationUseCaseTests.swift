//
//  UpdateRotationUseCaseTests.swift
//  MoonforgeTests
//
//  Created by Yauheni Kozich on 17.03.26.
//

import XCTest
@testable import Moonforge

@MainActor
final class RotationForwardingTests: XCTestCase {
    // MARK: - Execute Tests

    func testExecuteCallsRotateOnRenderer() throws {
        let renderer = try TestSceneRenderer(device: requireTestMetalDevice())
        let viewModel = try makeSceneViewModelForTests(renderer: renderer)
        let expectedX: Float = 0.5
        let expectedY: Float = -0.3
        
        viewModel.rotateObject(deltaX: expectedX, deltaY: expectedY)
        
        XCTAssertEqual(renderer.rotateCallCount, 1)
        XCTAssertEqual(renderer.lastX, expectedX, accuracy: 0.001)
        XCTAssertEqual(renderer.lastY, expectedY, accuracy: 0.001)
    }
    
    func testExecuteWithZeroValues() throws {
        let renderer = try TestSceneRenderer(device: requireTestMetalDevice())
        let viewModel = try makeSceneViewModelForTests(renderer: renderer)
        let zeroX: Float = 0
        let zeroY: Float = 0
        
        viewModel.rotateObject(deltaX: zeroX, deltaY: zeroY)
        
        XCTAssertEqual(renderer.rotateCallCount, 1)
        XCTAssertEqual(renderer.lastX, zeroX, accuracy: 0.001)
        XCTAssertEqual(renderer.lastY, zeroY, accuracy: 0.001)
    }
    
    func testExecuteWithNegativeValues() throws {
        let renderer = try TestSceneRenderer(device: requireTestMetalDevice())
        let viewModel = try makeSceneViewModelForTests(renderer: renderer)
        let negativeX: Float = -1.0
        let negativeY: Float = -2.0
        
        viewModel.rotateObject(deltaX: negativeX, deltaY: negativeY)
        
        XCTAssertEqual(renderer.lastX, negativeX, accuracy: 0.001)
        XCTAssertEqual(renderer.lastY, negativeY, accuracy: 0.001)
    }
    
    func testExecuteMultipleTimes() throws {
        let renderer = try TestSceneRenderer(device: requireTestMetalDevice())
        let viewModel = try makeSceneViewModelForTests(renderer: renderer)
        viewModel.rotateObject(deltaX: 0.1, deltaY: 0.2)
        viewModel.rotateObject(deltaX: 0.3, deltaY: 0.4)
        viewModel.rotateObject(deltaX: 0.5, deltaY: 0.6)
        
        XCTAssertEqual(renderer.rotateCallCount, 3)
        XCTAssertEqual(renderer.lastX, 0.5, accuracy: 0.001)
        XCTAssertEqual(renderer.lastY, 0.6, accuracy: 0.001)
    }
}


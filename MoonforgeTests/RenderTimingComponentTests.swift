//
//  RenderTimingComponentTests.swift
//  MoonforgeTests
//
//  Created on 20.03.26.
//

import XCTest
@testable import Moonforge

final class RenderTimingComponentTests: XCTestCase {
    var timing: RenderTimingComponent!
    
    override func setUp() {
        super.setUp()
        timing = RenderTimingComponent()
    }
    
    override func tearDown() {
        timing = nil
        super.tearDown()
    }
    
    // MARK: - Initial State
    
    func testInitialDeltaIsTargetFrameTime() {
        let deltaTime = timing.update()
        
        XCTAssertEqual(deltaTime, MetalConfiguration.Performance.targetFrameTime, accuracy: 0.001)
    }
    
    // MARK: - Delta Time
    
    func testDeltaTimeUpdates() {
        _ = timing.update() // First call initializes
        
        Thread.sleep(forTimeInterval: 0.016) // ~60 FPS
        
        let deltaTime = timing.update()
        
        XCTAssertGreaterThanOrEqual(deltaTime, 0.015)
        XCTAssertLessThanOrEqual(deltaTime, 0.020)
    }
    
    func testDeltaTimeCapsAtMax() {
        _ = timing.update() // First call initializes
        
        Thread.sleep(forTimeInterval: 0.5) // Long delay
        
        let deltaTime = timing.update()
        
        // Should be capped at 2x target frame time
        let maxDelta = MetalConfiguration.Performance.targetFrameTime * 2
        XCTAssertLessThanOrEqual(deltaTime, maxDelta + 0.001)
    }
    
    // MARK: - FPS
    
    func testFPSUpdates() {
        // Initial FPS should be 0
        XCTAssertEqual(timing.currentFPS, 0)
        
        // Update multiple times over 1 second with realistic frame timing
        let startTime = CACurrentMediaTime()
        while CACurrentMediaTime() - startTime < 1.1 {
            _ = timing.update()
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        // FPS should now be updated
        let fps = timing.currentFPS
        XCTAssertGreaterThan(fps, 0)
        XCTAssertLessThanOrEqual(fps, 300) // Reasonable upper bound
    }
    
    // MARK: - Reset
    
    func testReset() {
        _ = timing.update()
        Thread.sleep(forTimeInterval: 0.1)
        _ = timing.update()
        
        timing.reset()
        
        XCTAssertEqual(timing.deltaTime, 0)
        XCTAssertEqual(timing.currentFPS, 0)
    }
    
    func testResetThenUpdate() {
        _ = timing.update()
        timing.reset()
        
        let deltaTime = timing.update()
        
        // After reset, first update should return target frame time
        XCTAssertEqual(deltaTime, MetalConfiguration.Performance.targetFrameTime, accuracy: 0.001)
    }
    
    // MARK: - Thread Safety
    
    func testConcurrentAccess() {
        let expectation = XCTestExpectation(description: "Concurrent access completes")
        
        guard let timing else {
            XCTFail("timing is nil")
            return
        }
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            _ = timing.update()
            _ = timing.deltaTime
            _ = timing.currentFPS
        }
        
        expectation.fulfill()
        wait(for: [expectation], timeout: 5.0)
        
        // Should not crash - thread safety verified by lack of exceptions
        XCTAssertGreaterThanOrEqual(timing.deltaTime, 0)
    }
}

//
//  RotationStateManagerTests.swift
//  MoonforgeTests
//
//  Created on 20.03.26.
//

import XCTest
import simd
@testable import Moonforge

final class RotationStateManagerTests: XCTestCase {
    var rotationManager: RotationStateManager!

    override func setUp() {
        super.setUp()
        rotationManager = RotationStateManager()
    }

    override func tearDown() {
        rotationManager = nil
        super.tearDown()
    }

    func testInitialStateIsCentered() {
        let snapshot = rotationManager.getSnapshot()

        XCTAssertEqual(snapshot.x, 0, accuracy: 0.001)
        XCTAssertEqual(snapshot.y, 0, accuracy: 0.001)
        XCTAssertEqual(snapshot.z, 0, accuracy: 0.001)
        XCTAssertFalse(rotationManager.isMoving)
    }

    func testApplyInputRotatesObjectAroundXYAxes() {
        rotationManager.applyInput(x: 0.1, y: 0.2)

        let snapshot = rotationManager.getSnapshot()

        XCTAssertEqual(snapshot.x, 0.1, accuracy: 0.001)
        XCTAssertEqual(snapshot.y, 0.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.z, 0, accuracy: 0.001)
        XCTAssertTrue(rotationManager.isMoving)
    }

    func testUpdateDoesNotAddAutoRotationOrInertia() {
        rotationManager.applyInput(x: 0.25, y: -0.5)
        let snapshotBeforeUpdate = rotationManager.getSnapshot()

        rotationManager.update(deltaTime: 0.5)

        let snapshotAfterUpdate = rotationManager.getSnapshot()

        XCTAssertEqual(snapshotAfterUpdate.x, snapshotBeforeUpdate.x, accuracy: 0.001)
        XCTAssertEqual(snapshotAfterUpdate.y, snapshotBeforeUpdate.y, accuracy: 0.001)
        XCTAssertEqual(snapshotAfterUpdate.z, snapshotBeforeUpdate.z, accuracy: 0.001)
    }

    func testResetReturnsObjectToCenteredOrientation() {
        rotationManager.applyInput(x: 0.3, y: 0.4)
        rotationManager.reset()

        let snapshot = rotationManager.getSnapshot()

        XCTAssertEqual(snapshot.x, 0, accuracy: 0.001)
        XCTAssertEqual(snapshot.y, 0, accuracy: 0.001)
        XCTAssertEqual(snapshot.z, 0, accuracy: 0.001)
        XCTAssertFalse(rotationManager.isMoving)
    }

    func testConcurrentAccessRemainsSafe() {
        let expectation = XCTestExpectation(description: "Concurrent access completes")

        guard let rotationManager else {
            XCTFail("rotationManager is nil")
            return
        }
        DispatchQueue.concurrentPerform(iterations: 1000) { iteration in
            rotationManager.applyInput(x: Float(iteration) * 0.0001, y: 0.01)
            rotationManager.update(deltaTime: 0.016)
            _ = rotationManager.getSnapshot()
            _ = rotationManager.isMoving
        }

        expectation.fulfill()
        wait(for: [expectation], timeout: 5.0)

        XCTAssertNotNil(rotationManager.getSnapshot())
    }
}

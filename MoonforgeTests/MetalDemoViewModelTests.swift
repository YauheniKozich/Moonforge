//
//  MetalDemoViewModelTests.swift
//  MoonforgeTests
//
//  Created by Yauheni Kozich on 17.03.26.
//

import XCTest
import MetalKit
@testable import Moonforge

@MainActor
final class SceneViewModelTests: XCTestCase {
    // MARK: - Initial State Tests

    func testInitialState() throws {
        let viewModel = try makeSceneViewModelForTests()
        XCTAssertEqual(viewModel.rotationSensitivity, 0.005, accuracy: 0.0001)
        XCTAssertEqual(viewModel.velocitySensitivity, 0.0001, accuracy: 0.00001)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Sensitivity Update Tests

    func testUpdateRotationSensitivity() throws {
        let viewModel = try makeSceneViewModelForTests()
        viewModel.updateRotationSensitivity(0.01)
        XCTAssertEqual(viewModel.rotationSensitivity, 0.01, accuracy: 0.0001)
    }

    func testUpdateVelocitySensitivity() throws {
        let viewModel = try makeSceneViewModelForTests()
        viewModel.updateVelocitySensitivity(0.001)
        XCTAssertEqual(viewModel.velocitySensitivity, 0.001, accuracy: 0.00001)
    }

    // MARK: - Clamping Tests

    func testRotationSensitivityClamping_upperBound() throws {
        let viewModel = try makeSceneViewModelForTests()
        viewModel.updateRotationSensitivity(1.0)
        XCTAssertEqual(viewModel.rotationSensitivity, 0.1, accuracy: 0.0001)
    }

    func testRotationSensitivityClamping_lowerBound() throws {
        let viewModel = try makeSceneViewModelForTests()
        viewModel.updateRotationSensitivity(0.00000001)
        XCTAssertEqual(viewModel.rotationSensitivity, 0.000001, accuracy: 0.0000001)
    }

    func testVelocitySensitivityClamping_upperBound() throws {
        let viewModel = try makeSceneViewModelForTests()
        viewModel.updateVelocitySensitivity(1.0)
        XCTAssertEqual(viewModel.velocitySensitivity, 0.01, accuracy: 0.0001)
    }

    func testVelocitySensitivityClamping_lowerBound() throws {
        let viewModel = try makeSceneViewModelForTests()
        viewModel.updateVelocitySensitivity(0.000000001)
        XCTAssertEqual(viewModel.velocitySensitivity, 0.0000001, accuracy: 0.00000001)
    }

    // MARK: - Error Handling Tests

    func testSetError() throws {
        let viewModel = try makeSceneViewModelForTests()
        let errorMessage = "Test error message"
        viewModel.setError(errorMessage)
        XCTAssertEqual(viewModel.errorMessage, errorMessage)
    }

    func testClearError() throws {
        let viewModel = try makeSceneViewModelForTests()
        viewModel.setError("Test error")
        viewModel.clearError()
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Missing Metal Device Handling Tests

    func testDIContainerHandlesNilMetalDeviceGracefully() {
        let container = DIContainer(device: nil)
        XCTAssertNil(container.device)
        XCTAssertNil(container.makeRenderer())
        XCTAssertNil(container.makeTextureRepository())
    }

    func testDefaultRendererFactoryHandlesNilDeviceGracefully() {
        let factory = DefaultRendererFactory(
            device: nil,
            logger: TestMetalLogger(),
            configuration: .default
        )
        XCTAssertNil(factory.makeRenderer())
    }
}

@MainActor
func makeSceneViewModelForTests(renderer: TestSceneRenderer? = nil) throws -> SceneViewModel {
    let renderer = try renderer ?? TestSceneRenderer(device: requireTestMetalDevice())
    let logger = TestMetalLogger()
    return SceneViewModel(
        switchGeometryUseCase: DefaultSwitchGeometryUseCase(geometrySwitcher: renderer, logger: logger),
        toggleModelTextureUseCase: DefaultToggleModelTextureUseCase(modelTextureSwitcher: renderer, logger: logger),
        adjustCameraUseCase: DefaultAdjustCameraUseCase(cameraController: renderer, logger: logger),
        sceneService: SceneServiceAdapter(renderer: renderer, logger: logger),
        renderer: renderer,
        logger: logger
    )
}

func requireTestMetalDevice() throws -> MTLDevice {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw XCTSkip("Metal device is not available in this environment")
    }
    return device
}

struct TestMetalLogger: MetalLogger {
    func log(_ message: String, level: MetalLogLevel) {}
}

@MainActor
final class TestSceneRenderer: MetalRenderable, ObjectRotating, GeometrySwitching, ModelTextureSwitching, CameraControlling {
    nonisolated let device: MTLDevice
    weak var delegate: MetalRendererDelegate?
    var availableGeometries = ["cube"]
    var currentGeometryName = "cube"
    var textureEnabled = true
    var rotateCallCount = 0
    var lastX: Float = 0
    var lastY: Float = 0

    init(device: MTLDevice) {
        self.device = device
    }

    func setup(metalView: MTKView) throws {}
    func updateRenderSnapshot(for view: MTKView) {}
    nonisolated func draw(drawable: MTLDrawable, renderPassDescriptor: MTLRenderPassDescriptor) {}
    nonisolated func cleanup() {}
    func rotate(x: Float, y: Float) { rotateObject(deltaX: x, deltaY: y) }
    func rotateObject(deltaX: Float, deltaY: Float) {
        rotateCallCount += 1
        lastX = deltaX
        lastY = deltaY
    }
    func resetObjectRotation() {}
    func switchGeometry(named name: String) { currentGeometryName = name }
    func setModelTextureEnabled(_ enabled: Bool) { textureEnabled = enabled }
    func isModelTextureEnabled() -> Bool { textureEnabled }
    func orbit(deltaX: Float, deltaY: Float) {}
    func pan(deltaX: Float, deltaY: Float) {}
    func applyPinch(scale: Float) {}
    func resetCamera() {}
}

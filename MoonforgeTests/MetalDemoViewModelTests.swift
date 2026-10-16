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

// MARK: - SceneDebugService Tests

@MainActor
final class SceneDebugServiceTests: XCTestCase {
    private var provider: TestDebugInfoProvider!
    private var service: TestSceneService!
    private var sut: SceneDebugService!

    override func setUp() async throws {
        try await super.setUp()
        provider = TestDebugInfoProvider()
        service = TestSceneService()
        sut = SceneDebugService(debugInfoProvider: provider, sceneService: service)
    }

    override func tearDown() async throws {
        sut.stopPolling()
        sut = nil
        service = nil
        provider = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Выполняет детерминированное ожидание stopPollingAndWait с ограничением по времени через XCTest.
    /// В случае зависания polling-задачи XCTest фиксирует таймаут и возвращает управление,
    /// предотвращая бесконечный hang тестового раннера.
    private func stopPollingAndWait(
        _ service: SceneDebugService,
        clock: TestClock? = nil,
        timeout: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let exp = expectation(description: "stopPollingAndWait should complete within timeout")
        var isCompleted = false
        let waitTask = Task { @MainActor in
            await service.stopPollingAndWait()
            isCompleted = true
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: timeout)
        if isCompleted {
            _ = await waitTask.result
        } else {
            waitTask.cancel()
            clock?.cancelAllWaiters()
        }
    }

    func testInitialStateDoesNotStartPolling() {
        XCTAssertFalse(sut.isPolling)
        XCTAssertEqual(provider.queryCount, 0)
        XCTAssertNil(sut.debugInfo)
        XCTAssertTrue(sut.availableGeometries.isEmpty)
        XCTAssertEqual(sut.selectedGeometry, "")
    }

    func testStartPollingUpdatesImmediatelyAndSetsPollingTrue() {
        sut.startPolling()

        XCTAssertTrue(sut.isPolling)
        XCTAssertEqual(provider.queryCount, 1)
        XCTAssertEqual(sut.debugInfo?.sessionId, "test-session")
        XCTAssertEqual(sut.availableGeometries, ["cube", "model"])
        XCTAssertEqual(sut.selectedGeometry, "cube")
        XCTAssertTrue(sut.modelTextureEnabled)
    }

    func testStartPollingIsIdempotent() {
        sut.startPolling()
        XCTAssertTrue(sut.isPolling)
        XCTAssertEqual(provider.queryCount, 1)

        sut.startPolling()
        XCTAssertTrue(sut.isPolling)
        XCTAssertEqual(provider.queryCount, 1)
    }

    func testStopPollingCancelsTaskAndSetsPollingFalse() {
        sut.startPolling()
        XCTAssertTrue(sut.isPolling)

        sut.stopPolling()
        XCTAssertFalse(sut.isPolling)

        sut.stopPolling()
        XCTAssertFalse(sut.isPolling)
    }

    func testRepeatedStartStopCycles() {
        for _ in 0..<5 {
            sut.startPolling()
            XCTAssertTrue(sut.isPolling)
            sut.stopPolling()
            XCTAssertFalse(sut.isPolling)
        }
    }

    func testSceneViewModelDebugPollingLifecycle() throws {
        let viewModel = try makeSceneViewModelForTests()
        XCTAssertFalse(viewModel.isDebugPolling)

        viewModel.startDebugPolling()
        XCTAssertTrue(viewModel.isDebugPolling)

        viewModel.stopDebugPolling()
        XCTAssertFalse(viewModel.isDebugPolling)
    }

    // MARK: - Deterministic Async Polling Tests

    func testSinglePollingTickPerformsExactlyOneUpdate() async throws {
        let clock = TestClock()
        let customSut = SceneDebugService(
            debugInfoProvider: provider,
            sceneService: service,
            clock: clock
        )
        defer { customSut.stopPolling() }

        customSut.startPolling()
        XCTAssertEqual(provider.queryCount, 1) // Немедленное обновление при старте

        // Явное ожидание регистрации sleep
        let waiterId = try await clock.waitForSleepRegistration()
        XCTAssertEqual(waiterId, 1)

        // Продвигаем время ровно на один интервал
        let resumed = clock.advance(by: .milliseconds(500))
        XCTAssertEqual(resumed, [1])

        // Явное детерминированное ожидание выполнения тика обновления
        try await provider.waitForQueryCount(2)
        XCTAssertEqual(provider.queryCount, 2)

        // Задача перешла к следующему сну (waiter ID 2)
        let nextWaiterId = try await clock.waitForSleepRegistration(after: 2)
        XCTAssertEqual(nextWaiterId, 2)
        XCTAssertEqual(provider.queryCount, 2)

        await stopPollingAndWait(customSut, clock: clock)
    }

    func testAfterStopPollingCancelledLoopDoesNotQueryProvider() async throws {
        let clock = TestClock()
        let customSut = SceneDebugService(
            debugInfoProvider: provider,
            sceneService: service,
            clock: clock
        )
        defer { customSut.stopPolling() }

        customSut.startPolling()
        let waiterId = try await clock.waitForSleepRegistration()
        XCTAssertEqual(waiterId, 1)
        XCTAssertEqual(provider.queryCount, 1)

        // Гарантированно останавливаем и дожидаемся полного завершения фонового цикла
        await stopPollingAndWait(customSut, clock: clock)
        XCTAssertFalse(customSut.isPolling)
        XCTAssertFalse(clock.isWaiterActive(id: waiterId))

        // Продвигаем время на 10 секунд вперед
        let resumed = clock.advance(by: .seconds(10))
        XCTAssertTrue(resumed.isEmpty) // Ни один waiter не был пробужден

        // Старый цикл полностью завершен и больше не обращается к provider
        XCTAssertEqual(provider.queryCount, 1)
        XCTAssertEqual(clock.activeWaitersCount, 0)
    }

    func testAfterStopAndRestartWakingOldTaskDoesNotUpdateData() async throws {
        let clock = TestClock()
        let customSut = SceneDebugService(
            debugInfoProvider: provider,
            sceneService: service,
            clock: clock
        )
        defer { customSut.stopPolling() }

        // 1. Запуск первой задачи
        customSut.startPolling()
        let waiter1 = try await clock.waitForSleepRegistration()
        XCTAssertEqual(waiter1, 1)
        XCTAssertEqual(provider.queryCount, 1)

        // 2. Остановка первой задачи и гарантированное ожидание её завершения
        await stopPollingAndWait(customSut, clock: clock)
        XCTAssertFalse(customSut.isPolling)
        XCTAssertFalse(clock.isWaiterActive(id: 1))

        // 3. Немедленный старт новой задачи
        customSut.startPolling()
        XCTAssertTrue(customSut.isPolling)
        XCTAssertEqual(provider.queryCount, 2) // Немедленное обновление новой задачи

        // 4. Ожидание регистрации сна второй задачи (waiter ID 2)
        let waiter2 = try await clock.waitForSleepRegistration(after: 2)
        XCTAssertEqual(waiter2, 2)
        XCTAssertTrue(clock.isWaiterActive(id: 2))

        // 5. Продвигаем время на один интервал
        let resumed = clock.advance(by: .milliseconds(500))
        // Пробуждена ровно вторая задача
        XCTAssertEqual(resumed, [2])

        // 6. Ожидание фактического выполнения тика второй задачи
        try await provider.waitForQueryCount(3)
        XCTAssertEqual(provider.queryCount, 3)

        // 7. Вторая задача заснула на 3-й waiter
        let waiter3 = try await clock.waitForSleepRegistration(after: 3)
        XCTAssertEqual(waiter3, 3)
        XCTAssertEqual(provider.queryCount, 3)

        await stopPollingAndWait(customSut, clock: clock)
    }

    func testDuplicateStartPollingDoesNotCreateSecondActiveLoop() async throws {
        let clock = TestClock()
        let customSut = SceneDebugService(
            debugInfoProvider: provider,
            sceneService: service,
            clock: clock
        )
        defer { customSut.stopPolling() }

        customSut.startPolling()
        customSut.startPolling() // Повторный вызов не должен создавать вторую задачу
        XCTAssertEqual(provider.queryCount, 1)

        let waiterId = try await clock.waitForSleepRegistration()
        XCTAssertEqual(waiterId, 1)
        XCTAssertEqual(clock.activeWaitersCount, 1)

        // Продвигаем время на один интервал
        let resumed = clock.advance(by: .milliseconds(500))
        XCTAssertEqual(resumed, [1])

        try await provider.waitForQueryCount(2)
        XCTAssertEqual(provider.queryCount, 2)

        let nextWaiter = try await clock.waitForSleepRegistration(after: 2)
        XCTAssertEqual(nextWaiter, 2)
        XCTAssertEqual(clock.activeWaitersCount, 1)

        await stopPollingAndWait(customSut, clock: clock)
    }

    func testCancellationAfterSuccessfulSleepExitsViaPostAwaitGuard() async throws {
        let clock = TestClock()
        let customSut = SceneDebugService(
            debugInfoProvider: provider,
            sceneService: service,
            clock: clock
        )
        defer { customSut.stopPolling() }

        // 1. Старт polling
        customSut.startPolling()
        XCTAssertEqual(provider.queryCount, 1)

        // 2. Ожидание регистрации сна
        let waiterId = try await clock.waitForSleepRegistration()
        XCTAssertEqual(waiterId, 1)

        // 3. clock.advance завершает sleep УСПЕШНО без ошибки CancellationError
        let resumed = clock.advance(by: .milliseconds(500))
        XCTAssertEqual(resumed, [1])

        // 4. Отменяем задачу и гарантированно дожидаемся её завершения с таймаутом.
        // sleep уже успешно завершен advance'ом, но Task.isCancelled выставлен в true до продолжения цикла.
        customSut.stopPolling()
        await stopPollingAndWait(customSut, clock: clock)
        XCTAssertFalse(customSut.isPolling)

        // 5. Продвигаем время на 10 секунд вперёд на случай несанкционированного продолжения
        let laterResumed = clock.advance(by: .seconds(10))
        XCTAssertTrue(laterResumed.isEmpty)

        // 6. Проверяем, что provider НЕ вызывался повторно:
        // пост-await guard (guard let self, !Task.isCancelled else { break })
        // обязан прервать цикл БЕЗ вызова updateDebugInfo()
        XCTAssertEqual(provider.queryCount, 1)
        XCTAssertEqual(clock.activeWaitersCount, 0)
    }

    func testStopPollingFollowedByStartPollingDoesNotCancelNewTask() async throws {
        let clock = TestClock()
        let customSut = SceneDebugService(
            debugInfoProvider: provider,
            sceneService: service,
            clock: clock
        )
        defer { customSut.stopPolling() }

        // 1. Старт задачи 1
        customSut.startPolling()
        let waiter1 = try await clock.waitForSleepRegistration()
        XCTAssertEqual(waiter1, 1)

        // 2. Вызываем stopPollingAndWait для старой задачи, затем стартуем новую задачу
        await stopPollingAndWait(customSut, clock: clock)
        XCTAssertFalse(customSut.isPolling)

        customSut.startPolling()
        XCTAssertTrue(customSut.isPolling)
        XCTAssertEqual(provider.queryCount, 2)

        // 3. Ждём регистрацию сна второй задачи (waiter 2)
        let waiter2 = try await clock.waitForSleepRegistration(after: 2)
        XCTAssertEqual(waiter2, 2)
        XCTAssertTrue(clock.isWaiterActive(id: 2))
        XCTAssertFalse(clock.isWaiterActive(id: 1))

        await stopPollingAndWait(customSut, clock: clock)
        XCTAssertFalse(customSut.isPolling)
    }

    func testInterleavedStopPollingAndWaitPreservesNewTaskIdentity() async throws {
        let clock = TestClock()
        let customSut = SceneDebugService(
            debugInfoProvider: provider,
            sceneService: service,
            clock: clock
        )
        defer { customSut.stopPolling() }

        // 1. Старт задачи 1
        customSut.startPolling()
        let waiter1 = try await clock.waitForSleepRegistration()
        XCTAssertEqual(waiter1, 1)
        XCTAssertEqual(provider.queryCount, 1)

        // 2. Включаем задержку отмены в TestClock, чтобы задача 1 оставалась на паузе в sleep
        clock.setDelayCancellation(true)

        // 3. Запускаем stopPollingAndWait для задачи 1 в отдельном таске.
        // Он вызывает stopPolling(), отменяет задачу 1 и приостанавливается на await task1.result.
        let joinOldTask = Task { @MainActor in
            await customSut.stopPollingAndWait()
        }

        // Даём joinOldTask запуститься на MainActor и войти в stopPollingAndWait
        await Task.yield()

        // 4. Пока старый stopPollingAndWait приостановлен в ожидании завершения задачи 1,
        // запускаем НОВУЮ задачу 2
        customSut.startPolling()
        XCTAssertTrue(customSut.isPolling)
        XCTAssertEqual(provider.queryCount, 2)

        // 5. Ожидаем регистрации сна новой задачи (waiter ID 2)
        let waiter2 = try await clock.waitForSleepRegistration(after: 2)
        XCTAssertEqual(waiter2, 2)
        XCTAssertTrue(clock.isWaiterActive(id: 2))

        // 6. Отключаем задержку отмены и возобновляем отложенную отмену задачи 1.
        // Задача 1 завершается с CancellationError.
        clock.setDelayCancellation(false)
        clock.resumePendingCancellations()

        // 7. Старый stopPollingAndWait просыпается, видит что lastRunningTask != task1 (уже task 2),
        // и НЕ затирает lastRunningTask в nil!
        _ = await joinOldTask.result

        // 8. Проверяем, что задача 2 НЕ была отменена или затёрта:
        XCTAssertTrue(customSut.isPolling)
        XCTAssertTrue(clock.isWaiterActive(id: 2))

        // Продвигаем время — задача 2 продолжает нормальную работу и обновляет debug info
        let resumed = clock.advance(by: .milliseconds(500))
        XCTAssertEqual(resumed, [2])
        try await provider.waitForQueryCount(3)
        XCTAssertEqual(provider.queryCount, 3)

        // 9. Корректно завершаем задачу 2
        await stopPollingAndWait(customSut, clock: clock)
        XCTAssertFalse(customSut.isPolling)
    }

    // MARK: - TestClock Concurrency & Cancellation Tests

    func testTestClockCancellationBeforeRegistration() async throws {
        let clock = TestClock()
        let task = Task {
            try await clock.sleep(until: clock.now.advanced(by: .seconds(1)))
        }
        task.cancel()

        do {
            try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Корректно
        }
        XCTAssertEqual(clock.activeWaitersCount, 0)
    }

    func testTestClockCancellationAfterRegistration() async throws {
        let clock = TestClock()
        let task = Task {
            try await clock.sleep(until: clock.now.advanced(by: .seconds(1)))
        }

        let waiterId = try await clock.waitForSleepRegistration()
        XCTAssertEqual(waiterId, 1)
        XCTAssertTrue(clock.isWaiterActive(id: 1))

        task.cancel()

        do {
            try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Корректно
        }
        XCTAssertFalse(clock.isWaiterActive(id: 1))
        XCTAssertEqual(clock.activeWaitersCount, 0)
    }

    func testTestClockConcurrentCancellationRaceAndNoDoubleResume() async throws {
        let clock = TestClock()

        // 50 итераций реальной конкурентной гонки между advance и cancel
        for _ in 0..<50 {
            let task = Task {
                try await clock.sleep(until: clock.now.advanced(by: .milliseconds(20)))
            }

            _ = try await clock.waitForSleepRegistration(after: 1)

            // Параллельно продвигаем время и отменяем задачу
            let advanceTask = Task {
                clock.advance(by: .milliseconds(20))
            }
            let cancelTask = Task {
                task.cancel()
            }

            _ = await advanceTask.result
            _ = await cancelTask.result

            do {
                try await task.value
                // Задача успела проснуться до отмены
            } catch is CancellationError {
                // Задача была отменена
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(clock.activeWaitersCount, 0)
    }

    func testWaitForSleepRegistrationTimesOutWithoutHanging() async throws {
        let clock = TestClock()
        let start = ContinuousClock.now

        do {
            _ = try await clock.waitForSleepRegistration(after: 1, timeout: .milliseconds(50))
            XCTFail("Expected TimeoutError")
        } catch is TimeoutError {
            // Корректно: timeout сработал детерминированно, child task отменен без зависания
            let elapsed = ContinuousClock.now - start
            XCTAssertLessThan(elapsed, .seconds(1))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Test Utilities

import os

struct TimeoutError: Error, CustomStringConvertible, Sendable {
    let message: String
    var description: String { message }
}

func withTimeout<T: Sendable>(
    _ duration: Duration,
    message: String = "Operation timed out",
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError(message: "\(message) (after \(duration))")
        }

        group.addTask {
            try await operation()
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// MARK: - TestClock Implementation

final class TestClock: Clock, Sendable {
    typealias Instant = ContinuousClock.Instant
    typealias Duration = Swift.Duration

    struct Waiter: Sendable {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    enum SlotState: Sendable {
        case pendingRegistration(deadline: Instant)
        case active(Waiter)
        case cancelled
    }

    struct RegistrationListener: Sendable {
        let id: Int
        let minId: Int
        let continuation: CheckedContinuation<Int, any Error>
    }

    struct State: Sendable {
        var now: Instant = .now
        var nextWaiterId: Int = 1
        var slots: [Int: SlotState] = [:]
        var nextListenerId: Int = 1
        var listeners: [Int: RegistrationListener] = [:]
        var delayCancellation: Bool = false
        var pendingCancellations: [CheckedContinuation<Void, any Error>] = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var now: Instant {
        lock.withLock { $0.now }
    }

    var minimumResolution: Duration {
        .nanoseconds(1)
    }

    var activeWaitersCount: Int {
        lock.withLock { s in
            s.slots.values.filter {
                if case .active = $0 { return true }
                return false
            }.count
        }
    }

    func isWaiterActive(id: Int) -> Bool {
        lock.withLock { s in
            if case .active = s.slots[id] { return true }
            return false
        }
    }

    private enum RegistrationOutcome {
        case resumeSuccess
        case resumeCancelled
        case registered([CheckedContinuation<Int, any Error>])
    }

    private func transitionSlotToActive(
        waiterId: Int,
        continuation: CheckedContinuation<Void, any Error>
    ) -> RegistrationOutcome {
        lock.withLock { s in
            guard let slot = s.slots[waiterId] else {
                return .resumeCancelled
            }

            switch slot {
            case .cancelled:
                s.slots.removeValue(forKey: waiterId)
                return .resumeCancelled

            case .pendingRegistration(let deadline):
                if Task.isCancelled || s.now >= deadline {
                    s.slots.removeValue(forKey: waiterId)
                    return Task.isCancelled ? .resumeCancelled : .resumeSuccess
                }

                let waiter = Waiter(id: waiterId, deadline: deadline, continuation: continuation)
                s.slots[waiterId] = .active(waiter)

                var remaining: [Int: RegistrationListener] = [:]
                var toNotify: [CheckedContinuation<Int, any Error>] = []
                for (lid, item) in s.listeners {
                    if waiterId >= item.minId {
                        toNotify.append(item.continuation)
                    } else {
                        remaining[lid] = item
                    }
                }
                s.listeners = remaining
                return .registered(toNotify)

            case .active:
                return .registered([])
            }
        }
    }

    private func cancelPendingOrActiveSlot(waiterId: Int) -> CheckedContinuation<Void, any Error>? {
        lock.withLock { s in
            guard let slot = s.slots[waiterId] else { return nil }
            switch slot {
            case .pendingRegistration:
                s.slots[waiterId] = .cancelled
                return nil

            case .active(let waiter):
                s.slots.removeValue(forKey: waiterId)
                if s.delayCancellation {
                    s.pendingCancellations.append(waiter.continuation)
                    return nil
                }
                return waiter.continuation

            case .cancelled:
                return nil
            }
        }
    }

    deinit {
        cancelAllWaiters()
    }

    func setDelayCancellation(_ delay: Bool) {
        lock.withLock { $0.delayCancellation = delay }
    }

    func resumePendingCancellations() {
        let continuations = lock.withLock { s -> [CheckedContinuation<Void, any Error>] in
            let conts = s.pendingCancellations
            s.pendingCancellations.removeAll()
            return conts
        }
        for cont in continuations {
            cont.resume(throwing: CancellationError())
        }
    }

    func cancelAllWaiters() {
        let continuations = lock.withLock { s -> [CheckedContinuation<Void, any Error>] in
            var toCancel = s.pendingCancellations
            s.pendingCancellations.removeAll()
            for (id, slot) in s.slots {
                if case .active(let waiter) = slot {
                    toCancel.append(waiter.continuation)
                }
                s.slots[id] = .cancelled
            }
            return toCancel
        }
        for cont in continuations {
            cont.resume(throwing: CancellationError())
        }
    }

    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        try Task.checkCancellation()

        let waiterId = lock.withLock { s -> Int in
            let id = s.nextWaiterId
            s.nextWaiterId += 1
            s.slots[id] = .pendingRegistration(deadline: deadline)
            return id
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                switch transitionSlotToActive(waiterId: waiterId, continuation: continuation) {
                case .resumeSuccess:
                    continuation.resume()

                case .resumeCancelled:
                    continuation.resume(throwing: CancellationError())

                case .registered(let listeners):
                    for listener in listeners {
                        listener.resume(returning: waiterId)
                    }
                }
            }
        } onCancel: {
            cancelPendingOrActiveSlot(waiterId: waiterId)?.resume(throwing: CancellationError())
        }
    }

    @discardableResult
    func advance(by duration: Duration) -> [Int] {
        let (resumedWaiters, resumedIds) = lock.withLock { s -> ([Waiter], [Int]) in
            s.now = s.now.advanced(by: duration)
            var expired: [Waiter] = []
            var expiredIds: [Int] = []
            for (id, slot) in s.slots {
                if case .active(let waiter) = slot, waiter.deadline <= s.now {
                    expired.append(waiter)
                    expiredIds.append(id)
                    s.slots.removeValue(forKey: id)
                }
            }
            let sorted = zip(expired, expiredIds).sorted { $0.1 < $1.1 }
            return (sorted.map(\.0), sorted.map(\.1))
        }

        for waiter in resumedWaiters {
            waiter.continuation.resume()
        }
        return resumedIds
    }

    func waitForSleepRegistration(after minId: Int = 1, timeout: Duration = .seconds(2)) async throws -> Int {
        try await withTimeout(timeout, message: "Timed out waiting for sleep registration >= \(minId)") {
            try Task.checkCancellation()

            let (immediateId, listenerId) = self.lock.withLock { s -> (Int?, Int) in
                for (id, slot) in s.slots {
                    if id >= minId, case .active = slot {
                        return (id, 0)
                    }
                }
                let lid = s.nextListenerId
                s.nextListenerId += 1
                return (nil, lid)
            }

            if let immediateId {
                return immediateId
            }

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, any Error>) in
                    let immediateResult: Result<Int, any Error>? = self.lock.withLock { s in
                        if Task.isCancelled {
                            return .failure(CancellationError())
                        }
                        for (id, slot) in s.slots {
                            if id >= minId, case .active = slot {
                                return .success(id)
                            }
                        }
                        s.listeners[listenerId] = RegistrationListener(id: listenerId, minId: minId, continuation: continuation)
                        return nil
                    }

                    if let immediateResult {
                        continuation.resume(with: immediateResult)
                    }
                }
            } onCancel: {
                let contToResume = self.lock.withLock { s in
                    s.listeners.removeValue(forKey: listenerId)?.continuation
                }
                contToResume?.resume(throwing: CancellationError())
            }
        }
    }
}

// MARK: - TestDebugInfoProvider Implementation

@MainActor
private final class TestDebugInfoProvider: RenderDebugInfoProvider {
    private(set) var queryCount = 0
    private var queryContinuations: [(target: Int, continuation: CheckedContinuation<Void, any Error>)] = []

    var sampleInfo = RenderDebugInfo(
        sessionId: "test-session",
        geometryName: "cube",
        pipelineCacheCount: 1,
        snapshotReady: true,
        textureReady: true,
        modelStatus: .ok,
        modelTextureEnabled: true,
        cameraDistance: 2.5,
        submeshCount: 1,
        texturedSubmeshCount: 1
    )

    var debugInfo: RenderDebugInfo {
        queryCount += 1
        let currentCount = queryCount
        var remaining: [(target: Int, continuation: CheckedContinuation<Void, any Error>)] = []
        for waiter in queryContinuations {
            if currentCount >= waiter.target {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        queryContinuations = remaining
        return sampleInfo
    }

    func waitForQueryCount(_ target: Int, timeout: Duration = .seconds(2)) async throws {
        if queryCount >= target { return }

        try await withTimeout(timeout, message: "Timed out waiting for queryCount >= \(target)") {
            try await self.waitUntilQueryCount(target)
        }
    }

    private func waitUntilQueryCount(_ target: Int) async throws {
        if queryCount >= target { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if self.queryCount >= target {
                    continuation.resume()
                } else {
                    self.queryContinuations.append((target: target, continuation: continuation))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaiters(for: target)
            }
        }
    }

    private func cancelWaiters(for target: Int) {
        var remaining: [(target: Int, continuation: CheckedContinuation<Void, any Error>)] = []
        for waiter in queryContinuations {
            if waiter.target == target {
                waiter.continuation.resume(throwing: CancellationError())
            } else {
                remaining.append(waiter)
            }
        }
        queryContinuations = remaining
    }
}

@MainActor
private final class TestSceneService: SceneServiceProtocol {
    var availableGeometries = ["cube", "model"]
    var currentGeometry = "cube"
    var isTextureEnabled = true

    func switchGeometry(to name: String) async throws {
        currentGeometry = name
    }

    func toggleModelTexture() async {
        isTextureEnabled.toggle()
    }

    func adjustCamera(delta: CameraDelta) async {}

    func getAvailableGeometries() -> [String] {
        availableGeometries
    }

    func getCurrentGeometry() -> String {
        currentGeometry
    }

    func isModelTextureEnabled() -> Bool {
        isTextureEnabled
    }
}

//
//  BaseRenderer.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//  Refactored on 20.03.26.
//

@preconcurrency import Metal
import MetalKit
import os

// MARK: - Base Renderer

/// Base renderer with common Metal infrastructure.
///
/// Thread safety model:
/// - @MainActor: setup, rotate, camera controls, geometry switching, state mutations
/// - nonisolated: draw (Metal thread), cleanup (any thread), updateDrawableSize
/// - snapshotLock: protects snapshot between Main thread (writer) and render thread (reader)
///
/// Architecture:
/// - Delegates rendering logic to components: CameraComponent, RenderTimingComponent, SnapshotBuilder
/// - Uses double-buffering: Main thread mutates state, render thread reads immutable snapshots
@MainActor
class BaseRenderer: MetalRenderer, MetalRenderable, MetalViewRendering {

    weak var delegate: MetalRendererDelegate?

    // MARK: - Metal Resources

    nonisolated let device: MTLDevice
    nonisolated let commandQueue: MTLCommandQueue
    private nonisolated let transparentDepthStencil: MTLDepthStencilState?

    // MARK: - Components

    private let pipelineManager: PipelineManager
    private let textureRepository: TextureRepository
    private nonisolated let bloomLock = OSAllocatedUnfairLock<BloomPostProcessor?>(initialState: nil)
    private let cameraComponent: CameraComponent
    private let rotationStateManager: RotationStateManager
    private nonisolated let timingComponent: RenderTimingComponent
    private let logger: MetalLogger
    private let configuration: MetalConfiguration

    // MARK: - State (@MainActor — compiler protects without locks)

    private var shaderLibrary: MTLLibrary?
    private weak var metalView: MTKView?
    private var colorPixelFormat: MTLPixelFormat?
    private var depthPixelFormat: MTLPixelFormat?
    private let geometryRegistry = GeometryRegistry()
    private var currentGeometryKey: String?
    private var modelLoadStatus: ModelLoadStatus = .notApplicable
    private var modelTextureEnabled: Bool = true
    private var renderedZoom: (logDistance: Float, time: CFTimeInterval)?
    private var isCleaned = false
    // A queued cleanup belongs only to the setup generation that requested it.
    private nonisolated let lifecycleGeneration = OSAllocatedUnfairLock<UInt64>(initialState: 0)
    private let sessionId: String = UUID().uuidString

    // MARK: - FPS Throttle

    private var lastFPSUpdateTime: CFTimeInterval = 0
    private let fpsUpdateInterval: CFTimeInterval = 1.0

    // MARK: - Sampler

    private var samplerState: MTLSamplerState?

    // MARK: - Texture Loading

    private var geometryLoadTask: Task<Void, Never>?
    private var geometryRequestID: UInt64 = 0

    private var textureLoadTask: Task<Void, Never>?

    // MARK: - Render State (@MainActor only)

    private var renderState = RenderState()

    private struct RenderState {
        var currentGeometry: GeometrySource?
        var currentPipeline: MTLRenderPipelineState?
        var currentDepthStencil: MTLDepthStencilState?
        var didLogResourcesNotReady: Bool = false
    }

    // MARK: - Drawable Size (shared between MainActor and MTKView callbacks)

    private let drawableSizeLock = OSAllocatedUnfairLock<CGSize>(initialState: .zero)

    // MARK: - Snapshot Lock (only lock — bridge between MainActor and render thread)

    private let snapshotLock = OSAllocatedUnfairLock<RenderSnapshot?>(initialState: nil)

    // MARK: - Init

    init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipelineManager: PipelineManager,
        textureRepository: TextureRepository,
        logger: MetalLogger,
        configuration: MetalConfiguration
    ) {
        self.device = device
        self.commandQueue = commandQueue
        let transparentDepth = MTLDepthStencilDescriptor()
        transparentDepth.depthCompareFunction = .less
        transparentDepth.isDepthWriteEnabled = false
        self.transparentDepthStencil = device.makeDepthStencilState(descriptor: transparentDepth)
        self.pipelineManager = pipelineManager
        self.textureRepository = textureRepository
        self.logger = logger
        self.configuration = configuration
        self.cameraComponent = CameraComponent(
            minDistance: MetalConfiguration.Camera.minDistance,
            maxDistance: MetalConfiguration.Camera.maxDistance,
            orbitSensitivity: MetalConfiguration.Camera.orbitSensitivity,
            panSensitivity: MetalConfiguration.Camera.panSensitivity,
            pinchSensitivity: MetalConfiguration.Camera.pinchSensitivity,
            maxPitch: MetalConfiguration.Camera.maxPitch
        )
        self.rotationStateManager = RotationStateManager()
        self.timingComponent = RenderTimingComponent(
            targetFrameTime: MetalConfiguration.Performance.targetFrameTime
        )

        logger.log("BaseRenderer initialized [sessionId=\(sessionId)]", level: .info)
    }

    convenience init(device: MTLDevice, logger: MetalLogger) {
        let commandQueue = device.makeCommandQueue()!
        self.init(
            device: device,
            commandQueue: commandQueue,
            pipelineManager: PipelineManager(device: device),
            textureRepository: TextureRepository(device: device, logger: logger),
            logger: logger,
            configuration: .default
        )
    }

    deinit {
        if !isCleaned {
            logger.log("cleanup() not called before deinit [sessionId=\(sessionId)]", level: .warning)
        }
        geometryLoadTask?.cancel()
        textureLoadTask?.cancel()
        snapshotLock.withLock { $0 = nil }
    }

    // MARK: - Setup

    func setup(metalView: MTKView) throws {
        lifecycleGeneration.withLock { $0 &+= 1 }
        isCleaned = false
        geometryLoadTask?.cancel()
        textureLoadTask?.cancel()
        timingComponent.reset()
        lastFPSUpdateTime = 0
        logger.log("Starting setup [sessionId=\(sessionId)]", level: .info)
        self.metalView = metalView
        colorPixelFormat = BloomPostProcessor.scenePixelFormat
        depthPixelFormat = metalView.depthStencilPixelFormat
        updateDrawableSize(metalView.drawableSize)

        do {
            shaderLibrary = try device.makeDefaultLibrary(bundle: .main)
        } catch {
            logger.log("Shader library creation failed: \(error.localizedDescription)", level: .error)
            delegate?.renderer(self, didFailWithError: error)
            throw MetalError.libraryCreationFailed
        }

        guard transparentDepthStencil != nil else { throw MetalError.bufferCreationFailed }
        createSampler()
        let bloom = try BloomPostProcessor(device: device, format: metalView.colorPixelFormat)
        bloomLock.withLock { $0 = bloom }

        textureLoadTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.textureRepository.loadTexture()
        }

        logger.log("BaseRenderer setup complete [sessionId=\(sessionId)]", level: .info)
    }

    // MARK: - Geometry Switching

    private(set) var geometrySwitchError: Error?

    func switchGeometry(to geometry: GeometrySource) {
        geometryRequestID &+= 1
        geometrySwitchError = nil
        do {
            guard let library = shaderLibrary else { throw MetalError.libraryCreationFailed }
            guard let colorPixelFormat, let depthPixelFormat else {
                throw MetalError.pipelineCreationFailed("Pixel formats are not configured")
            }
            guard let vertex = library.makeFunction(name: geometry.shaderNames.vertex),
                  let fragment = library.makeFunction(name: geometry.shaderNames.fragment) else {
                throw MetalError.shaderFunctionNotFound("\(geometry.shaderNames.vertex)/\(geometry.shaderNames.fragment)")
            }
            let pipeline = try pipelineManager.createPipeline(
                vertexFunction: vertex, fragmentFunction: fragment,
                vertexDescriptor: geometry.vertexDescriptor,
                colorPixelFormat: colorPixelFormat, depthStencilPixelFormat: depthPixelFormat,
                sampleCount: metalView?.sampleCount ?? 1
            )
            guard let depth = pipelineManager.depthStencilState(for: depthPixelFormat) else {
                throw MetalError.pipelineCreationFailed("Depth stencil state could not be created")
            }
            // Commit only after every resource is ready; a failed switch keeps the prior scene intact.
            renderState.currentGeometry = geometry
            renderState.currentPipeline = pipeline
            renderState.currentDepthStencil = depth
            renderState.didLogResourcesNotReady = false
            currentGeometryKey = nil
            cameraComponent.reset(distance: geometry.preferredCameraDistance)
            renderedZoom = nil
            modelLoadStatus = (geometry as? ModelIOGeometry)?.loadStatus ?? .notApplicable
            refreshSnapshotIfPossible()
        } catch {
            reportGeometryFailure(error)
        }
    }

    func switchGeometry(named name: String) {
        geometryRequestID &+= 1
        geometrySwitchError = nil
        modelLoadStatus = .loading
        do {
            let geometry = try geometryRegistry.make(name, device: device)
            switchGeometry(to: geometry)
            guard geometrySwitchError == nil else { return }
            currentGeometryKey = name
        } catch {
            reportGeometryFailure(error)
        }
    }

    func registerGeometryAsync(name: String, factory: @escaping GeometryRegistry.AsyncFactory) {
        geometryRegistry.registerAsync(name, factory: factory)
    }

    func startGeometryLoad(named name: String) {
        geometryLoadTask?.cancel()
        geometryLoadTask = Task { [weak self] in
            do { try await self?.switchGeometryAsync(named: name) }
            catch { /* The async switch reports current failures through the delegate. */ }
        }
    }

    func switchGeometryAsync(named name: String) async throws {
        geometryRequestID &+= 1
        let requestID = geometryRequestID
        let generation = lifecycleGeneration.withLock { $0 }
        geometrySwitchError = nil
        modelLoadStatus = .loading
        let geometry: GeometrySource
        do {
            geometry = try await geometryRegistry.makeAsync(name, device: device)
            try Task.checkCancellation()
        } catch {
            guard requestID == geometryRequestID, !isCleaned,
                  lifecycleGeneration.withLock({ $0 }) == generation else { throw CancellationError() }
            if error is CancellationError {
                modelLoadStatus = (renderState.currentGeometry as? ModelIOGeometry)?.loadStatus ?? .notApplicable
            } else {
                reportGeometryFailure(error)
            }
            throw error
        }
        guard requestID == geometryRequestID, !isCleaned,
              lifecycleGeneration.withLock({ $0 }) == generation else { throw CancellationError() }
        switchGeometry(to: geometry)
        if let error = geometrySwitchError { throw error }
        currentGeometryKey = name
    }

    private func reportGeometryFailure(_ error: Error) {
        geometrySwitchError = error
        modelLoadStatus = ModelLoadStatus.from(error: error)
        logger.log("Geometry switch failed: \(error)", level: .error)
        delegate?.renderer(self, didFailWithError: error)
    }

    func setMinimumCameraHeight(_ height: Float) {
        cameraComponent.setMinimumHeight(height)
        if metalView != nil { refreshSnapshotIfPossible() }
    }

    func registerGeometry(name: String, factory: @escaping GeometryRegistry.Factory) {
        geometryRegistry.register(name, factory: factory)
    }

    func makeViewDelegate() -> MTKViewDelegate {
        MetalViewDelegate(renderer: self)
    }

    // MARK: - Camera Controls

    func orbit(deltaX: Float, deltaY: Float) {
        cameraComponent.orbit(deltaX: deltaX, deltaY: deltaY)
        refreshSnapshotIfPossible()
    }

    func pan(deltaX: Float, deltaY: Float) {
        cameraComponent.pan(deltaX: deltaX, deltaY: deltaY)
        refreshSnapshotIfPossible()
    }

    func applyPinch(scale: Float) {
        cameraComponent.applyPinch(scale: scale)
        refreshSnapshotIfPossible()
    }

    func resetCamera() {
        cameraComponent.reset(distance: renderState.currentGeometry?.preferredCameraDistance)
        renderedZoom = nil
        refreshSnapshotIfPossible()
    }

    // MARK: - Draw

    nonisolated func draw(drawable: MTLDrawable, renderPassDescriptor: MTLRenderPassDescriptor) {
        guard let snapshot = snapshotLock.withLock({ $0 }) else { return }

        // Retain this frame's processor even if screen teardown clears the cache.
        let bloomContext = bloomLock.withLock { processor -> (BloomPostProcessor, BloomPostProcessor.Frame)? in
            guard let processor, let frame = processor.frame(for: renderPassDescriptor) else { return nil }
            return (processor, frame)
        }
        guard let bloomContext else { return }

        // Fix: clearDepth BEFORE encoder creation
        renderPassDescriptor.depthAttachment?.clearDepth = 1.0

        guard let cmdBuffer = commandQueue.makeCommandBuffer() else { return }
        renderShadows(using: cmdBuffer, snapshot: snapshot)
        let scenePass = bloomContext.0.scenePass(frame: bloomContext.1, original: renderPassDescriptor)
        guard let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: scenePass) else {
            cmdBuffer.commit()
            return
        }

        encoder.label = "RenderEncoder"
        encoder.pushDebugGroup("Draw")
        encodeEnvironmentParameters(to: encoder, viewMatrix: snapshot.uniforms.viewMatrix)
        renderSpecifics(using: encoder, snapshot: snapshot)
        encoder.setRenderPipelineState(snapshot.pipeline)
        encoder.setDepthStencilState(snapshot.depthStencil)
        encoder.setVertexBuffer(snapshot.vertexBuffer, offset: snapshot.vertexBufferOffset, index: BufferIndex.vertices.rawValue)

        if let sampler = snapshot.sampler {
            encoder.setFragmentSamplerState(sampler, index: 0)
        }

        var uniforms = snapshot.uniforms
        encoder.setVertexBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: BufferIndex.uniforms.rawValue
        )

        if !snapshot.submeshes.isEmpty {
            drawSubmeshes(to: encoder, submeshes: snapshot.submeshes, uniforms: uniforms)
        } else {
            drawProceduralGeometry(to: encoder, snapshot: snapshot)
        }

        let sceneTime = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 1024))
        renderOverlays(using: encoder, snapshot: snapshot, time: sceneTime)
        encoder.popDebugGroup()
        encoder.endEncoding()
        bloomContext.0.encode(frame: bloomContext.1, original: renderPassDescriptor, commandBuffer: cmdBuffer)
        cmdBuffer.present(drawable)
        cmdBuffer.commit()
        // Count submitted frames, independently of input-driven snapshot updates.
        _ = timingComponent.update()

        Task { @MainActor [weak self] in
            self?.updateFPS()
        }
    }

    private nonisolated func encodeEnvironmentParameters(
        to encoder: MTLRenderCommandEncoder,
        viewMatrix: simd_float4x4
    ) {
        var noShadowTransform = matrix_identity_float4x4
        encoder.setFragmentBytes(&noShadowTransform, length: MemoryLayout<simd_float4x4>.stride, index: 4)
        var sceneTime = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 1024))
        encoder.setFragmentBytes(&sceneTime, length: MemoryLayout<Float>.stride, index: 5)
        var fog = FogParameters(
            colorDensity: SIMD4<Float>(MetalConfiguration.Fog.color, MetalConfiguration.Fog.density),
            height: SIMD4<Float>(MetalConfiguration.Fog.baseHeight, MetalConfiguration.Fog.heightFalloff,
                                 MetalConfiguration.Fog.skyDistance, 0),
            cameraPosition: simd_inverse(viewMatrix).columns.3
        )
        encoder.setFragmentBytes(&fog, length: MemoryLayout<FogParameters>.stride, index: 6)
        var moon = MoonParameters(
            panoramaMapping: MetalConfiguration.Moon.panoramaMapping,
            direction: SIMD4<Float>(MetalConfiguration.Moon.direction, MetalConfiguration.Moon.angularRadius),
            textureRegion: MetalConfiguration.Moon.textureRegion
        )
        encoder.setFragmentBytes(&moon, length: MemoryLayout<MoonParameters>.stride, index: 7)
    }

    private nonisolated func drawSubmeshes(
        to encoder: MTLRenderCommandEncoder,
        submeshes: [SubmeshSnapshot],
        uniforms: Uniforms
    ) {
        func drawSubmesh(_ submesh: SubmeshSnapshot, alphaPass: UInt32) {
            encoder.setVertexBuffer(submesh.vertexBuffer, offset: submesh.vertexBufferOffset, index: BufferIndex.vertices.rawValue)

            var modelParams = ModelParams(
                useBaseColorTexture: submesh.useBaseColorTexture ? 1 : 0,
                useNormalTexture: submesh.normalTexture != nil ? 1 : 0,
                useRoughnessTexture: submesh.roughnessTexture != nil ? 1 : 0,
                useMetallicTexture: submesh.metallicTexture != nil ? 1 : 0,
                useEmissiveTexture: submesh.emissiveTexture != nil ? 1 : 0,
                alphaPass: alphaPass, padding1: 0, padding2: 0,
                baseColorFactor: submesh.baseColor,
                emissiveFactor: submesh.emissiveColor,
                roughnessFactor: submesh.roughness,
                metallicFactor: submesh.metallic,
                padding3: .zero
            )
            encoder.setFragmentBytes(
                &modelParams,
                length: MemoryLayout<ModelParams>.stride,
                index: BufferIndex.modelParams.rawValue
            )
            encoder.setFragmentTexture(submesh.baseColorTexture, index: 0)
            encoder.setFragmentTexture(submesh.normalTexture, index: 1)
            encoder.setFragmentTexture(submesh.roughnessTexture, index: 2)
            encoder.setFragmentTexture(submesh.metallicTexture, index: 3)
            encoder.setFragmentTexture(submesh.emissiveTexture, index: 4)
            encoder.drawIndexedPrimitives(
                type: submesh.primitiveType,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: submesh.indexBuffer,
                indexBufferOffset: submesh.indexBufferOffset
            )
        }

        for submesh in submeshes {
            drawSubmesh(submesh, alphaPass: 1)
        }
        encoder.setDepthStencilState(transparentDepthStencil)
        let modelView = uniforms.viewMatrix * uniforms.modelMatrix
        let transparentSubmeshes = submeshes.enumerated().sorted { lhs, rhs in
            let left = (modelView * SIMD4<Float>(lhs.element.sortCenter, 1)).z
            let right = (modelView * SIMD4<Float>(rhs.element.sortCenter, 1)).z
            return left == right ? lhs.offset < rhs.offset : left < right
        }
        for entry in transparentSubmeshes {
            drawSubmesh(entry.element, alphaPass: 2)
        }
    }

    private nonisolated func drawProceduralGeometry(
        to encoder: MTLRenderCommandEncoder,
        snapshot: RenderSnapshot
    ) {
        if let texture = snapshot.texture {
            encoder.setFragmentTexture(texture, index: 0)
        }

        var modelParams = ModelParams(
            useBaseColorTexture: snapshot.useTexture ? 1 : 0,
            useNormalTexture: 0, useRoughnessTexture: 0,
            useMetallicTexture: 0, useEmissiveTexture: 0,
            alphaPass: 0, padding1: 0, padding2: 0,
            baseColorFactor: SIMD4<Float>(1, 1, 1, 1),
            emissiveFactor: .zero,
            roughnessFactor: 1.0, metallicFactor: 0.0,
            padding3: .zero
        )
        encoder.setFragmentBytes(
            &modelParams,
            length: MemoryLayout<ModelParams>.stride,
            index: BufferIndex.modelParams.rawValue
        )
        encoder.drawIndexedPrimitives(
            type: snapshot.primitiveType,
            indexCount: snapshot.indexCount,
            indexType: snapshot.indexType,
            indexBuffer: snapshot.indexBuffer,
            indexBufferOffset: snapshot.indexBufferOffset
        )
    }

    // MARK: - Cleanup

    nonisolated func cleanup() {
        let generation = lifecycleGeneration.withLock { $0 }
        Task { @MainActor [weak self] in
            guard let self, !isCleaned,
                  lifecycleGeneration.withLock({ $0 }) == generation else { return }
            isCleaned = true

            logger.log("Renderer cleanup [sessionId=\(sessionId)]", level: .info)

            geometryLoadTask?.cancel()
            geometryLoadTask = nil
            textureLoadTask?.cancel()
            textureLoadTask = nil

            pipelineManager.cleanup()
            textureRepository.cleanup()
            bloomLock.withLock { $0 = nil }

            renderState.currentGeometry = nil
            renderState.currentPipeline = nil
            renderState.currentDepthStencil = nil

            snapshotLock.withLock { $0 = nil }
        }
    }

    // MARK: - Snapshot

    func updateRenderSnapshot(for view: MTKView) {
        buildSnapshot(for: view)
    }

    nonisolated func updateDrawableSize(_ size: CGSize) {
        drawableSizeLock.withLock { $0 = size }
    }

    private func buildSnapshot(for view: MTKView) {
        guard
            let geometry = renderState.currentGeometry,
            let pipeline = renderState.currentPipeline,
            let depthStencil = renderState.currentDepthStencil
        else {
            if !renderState.didLogResourcesNotReady {
                logger.log("Render snapshot skipped — resources not ready", level: .warning)
                renderState.didLogResourcesNotReady = true
            }
            return
        }

        let snapshot = SnapshotBuilder.build(
            geometry: geometry,
            pipeline: pipeline,
            depthStencil: depthStencil,
            rotation: rotationStateManager.getSnapshot(),
            cameraState: smoothedCameraState(at: CACurrentMediaTime()),
            drawableSize: drawableSizeLock.withLock { $0 },
            sampler: samplerState,
            modelTextureEnabled: modelTextureEnabled,
            texture: textureRepository.texture
        )

        snapshotLock.withLock { $0 = snapshot }
    }

    private func smoothedCameraState(at time: CFTimeInterval) -> CameraState {
        var camera = cameraComponent.getStateSnapshot()
        guard camera.distance.isFinite, camera.distance > 0 else { return camera }
        let target = log(camera.distance)
        if let previous = renderedZoom {
            // Exponential easing in log space keeps proportional zoom speed
            // consistent at every distance and independent of the frame rate.
            let elapsed = max(0, time - previous.time)
            let weight = Float(1 - exp(-elapsed / 0.08))
            let distance = previous.logDistance + (target - previous.logDistance) * weight
            let settled = abs(target - distance) < 0.0001 ? target : distance
            renderedZoom = (settled, time)
            camera.distance = exp(settled)
        } else {
            renderedZoom = (target, time)
        }
        return camera
    }

    // MARK: - Subclass hooks

    nonisolated func renderSpecifics(using encoder: MTLRenderCommandEncoder, snapshot: RenderSnapshot) {}
    nonisolated func renderShadows(using commandBuffer: MTLCommandBuffer, snapshot: RenderSnapshot) {}
    nonisolated func renderOverlays(using encoder: MTLRenderCommandEncoder, snapshot: RenderSnapshot, time: Float) {}

    func logMessage(_ message: String, level: MetalLogLevel) {
        logger.log(message, level: level)
    }

    func createSampler() {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.mipFilter = .linear
        desc.sAddressMode = .repeat
        desc.tAddressMode = .repeat
        desc.maxAnisotropy = 16
        samplerState = device.makeSamplerState(descriptor: desc)
    }

    // MARK: - Private

    private func updateFPS() {
        let fps = timingComponent.currentFPS
        guard fps > 0 else { return }

        let currentTime = CACurrentMediaTime()
        guard currentTime - lastFPSUpdateTime >= fpsUpdateInterval else { return }
        lastFPSUpdateTime = currentTime

        // Already on @MainActor — direct call without Task
        delegate?.renderer(self, didUpdateFPS: fps)
    }

    private func refreshSnapshotIfPossible() {
        guard let metalView else {
            logger.log("Cannot refresh snapshot — metalView is nil", level: .warning)
            return
        }
        updateRenderSnapshot(for: metalView)
    }

    func resetRotation() {
        cameraComponent.reset(distance: renderState.currentGeometry?.preferredCameraDistance)
        renderedZoom = nil
    }

    @available(*, deprecated, renamed: "rotateObject(deltaX:deltaY:)")
    func rotate(x: Float, y: Float) {
        rotateObject(deltaX: x, deltaY: y)
    }
}

// MARK: - Render Debug Info Provider

extension BaseRenderer: RenderDebugInfoProvider {
    var debugInfo: RenderDebugInfo {
        let snapshotReady = snapshotLock.withLock { $0 != nil }
        let textureReady = textureRepository.texture != nil
        let submeshCount = renderState.currentGeometry?.submeshes.count ?? 0
        let texturedSubmeshCount = renderState.currentGeometry?.submeshes
            .filter { $0.baseColorTexture != nil }.count ?? 0

        return RenderDebugInfo(
            sessionId: sessionId,
            geometryName: currentGeometryName,
            pipelineCacheCount: pipelineManager.pipelineCacheCount,
            snapshotReady: snapshotReady,
            textureReady: textureReady,
            modelStatus: modelLoadStatus,
            modelTextureEnabled: modelTextureEnabled,
            cameraDistance: cameraComponent.getStateSnapshot().distance,
            submeshCount: submeshCount,
            texturedSubmeshCount: texturedSubmeshCount
        )
    }
}

// MARK: - Geometry Switching

extension BaseRenderer: GeometrySwitching {
    var availableGeometries: [String] { geometryRegistry.names }
    var currentGeometryName: String {
        currentGeometryKey
            ?? renderState.currentGeometry.map { String(describing: type(of: $0)) }
            ?? "none"
    }
}

// MARK: - Model Texture Switching

extension BaseRenderer: ModelTextureSwitching {
    func setModelTextureEnabled(_ enabled: Bool) { modelTextureEnabled = enabled }
    func isModelTextureEnabled() -> Bool { modelTextureEnabled }
}

// MARK: - Camera Controlling

extension BaseRenderer: CameraControlling {}

// MARK: - Object Rotating

extension BaseRenderer: ObjectRotating {
    func rotateObject(deltaX: Float, deltaY: Float) {
        rotationStateManager.applyInput(x: deltaX, y: deltaY)
        refreshSnapshotIfPossible()
    }

    func resetObjectRotation() {
        rotationStateManager.reset()
        refreshSnapshotIfPossible()
    }
}

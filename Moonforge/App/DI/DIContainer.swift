//
//  DIContainer.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Metal
import MetalKit
import Foundation

// MARK: - Dependency Injection Container

/// Контейнер зависимостей приложения — без синглтона, создаётся явно
final class DIContainer {
    // MARK: - Properties

    /// Metal device для GPU операций
    let device: MTLDevice?

    /// Command queue для кодирования и отправки command buffers
    let commandQueue: MTLCommandQueue?

    /// Logger для логирования приложения
    let logger: Logger

    /// Settings service для пользовательских настроек
    let settingsService: SettingsService

    /// Renderer factory для создания Metal renderer
    private let rendererFactory: IRendererFactory

    /// Metal logger для engine-уровневого логирования
    private let metalLogger: MetalLogger

    // MARK: - Initialization

    init(
        device: MTLDevice? = MTLCreateSystemDefaultDevice(),
        commandQueue: MTLCommandQueue? = nil,
        logger: Logger = OSLogger(subsystem: "Moonforge", category: "App"),
        settingsService: SettingsService? = nil,
        rendererFactory: IRendererFactory? = nil
    ) {
        self.device = device
        self.commandQueue = commandQueue ?? device?.makeCommandQueue()
        self.logger = logger
        self.settingsService = settingsService ?? UserDefaultsSettingsService()
        
        let metalLogger = AppMetalLogger { message, level in
            logger.log(message, level: level)
        }
        self.metalLogger = metalLogger
        
        self.rendererFactory = rendererFactory ?? DefaultRendererFactory(
            device: device,
            logger: metalLogger,
            configuration: .default
        )

        if let device = device {
            logger.log("Metal device initialized: \(device.name)", level: .info)
        } else {
            logger.log("Metal device not available", level: .error)
        }
    }

    // MARK: - Factory Methods

    @MainActor
    func makeRenderer() -> SceneRenderer? {
        guard let renderer = rendererFactory.makeRenderer() else {
            return nil
        }

        SceneRendererBootstrap.configureDemoScene(renderer: renderer, logger: metalLogger)
        return renderer
    }

    func makeTextureRepository() -> TextureRepository? {
        guard let device = device else { return nil }

        let logger = self.logger
        let metalLogger = AppMetalLogger { message, level in
            logger.log(message, level: level)
        }

        return TextureRepository(device: device, logger: metalLogger)
    }

    // MARK: - Scene UseCase Factory

    @MainActor
    func makeSceneUseCases(renderer: SceneRenderer) -> (
        switchGeometryUseCase: SwitchGeometryUseCase,
        toggleModelTextureUseCase: ToggleModelTextureUseCase,
        adjustCameraUseCase: AdjustCameraUseCase,
        sceneService: SceneServiceProtocol
    ) {
        let logger = self.logger
        let metalLogger = AppMetalLogger { message, level in
            logger.log(message, level: level)
        }

        let sceneService = SceneServiceAdapter(renderer: renderer, logger: metalLogger)

        let switchGeometryUseCase = DefaultSwitchGeometryUseCase(
            geometrySwitcher: renderer,
            logger: metalLogger
        )

        let toggleModelTextureUseCase = DefaultToggleModelTextureUseCase(
            modelTextureSwitcher: renderer,
            logger: metalLogger
        )

        let adjustCameraUseCase = DefaultAdjustCameraUseCase(
            cameraController: renderer,
            logger: metalLogger
        )

        return (switchGeometryUseCase, toggleModelTextureUseCase, adjustCameraUseCase, sceneService)
    }

    @MainActor
    func makeSceneViewModel(renderer: SceneRenderer) -> SceneViewModel {
        let useCases = makeSceneUseCases(renderer: renderer)

        let logger = self.logger
        let metalLogger = AppMetalLogger { message, level in
            logger.log(message, level: level)
        }

        return SceneViewModel(
            switchGeometryUseCase: useCases.switchGeometryUseCase,
            toggleModelTextureUseCase: useCases.toggleModelTextureUseCase,
            adjustCameraUseCase: useCases.adjustCameraUseCase,
            sceneService: useCases.sceneService,
            renderer: renderer,
            logger: metalLogger
        )
    }
}

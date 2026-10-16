//
//  ToggleModelTextureUseCase.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 21.03.26.
//

import Foundation

// MARK: - Toggle Model Texture Use Case Protocol

/// Protocol for toggling model texture visibility
@MainActor
protocol ToggleModelTextureUseCase {
    /// Переключить видимость текстуры
    func execute() async

    /// Проверить, включена ли текстура
    func isModelTextureEnabled() -> Bool
}

// MARK: - Default Implementation

/// Default implementation using ModelTextureSwitching
@MainActor
final class DefaultToggleModelTextureUseCase: ToggleModelTextureUseCase {
    private let modelTextureSwitcher: ModelTextureSwitching
    private let logger: MetalLogger

    init(modelTextureSwitcher: ModelTextureSwitching, logger: MetalLogger) {
        self.modelTextureSwitcher = modelTextureSwitcher
        self.logger = logger
    }

    func execute() async {
        let newValue = !modelTextureSwitcher.isModelTextureEnabled()
        logger.log("Toggling model texture: \(newValue)", level: .debug)
        modelTextureSwitcher.setModelTextureEnabled(newValue)
    }

    func isModelTextureEnabled() -> Bool {
        modelTextureSwitcher.isModelTextureEnabled()
    }
}

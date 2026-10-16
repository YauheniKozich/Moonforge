import Foundation

// MARK: - Model Texture Switching Protocol

/// Протокол для включения и выключения рендеринга текстур модели
@MainActor
protocol ModelTextureSwitching: AnyObject {
    /// Включить или выключить рендеринг текстуры модели
    /// - Parameter enabled: Включить или выключить текстуру
    func setModelTextureEnabled(_ enabled: Bool)

    /// Проверить, включена ли текстура модели в данный момент
    /// - Returns: true, если текстура включена, false в противном случае
    func isModelTextureEnabled() -> Bool
}

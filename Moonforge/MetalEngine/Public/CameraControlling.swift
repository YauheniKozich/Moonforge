import Foundation

// MARK: - Camera Controlling Protocol

/// Протокол для управления камерой 3D сцены
@MainActor
protocol CameraControlling: AnyObject {
    /// Вращать камеру вокруг цели (orbit)
    /// - Parameters:
    ///   - deltaX: Горизонтальный дельта-коэффициент вращения
    ///   - deltaY: Вертикальный дельта-коэффициент вращения
    func orbit(deltaX: Float, deltaY: Float)

    /// Переместить камеру горизонтально/вертикально
    /// - Parameters:
    ///   - deltaX: Горизонтальная дельта перемещения
    ///   - deltaY: Вертикальная дельта перемещения
    func pan(deltaX: Float, deltaY: Float)

    /// Apply a pinch gesture scale directly to camera-object distance.
    /// - Parameter scale: `scale < 1` brings the object closer, `scale > 1` moves it farther away.
    func applyPinch(scale: Float)

    /// Сбросить камеру в положение по умолчанию
    func resetCamera()
}

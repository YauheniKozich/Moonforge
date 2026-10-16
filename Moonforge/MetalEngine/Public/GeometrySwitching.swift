import Foundation

// MARK: - Geometry Switching Protocol

/// Протокол для переключения между различными источниками геометрии
@MainActor
protocol GeometrySwitching: AnyObject {
    /// Переключиться на геометрию по имени (синхронно)
    /// - Parameter name: Имя геометрии, на которую нужно переключиться
    func switchGeometry(named name: String)

    func switchGeometryAsync(named name: String) async throws

    /// Получить список доступных имён геометрий
    var availableGeometries: [String] { get }

    /// Получить текущее имя геометрии
    var currentGeometryName: String { get }
    var geometrySwitchError: Error? { get }
}

extension GeometrySwitching {
    func switchGeometryAsync(named name: String) async throws {
        try Task.checkCancellation()
        switchGeometry(named: name)
        if let error = geometrySwitchError { throw error }
    }

    var geometrySwitchError: Error? { nil }
}

import Metal

// MARK: - Geometry Registry

/// Thread-safe registry for geometry factories using @MainActor.
///
/// Thread safety model:
/// - @MainActor: all methods run on Main thread
/// - Safe to call from any MainActor context
///
/// Usage:
/// ```swift
/// let registry = GeometryRegistry()
///
/// // Register geometry (Main thread)
/// registry.register("cube") { device in
///     try CubeGeometry(device: device, size: 1.0)
/// }
///
/// // Create geometry (Main thread)
/// let geometry = try registry.make("cube", device: device)
///
/// // Get available names
/// let names = registry.names
/// ```
@MainActor
final class GeometryRegistry {
    public typealias Factory = (MTLDevice) throws -> GeometrySource

    typealias AsyncFactory = (MTLDevice) async throws -> GeometrySource
    private var asyncFactories: [String: AsyncFactory] = [:]

    private var factories: [String: Factory] = [:]
    private var cachedNames: [String]?

    init() {}

    /// Register a geometry factory with the given name.
    func register(_ name: String, factory: @escaping Factory) {
        factories[name] = factory
        asyncFactories[name] = nil
        // Инвалидируем кэш при изменении
        cachedNames = nil
    }

    /// Create geometry instance using registered factory.
    /// - Parameters:
    ///   - name: Registered geometry name
    ///   - device: Metal device for buffer creation
    /// - Returns: GeometrySource instance
    /// - Throws: GeometryRegistryError.notFound if name is not registered
    func make(_ name: String, device: MTLDevice) throws -> GeometrySource {
        guard let factory = factories[name] else {
            throw GeometryRegistryError.notFound(name)
        }
        return try factory(device)
    }

    func registerAsync(_ name: String, factory: @escaping AsyncFactory) {
        asyncFactories[name] = factory
        cachedNames = nil
    }

    func makeAsync(_ name: String, device: MTLDevice) async throws -> GeometrySource {
        if let factory = asyncFactories[name] { return try await factory(device) }
        return try make(name, device: device)
    }

    /// Get list of registered geometry names.
    /// Кэширует отсортированный массив для производительности.
    var names: [String] {
        if cachedNames == nil {
            cachedNames = Set(factories.keys).union(asyncFactories.keys).sorted()
        }
        return cachedNames!
    }
}

// MARK: - Geometry Registry Error

enum GeometryRegistryError: Error, CustomStringConvertible {
    case notFound(String)

    var description: String {
        switch self {
        case .notFound(let name):
            return "Geometry not registered: \(name)"
        }
    }
}

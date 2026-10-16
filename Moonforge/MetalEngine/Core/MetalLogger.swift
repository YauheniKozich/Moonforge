import Foundation

// MARK: - Metal Log Level

/// Уровни логирования для MetalEngine
enum MetalLogLevel: Sendable {
    case debug
    case info
    case warning
    case error
}

// MARK: - Metal Logger Protocol

/// Протокол для логирования в MetalEngine
protocol MetalLogger: Sendable {
    func log(_ message: String, level: MetalLogLevel)
}

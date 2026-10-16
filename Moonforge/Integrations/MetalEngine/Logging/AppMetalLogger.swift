//
//  AppMetalLogger.swift
//  Moonforge
//
//  Created by Codex on 21.03.26.
//

import Foundation

// MARK: - App Metal Logger

/// Адаптер, который связывает логгер приложения с engine-native логированием.
final class AppMetalLogger: MetalLogger, Sendable {
    private let logMethod: @Sendable (String, LogLevel) -> Void

    init(logMethod: @escaping @Sendable (String, LogLevel) -> Void) {
        self.logMethod = logMethod
    }

    func log(_ message: String, level: MetalLogLevel) {
        let logLevel: LogLevel
        switch level {
        case .debug:
            logLevel = .debug

        case .info:
            logLevel = .info

        case .warning:
            logLevel = .warning

        case .error:
            logLevel = .error
        }

        logMethod(message, logLevel)
    }
}

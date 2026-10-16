//
//  Logger.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 21.10.25.
//

import os

// MARK: - Logger Protocol

protocol Logger: Sendable {
    func log(_ message: String, level: LogLevel)
}

enum LogLevel: Sendable {
    case info
    case debug
    case warning
    case error

    var osLogType: OSLogType {
        switch self {
        case .info: return .info
        case .debug: return .debug
        case .warning: return .default
        case .error: return .error
        }
    }

    var description: String {
        switch self {
        case .info: return "INFO"
        case .debug: return "DEBUG"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

// MARK: - OSLogger Implementation

final class OSLogger: Sendable {
    // MARK: - Properties

    private let logger: os.Logger

    // MARK: - Initialization

    init(subsystem: String, category: String) {
        self.logger = os.Logger(subsystem: subsystem, category: category)
    }
}

// MARK: - Logger Protocol

extension OSLogger: Logger {
    func log(_ message: String, level: LogLevel) {
        logger.log(level: level.osLogType, "\(message, privacy: .public)")
    }
}

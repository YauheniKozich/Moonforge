//
//  AppError.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Foundation

// MARK: - App Error

/// Centralized error type for the application
enum AppError: LocalizedError {
    case metalNotSupported
    case commandQueueCreationFailed
    case rendererSetupFailed(Error)
    case textureLoadingFailed
    case unknown(Error)

    // MARK: - Error Description

    var errorDescription: String? {
        switch self {
        case .metalNotSupported:
            return "Metal is not supported on this device"
        case .commandQueueCreationFailed:
            return "Failed to create command queue"
        case .rendererSetupFailed(let error):
            return "Renderer setup failed: \(error.localizedDescription)"
        case .textureLoadingFailed:
            return "Failed to load texture"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }

    // MARK: - Recovery Suggestion

    var recoverySuggestion: String? {
        switch self {
        case .metalNotSupported:
            return "This app requires a device with Metal support"
        case .commandQueueCreationFailed, .rendererSetupFailed:
            return "Try restarting the app"
        case .textureLoadingFailed:
            return "The app will use a fallback texture"
        default:
            return nil
        }
    }

    // MARK: - Is Recoverable

    var isRecoverable: Bool {
        switch self {
        case .textureLoadingFailed:
            return true  // Can use fallback texture
        case .metalNotSupported:
            return false  // Cannot recover
        default:
            return true  // Most errors are recoverable
        }
    }
}

// MARK: - Error Mapping

extension AppError {
    /// Map from other error types to AppError
    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        return .unknown(error)
    }
}

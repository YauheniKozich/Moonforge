//
//  SettingsViewModel.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Foundation
import Observation

// MARK: - Settings View Model

/// ViewModel для экрана настроек
@Observable
final class SettingsViewModel {
    // MARK: - Properties

    var isDarkModeEnabled: Bool {
        didSet {
            guard !isApplyingStoredSettings, oldValue != isDarkModeEnabled else { return }
            saveSettings()
        }
    }
    
    var targetFrameRate: Int {
        didSet {
            let validatedValue = Self.validatedFrameRate(targetFrameRate)
            if targetFrameRate != validatedValue {
                targetFrameRate = validatedValue
                return
            }

            guard !isApplyingStoredSettings, oldValue != targetFrameRate else { return }
            saveSettings()
        }
    }

    // MARK: - Configuration

    static let supportedFrameRates = [30, 60, 120]
    var availableFrameRates: [Int] { Self.supportedFrameRates }
    private let settingsService: SettingsService
    private var isApplyingStoredSettings = false

    // MARK: - Callbacks

    var onNavigateToAbout: (() -> Void)?

    // MARK: - Initialization

    init(settingsService: SettingsService) {
        self.settingsService = settingsService
        let settings = settingsService.load()
        self.isDarkModeEnabled = settings.isDarkModeEnabled
        self.targetFrameRate = Self.validatedFrameRate(settings.targetFrameRate)
    }

    // MARK: - Settings Management

    func loadSettings() {
        let settings = settingsService.load()
        isApplyingStoredSettings = true
        isDarkModeEnabled = settings.isDarkModeEnabled
        targetFrameRate = Self.validatedFrameRate(settings.targetFrameRate)
        isApplyingStoredSettings = false
    }

    func saveSettings() {
        let settings = Settings(
            isDarkModeEnabled: isDarkModeEnabled,
            targetFrameRate: targetFrameRate
        )
        settingsService.save(settings)
    }

    // MARK: - Navigation

    func navigateToAbout() {
        onNavigateToAbout?()
    }

    // MARK: - Validation

    private static func validatedFrameRate(_ frameRate: Int) -> Int {
        guard supportedFrameRates.contains(frameRate) else {
            return Settings.default.targetFrameRate
        }

        return frameRate
    }
}

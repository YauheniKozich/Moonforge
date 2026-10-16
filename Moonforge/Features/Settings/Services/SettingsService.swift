//
//  SettingsService.swift
//  Moonforge
//
//  Created by Codex on 19.03.26.
//

import Foundation

// MARK: - Settings Service Protocol

protocol SettingsService: AnyObject {
    func load() -> Settings
    func save(_ settings: Settings)
}

// MARK: - UserDefaults Settings Service

final class UserDefaultsSettingsService: SettingsService {
    private struct Keys {
        static let isDarkModeEnabled = "isDarkModeEnabled"
        static let targetFrameRate = "targetFrameRate"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> Settings {
        let isDarkModeEnabled = userDefaults.object(forKey: Keys.isDarkModeEnabled) as? Bool ?? Settings.default.isDarkModeEnabled
        let targetFrameRate = userDefaults.object(forKey: Keys.targetFrameRate) as? Int ?? Settings.default.targetFrameRate
        return Settings(
            isDarkModeEnabled: isDarkModeEnabled,
            targetFrameRate: targetFrameRate
        )
    }

    func save(_ settings: Settings) {
        userDefaults.set(settings.isDarkModeEnabled, forKey: Keys.isDarkModeEnabled)
        userDefaults.set(settings.targetFrameRate, forKey: Keys.targetFrameRate)
    }
}

// MARK: - In-Memory Settings Service

final class InMemorySettingsService: SettingsService {
    private var settings: Settings
    var onSave: ((Settings) -> Void)?

    init(initial: Settings = .default) {
        self.settings = initial
    }

    func load() -> Settings {
        settings
    }

    func save(_ settings: Settings) {
        self.settings = settings
        onSave?(settings)
    }
}

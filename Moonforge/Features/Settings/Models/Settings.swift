//
//  Settings.swift
//  Moonforge
//
//  Created by Codex on 19.03.26.
//

import Foundation

// MARK: - Settings Model

struct Settings: Equatable {
    var isDarkModeEnabled: Bool
    var targetFrameRate: Int

    static let `default` = Settings(
        isDarkModeEnabled: false,
        targetFrameRate: 60
    )
}

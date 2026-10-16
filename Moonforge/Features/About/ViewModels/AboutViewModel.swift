//
//  AboutViewModel.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Foundation
import Observation

// MARK: - About View Model

/// ViewModel for About screen
@Observable
final class AboutViewModel {
    // MARK: - Properties

    private(set) var appName: String = "Moonforge"
    private(set) var appVersion: String = "1.0.0"
    private(set) var appBuild: String = "1"

    // MARK: - Initialization

    init() {
        loadAppInfo()
    }

    // MARK: - App Info

    private func loadAppInfo() {
        appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Moonforge"
        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

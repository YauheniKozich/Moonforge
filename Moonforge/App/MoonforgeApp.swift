//
//  MoonforgeApp.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 29.10.24.
//

import SwiftUI

@main
struct MoonforgeApp: App {
    private let appState = AppState()

    var body: some Scene {
        WindowGroup {
            appState.rootView
        }
    }
}

// MARK: - App State

/// Manages app initialization and state
@MainActor
private final class AppState {
    private let container: DIContainer
    private let coordinator: AppCoordinator

    let rootView: AnyView

    init() {
        self.container = DIContainer()
        self.coordinator = AppCoordinator(container: container)
        self.coordinator.start()
        self.rootView = AnyView(coordinator.makeRootView())
    }
}

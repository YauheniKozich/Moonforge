//
//  AppCoordinator.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import SwiftUI

// MARK: - App Coordinator

/// Main coordinator for app flow
final class AppCoordinator: Coordinator {
    var children: [Coordinator] = []
    var parent: Coordinator?

    private let container: DIContainer
    let navigationState: NavigationState
    private lazy var settingsViewModel: SettingsViewModel = {
        let viewModel = SettingsViewModel(settingsService: container.settingsService)
        viewModel.onNavigateToAbout = { [weak self] in
            self?.navigateToAbout()
        }
        return viewModel
    }()

    init(container: DIContainer) {
        self.container = container
        self.navigationState = NavigationState()
    }

    func start() {
        logger.log("App coordinator started", level: .info)
    }

    // MARK: - Factory Methods

    @MainActor
    func makeRootView() -> any View {
        guard let renderer = container.makeRenderer() else {
            return Text("Failed to create renderer")
        }
        let sceneViewModel = container.makeSceneViewModel(renderer: renderer)
        return AppRootView(
            coordinator: self,
            sceneViewModel: sceneViewModel,
            settingsViewModel: settingsViewModel,
            aboutViewModelFactory: makeAboutViewModel,
            navigationState: navigationState
        )
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        settingsViewModel
    }

    func makeAboutViewModel() -> AboutViewModel {
        AboutViewModel()
    }

    // MARK: - Navigation Methods

    func navigateTo(_ destination: NavigationDestination) {
        navigationState.push(destination)
    }

    func navigateToSettings() {
        navigateTo(.settings)
    }

    func navigateToAbout() {
        navigateTo(.about)
    }

    func navigateBack() {
        navigationState.pop()
    }

    func navigateToRoot() {
        navigationState.popToRoot()
        children.removeAll()
    }

    // MARK: - Private Properties

    private var logger: Logger {
        container.logger
    }

    // MARK: - Error Handling

    func handle(_ error: Error) {
        let appError = AppError.from(error)

        logger.log("Error: \(appError.errorDescription ?? "Unknown")", level: .error)

        if appError.isRecoverable {
            navigationState.push(.error(appError.errorDescription ?? "Unknown error"))
        } else {
            logger.log("Fatal error: \(appError)", level: .error)
        }
    }
}

// MARK: - Error Handler

extension AppCoordinator: ErrorHandler {
    // Метод handle реализован в основном классе
}

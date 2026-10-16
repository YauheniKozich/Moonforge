//
//  NavigationState.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import SwiftUI
import Combine

// MARK: - Navigation Destination

/// Type-safe navigation destinations
enum NavigationDestination: Hashable {
    case settings
    case about
    case scene
    case error(String)  // Use String instead of AppError for Hashable conformance
}

// MARK: - Navigation State

/// State object for managing navigation state
@Observable
final class NavigationState {
    // MARK: - Published Properties

    var path = NavigationPath()

    // MARK: - Navigation Methods

    func push(_ destination: NavigationDestination) {
        path.append(destination)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path = NavigationPath()
    }

    func canPop() -> Bool {
        !path.isEmpty
    }

    // MARK: - Convenience Methods

    func navigateToSettings() {
        push(.settings)
    }

    func navigateToAbout() {
        push(.about)
    }

    func navigateToCubeRenderer() {
        push(.scene)
    }
}

// MARK: - Environment Key

private struct NavigationStateKey: EnvironmentKey {
    static var defaultValue: NavigationState? { nil }
}

extension EnvironmentValues {
    var navigationState: NavigationState? {
        get { self[NavigationStateKey.self] }
        set { self[NavigationStateKey.self] = newValue }
    }
}

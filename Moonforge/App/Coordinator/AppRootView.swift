//
//  AppRootView.swift
//  Moonforge
//
//  Created by Codex on 21.03.26.
//

import SwiftUI

@MainActor
struct AppRootView: View {
    let coordinator: AppCoordinator
    let sceneViewModel: SceneViewModel
    let settingsViewModel: SettingsViewModel
    let aboutViewModelFactory: () -> AboutViewModel

    @Bindable var navigationState: NavigationState

    var body: some View {
        NavigationStack(path: $navigationState.path) {
            SceneView(
                viewModel: sceneViewModel,
                targetFrameRate: settingsViewModel.targetFrameRate,
                onOpenSettings: coordinator.navigateToSettings,
                onError: coordinator.handle
            )
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .scene:
                    SceneView(
                        viewModel: sceneViewModel,
                        targetFrameRate: settingsViewModel.targetFrameRate,
                        onOpenSettings: coordinator.navigateToSettings,
                        onError: coordinator.handle
                    )
                case .settings:
                    SettingsView(viewModel: settingsViewModel)
                        .toolbar(.visible, for: .navigationBar)
                        .statusBarHidden(false)
                case .about:
                    AboutView(viewModel: aboutViewModelFactory())
                case .error(let message):
                    RecoverableErrorView(message: message)
                }
            }
        }
        .preferredColorScheme(settingsViewModel.isDarkModeEnabled ? .dark : .light)
        .environment(\.navigationState, navigationState)
    }
}

private struct RecoverableErrorView: View {
    let message: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Something went wrong")
                .font(.title2.weight(.semibold))

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Go Back") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .navigationTitle("Error")
        .navigationBarTitleDisplayMode(.inline)
    }
}

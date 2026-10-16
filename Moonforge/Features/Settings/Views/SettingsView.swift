//
//  SettingsView.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import SwiftUI

// MARK: - Settings View

/// Settings screen - app configuration
struct SettingsView: View {
    var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Form {
            Section(header: Text("Appearance")) {
                Toggle("Dark Mode", isOn: Binding(
                    get: { viewModel.isDarkModeEnabled },
                    set: { viewModel.isDarkModeEnabled = $0 }
                ))
                .accessibilityLabel("Dark Mode")
                .accessibilityHint("Enable or disable dark mode")
            }

            Section(header: Text("Performance")) {
                Picker("Frame Rate", selection: Binding(
                    get: { viewModel.targetFrameRate },
                    set: { viewModel.targetFrameRate = $0 }
                )) {
                    ForEach(viewModel.availableFrameRates, id: \.self) { frameRate in
                        Text("\(frameRate) FPS").tag(frameRate)
                    }
                }
                .accessibilityLabel("Target Frame Rate")
                .accessibilityHint("Select maximum frame rate for rendering")
            }

            Section(header: Text("About")) {
                Button("About Moonforge") {
                    viewModel.navigateToAbout()
                }
                .accessibilityLabel("About Moonforge")
                .accessibilityHint("Learn more about this app")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview("Settings") {
    SettingsView(
        viewModel: SettingsViewModel(
            settingsService: InMemorySettingsService()
        )
    )
}

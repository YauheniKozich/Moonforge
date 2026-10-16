//
//  AboutView.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import SwiftUI

// MARK: - About View

/// About screen - app information
struct AboutView: View {
    var viewModel: AboutViewModel

    init(viewModel: AboutViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        List {
            Section(header: Text("Application")) {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(viewModel.appName)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Version")
                    Spacer()
                    Text(viewModel.appVersion)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Build")
                    Spacer()
                    Text(viewModel.appBuild)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Technology")) {
                HStack {
                    Text("Framework")
                    Spacer()
                    Text("Metal + SwiftUI")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Minimum iOS")
                    Spacer()
                    Text("iOS 17.0+")
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Developer")) {
                Link("GitHub Repository", destination: URL(string: "https://github.com/YauheniKozich/SwiftMetal3D")!)
                    .accessibilityLabel("GitHub Repository")
                    .accessibilityHint("Opens GitHub in browser")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview("About") {
    AboutView(viewModel: AboutViewModel())
}

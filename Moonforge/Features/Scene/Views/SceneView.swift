//
//  SceneView.swift
//  Moonforge
//
//  Created by assistant on 20.10.25.
//  Refactored by Yauheni Kozich on 17.03.26.
//

import SwiftUI
import MetalKit

// MARK: - Cube View

/// UI for configuring cube gesture sensitivity
struct SceneView: View {
    var viewModel: SceneViewModel
    var targetFrameRate: Int
    var onOpenSettings: (() -> Void)?
    var onError: ((Error) -> Void)?
    @State private var isDebugPanelVisible = false

    init(
        viewModel: SceneViewModel,
        targetFrameRate: Int = Settings.default.targetFrameRate,
        onOpenSettings: (() -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.targetFrameRate = targetFrameRate
        self.onOpenSettings = onOpenSettings
        self.onError = onError
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { _ in
                ZStack(alignment: .topLeading) {
                    SceneMetalView(
                        renderer: viewModel.renderer,
                        sensitivity: .init(
                            rotation: validatedFloat(viewModel.rotationSensitivity)
                        ),
                        preferredFramesPerSecond: targetFrameRate,
                        onError: { message in
                            viewModel.setError(message)
                            onError?(AppError.textureLoadingFailed)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .ignoresSafeArea(.container)
                    .background(Color(UIColor.systemBackground).ignoresSafeArea())
                    .accessibilityLabel(Text("3D Model View"))

                    if let error = viewModel.errorMessage {
                        ErrorOverlayView(
                            message: error,
                            onRetry: {
                                viewModel.clearError()
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    VStack {
                        HStack {
                            Spacer()
                            if let onOpenSettings {
                                Button(action: onOpenSettings) {
                                    Image(systemName: "gearshape")
                                        .padding()
                                        .background(Color.black.opacity(0.6))
                                        .foregroundColor(.white)
                                        .clipShape(Circle())
                                }
                                .accessibilityLabel("Open settings")
                            }
                            Button {
                                isDebugPanelVisible.toggle()
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .padding()
                                    .background(Color.black.opacity(0.6))
                                    .foregroundColor(.white)
                                    .clipShape(Circle())
                            }
                        }
                        .padding()
                        Spacer()
                    }
                )
                .sheet(isPresented: $isDebugPanelVisible) {
                    RenderDebugPanel(
                        fps: viewModel.fps,
                        info: viewModel.debugInfo,
                        availableGeometries: viewModel.availableGeometries,
                        selectedGeometry: viewModel.selectedGeometry,
                        onSelectGeometry: viewModel.selectGeometry,
                        modelTextureEnabled: viewModel.modelTextureEnabled,
                        onToggleModelTexture: viewModel.toggleModelTexture,
                        leadingPadding: 16,
                        topPadding: 12,
                        contentLeadingPadding: 4
                    )
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .height(280)))
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle("Moonforge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
    }

    private func validatedFloat(_ value: Double) -> Float {
        Float(value.clamped(to: 0.0000001...0.1))
    }

}

// MARK: - Previews

#Preview("Scene") {
    let container = DIContainer()
    guard let renderer = container.makeRenderer() else {
        return Text("Failed to create renderer")
    }
    let viewModel = container.makeSceneViewModel(renderer: renderer)
    return SceneView(viewModel: viewModel)
}

//
//  SceneMetalView.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 29.10.24.
//  Refactored by Yauheni Kozich on 21.03.26.
//

import SwiftUI
import MetalKit
import UIKit

// MARK: - Scene Metal View

struct SceneMetalView: UIViewRepresentable {
    struct Sensitivity {
        var rotation: Float = 0.005
    }

    private let renderer: MetalRenderable
    private let sensitivity: Sensitivity
    private let preferredFramesPerSecond: Int
    private let onError: ((String) -> Void)?
    private let onPinchTelemetry: ((Bool, Float) -> Void)?

    init(
        renderer: MetalRenderable,
        sensitivity: Sensitivity = Sensitivity(),
        preferredFramesPerSecond: Int = Settings.default.targetFrameRate,
        onError: ((String) -> Void)? = nil,
        onPinchTelemetry: ((Bool, Float) -> Void)? = nil
    ) {
        self.renderer = renderer
        self.sensitivity = sensitivity
        self.preferredFramesPerSecond = preferredFramesPerSecond
        self.onError = onError
        self.onPinchTelemetry = onPinchTelemetry
    }

    func makeCoordinator() -> GestureCoordinator {
        GestureCoordinator(
            sensitivity: sensitivity,
            onError: onError,
            onPinchTelemetry: onPinchTelemetry
        )
    }

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView(frame: .zero)
        containerView.backgroundColor = .clear

        let metalView = MTKView(frame: .zero, device: renderer.device)
        metalView.translatesAutoresizingMaskIntoConstraints = false
        configure(metalView)
        context.coordinator.setup(renderer: renderer, mtkView: metalView)
        context.coordinator.attach(metalView: metalView)

        metalView.isAccessibilityElement = true
        metalView.accessibilityLabel = "3D Scene"
        metalView.accessibilityHint = "Swipe to rotate object, pinch to zoom"
        metalView.accessibilityValue = "3D object visualization"

        let interactionView = InteractionCaptureView(frame: .zero)
        interactionView.translatesAutoresizingMaskIntoConstraints = false
        interactionView.backgroundColor = .clear
        interactionView.isOpaque = false
        interactionView.isMultipleTouchEnabled = true

        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(GestureCoordinator.handlePan(_:))
        )
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = context.coordinator
        interactionView.addGestureRecognizer(panGesture)

        let pinchGesture = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(GestureCoordinator.handlePinch(_:))
        )
        pinchGesture.cancelsTouchesInView = false
        pinchGesture.delegate = context.coordinator
        interactionView.addGestureRecognizer(pinchGesture)

        containerView.addSubview(metalView)
        containerView.addSubview(interactionView)

        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            metalView.topAnchor.constraint(equalTo: containerView.topAnchor),
            metalView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            interactionView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            interactionView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            interactionView.topAnchor.constraint(equalTo: containerView.topAnchor),
            interactionView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        context.coordinator.attach(interactionView: interactionView)

        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let metalView = context.coordinator.metalView else { return }

        let nativeScale = uiView.window?.screen.nativeScale ?? UIScreen.main.nativeScale
        if metalView.contentScaleFactor != nativeScale {
            metalView.contentScaleFactor = nativeScale
        }
        let size = uiView.bounds.size
        let drawableSize = CGSize(width: size.width * nativeScale, height: size.height * nativeScale)

        if metalView.drawableSize != drawableSize {
            metalView.drawableSize = drawableSize
        }

        if metalView.preferredFramesPerSecond != preferredFramesPerSecond {
            metalView.preferredFramesPerSecond = preferredFramesPerSecond
        }

        context.coordinator.sensitivity = sensitivity
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: GestureCoordinator) {
        coordinator.metalView?.delegate = nil
        coordinator.cleanup()
    }

    private func configure(_ view: MTKView) {
        view.contentScaleFactor = UIScreen.main.nativeScale
        view.isMultipleTouchEnabled = true
        view.clearColor = MTLClearColorMake(0.05, 0.05, 0.15, 1.0)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = view.device?.supportsTextureSampleCount(4) == true ? 4 : 1
        view.preferredFramesPerSecond = preferredFramesPerSecond
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.contentMode = .scaleAspectFill
    }
}

// MARK: - Gesture Coordinator

@MainActor
final class GestureCoordinator: NSObject, UIGestureRecognizerDelegate {
    var sensitivity: SceneMetalView.Sensitivity
    weak var metalView: MTKView?
    weak var interactionView: InteractionCaptureView?

    private weak var renderer: MetalRenderable?
    private var metalViewDelegate: MetalViewDelegate?
    private let onError: ((String) -> Void)?
    private let onPinchTelemetry: ((Bool, Float) -> Void)?

    init(
        sensitivity: SceneMetalView.Sensitivity,
        onError: ((String) -> Void)?,
        onPinchTelemetry: ((Bool, Float) -> Void)?
    ) {
        self.sensitivity = sensitivity
        self.onError = onError
        self.onPinchTelemetry = onPinchTelemetry
    }

    func setup(renderer: MetalRenderable, mtkView: MTKView) {
        self.renderer = renderer

        do {
            try renderer.setup(metalView: mtkView)

            if let viewRenderer = renderer as? any MetalViewRendering {
                let delegate = viewRenderer.makeViewDelegate()
                mtkView.delegate = delegate
                metalViewDelegate = delegate as? MetalViewDelegate
            }
        } catch {
            onError?(error.localizedDescription)
        }
    }

    func attach(metalView: MTKView) {
        self.metalView = metalView
    }

    func attach(interactionView: InteractionCaptureView) {
        self.interactionView = interactionView
    }

    func cleanup() {
        renderer?.cleanup()
        renderer = nil
        metalView = nil
        interactionView = nil
        metalViewDelegate = nil
    }

    @objc
    func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let renderer else { return }

        let translation = gesture.translation(in: gesture.view)

        guard gesture.state == .changed else {
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                gesture.setTranslation(.zero, in: gesture.view)
            }
            return
        }

#if targetEnvironment(simulator)
        if interactionView?.isShiftPressed == true,
           let cameraController = renderer as? CameraControlling {
            let deltaY = Float(translation.y)
            let scale = exp(deltaY * 0.01)
            onPinchTelemetry?(true, scale)
            cameraController.applyPinch(scale: scale)
            gesture.setTranslation(.zero, in: gesture.view)
            return
        }
#endif

        guard let cameraController = renderer as? CameraControlling else { return }
        let deltaX = Float(translation.x) * sensitivity.rotation
        let deltaY = Float(translation.y) * sensitivity.rotation
        cameraController.orbit(
            deltaX: deltaX / MetalConfiguration.Camera.orbitSensitivity,
            deltaY: deltaY / MetalConfiguration.Camera.orbitSensitivity
        )
        gesture.setTranslation(.zero, in: gesture.view)
    }

    @objc
    func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let renderer, let cameraController = renderer as? CameraControlling else { return }

        switch gesture.state {
        case .began:
            onPinchTelemetry?(true, Float(gesture.scale))
        case .changed:
            let scale = max(0.01, Float(gesture.scale))
            onPinchTelemetry?(true, scale)
            cameraController.applyPinch(scale: scale)
            gesture.scale = 1.0
        case .ended, .cancelled, .failed:
            onPinchTelemetry?(false, 1.0)
            gesture.scale = 1.0
        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

final class InteractionCaptureView: UIView {
    private(set) var isShiftPressed = false

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        becomeFirstResponder()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        updateModifierState(from: presses, isPressed: true)
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        updateModifierState(from: presses, isPressed: false)
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        updateModifierState(from: presses, isPressed: false)
        super.pressesCancelled(presses, with: event)
    }

    private func updateModifierState(from presses: Set<UIPress>, isPressed: Bool) {
        for press in presses {
            guard let key = press.key else { continue }
            if key.keyCode == .keyboardLeftShift || key.keyCode == .keyboardRightShift {
                isShiftPressed = isPressed
            }
        }
    }
}

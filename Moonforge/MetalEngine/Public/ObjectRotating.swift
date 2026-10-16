import Foundation

// MARK: - Object Rotating Protocol

/// Public capability for rotating the rendered object around its own axes.
@MainActor
protocol ObjectRotating: AnyObject {
    /// Rotate the current object around its local X/Y axes while keeping it centered.
    func rotateObject(deltaX: Float, deltaY: Float)

    /// Reset the current object rotation to the default centered orientation.
    func resetObjectRotation()
}

//
//  Coordinator.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Foundation

// MARK: - Coordinator Protocol

/// Base protocol for all coordinators
protocol Coordinator: AnyObject {
    var children: [Coordinator] { get set }
    var parent: Coordinator? { get set }
    
    func start()
    func navigateTo(_ destination: NavigationDestination)
    func navigateBack()
    func navigateToRoot()
}

// MARK: - Default Implementation

extension Coordinator {
    func navigateTo(_ destination: NavigationDestination) {
        // Default implementation - can be overridden
    }
    
    func navigateBack() {
        parent?.navigateBack()
    }
    
    func navigateToRoot() {
        children.removeAll()
    }
}

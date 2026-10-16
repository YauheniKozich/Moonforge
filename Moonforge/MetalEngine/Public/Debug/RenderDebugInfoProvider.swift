//
//  RenderDebugInfoProvider.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Foundation

// MARK: - Debug Info Provider

@MainActor
protocol RenderDebugInfoProvider: AnyObject {
    var debugInfo: RenderDebugInfo { get }
}

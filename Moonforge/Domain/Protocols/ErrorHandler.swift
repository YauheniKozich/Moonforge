//
//  ErrorHandler.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Foundation

// MARK: - Error Handler Protocol

/// Protocol for handling errors centrally
protocol ErrorHandler {
    func handle(_ error: Error)
}

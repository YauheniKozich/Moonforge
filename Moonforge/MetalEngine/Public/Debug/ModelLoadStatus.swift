//
//  ModelLoadStatus.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 21.10.25.
//

import Foundation

enum ModelLoadStatus: String, Sendable {
    case ok = "OK"
    case missing = "Missing"
    case unsupportedIndexType = "Unsupported indexType"
    case missingAttributes = "Missing attributes"
    case failed = "Failed"
    case loading = "Loading"
    case notApplicable = "-"

    public static func from(error: Error) -> ModelLoadStatus {
        guard let metalError = error as? MetalError else { return .failed }
        switch metalError {
        case .modelLoadingFailed(let details):
            let text = details.lowercased()
            if text.contains("resource not found") { return .missing }
            if text.contains("unsupported index type") { return .unsupportedIndexType }
            if text.contains("failed to generate normals") || text.contains("failed to generate uvs") {
                return .missingAttributes
            }
            if text.contains("no mesh found") || text.contains("no submesh found") {
                return .failed
            }
            return .failed
        default:
            return .failed
        }
    }
}

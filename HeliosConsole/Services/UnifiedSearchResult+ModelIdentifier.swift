//
//  UnifiedSearchResult+ModelIdentifier.swift
//  Helios
//
//  Extension to add modelIdentifier property to UnifiedSearchResult
//  This enables the use of realistic device icons in search results
//

import Foundation

extension UnifiedSearchResult {
    /// Returns the model identifier for CoreTypes icon lookup
    var modelIdentifier: String? {
        switch self {
        case .computer(let computer):
            return computer.hardware?.modelIdentifier
        case .mobileDevice(let device):
            // Mobile devices may not have modelIdentifier, derive from model name
            return nil
        }
    }
}

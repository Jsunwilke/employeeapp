//
//  UUID+Normalize.swift
//  Iconik Employee
//
//  Created to ensure consistent UUID handling across the app
//  UUIDs are normalized to lowercase for database compatibility
//

import Foundation

extension UUID {
    /// Returns lowercase string representation for consistent database storage
    /// Use this instead of .uuidString when storing or comparing UUIDs with database values
    var normalizedString: String {
        return self.uuidString.lowercased()
    }
}

extension String {
    /// Normalizes a UUID string to lowercase for consistent comparison
    /// Use this when comparing UUID strings from different sources
    var normalizedUUID: String {
        return self.lowercased()
    }
}

//
//  ImageNumbersMerger.swift
//  Iconik Employee
//
//  Intelligent merging utility for image numbers and notes fields
//  Handles multi-user conflict resolution by combining changes instead of overwriting
//

import Foundation

class ImageNumbersMerger {

    // MARK: - Image Numbers Merging

    /// Intelligently merge image numbers from two sources
    /// - Parameters:
    ///   - local: Image numbers from local/offline changes
    ///   - remote: Image numbers from remote/Firestore
    /// - Returns: Merged string with format "101, 102, 234-35, 678-79"
    ///
    /// Rules:
    /// - Preserves range notation (e.g., "234-35")
    /// - Removes exact duplicates
    /// - Sorts numerically by first number in each token
    /// - Uses ", " (comma+space) separator in result
    static func mergeImageNumbers(local: String, remote: String) -> String {
        // Handle empty cases
        if local.isEmpty && remote.isEmpty {
            return ""
        }
        if local.isEmpty {
            return remote
        }
        if remote.isEmpty {
            return local
        }

        // Parse both strings into tokens
        let localTokens = parseImageNumbers(local)
        let remoteTokens = parseImageNumbers(remote)

        // Combine and remove exact duplicates
        var combined = localTokens + remoteTokens
        combined = Array(Set(combined)) // Remove duplicates

        // Sort numerically by first number
        combined.sort { sortToken($0) < sortToken($1) }

        // Join with ", " separator
        return combined.joined(separator: ", ")
    }

    /// Parse image numbers string into individual tokens
    /// Handles various formats: "101, 102", "234-35", "101 102 103", "234-35,678-79"
    private static func parseImageNumbers(_ input: String) -> [String] {
        // Split by comma and/or space
        let separators = CharacterSet(charactersIn: ",")
        let components = input.components(separatedBy: separators)

        // Further split by whitespace and clean up
        var tokens: [String] = []
        for component in components {
            let subTokens = component.split(separator: " ").map { String($0) }
            tokens.append(contentsOf: subTokens)
        }

        // Trim whitespace and filter empty strings
        return tokens
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Extract the numeric value for sorting
    /// For ranges like "234-35", uses the first number (234)
    /// For single numbers like "101", uses that number
    private static func sortToken(_ token: String) -> Int {
        // Check if it's a range (contains hyphen)
        if let hyphenIndex = token.firstIndex(of: "-") {
            let firstPart = String(token[..<hyphenIndex])
            return Int(firstPart) ?? 0
        }

        // Single number
        return Int(token) ?? 0
    }

    // MARK: - Notes Merging

    /// Intelligently merge notes from two sources
    /// - Parameters:
    ///   - local: Notes from local/offline changes
    ///   - remote: Notes from remote/Firestore
    /// - Returns: Merged string with format "Note A; Note B"
    ///
    /// Rules:
    /// - If both empty, returns ""
    /// - If one empty, returns the other
    /// - If both have content, combines with "; " separator
    /// - Removes duplicate sentences if identical
    static func mergeNotes(local: String, remote: String) -> String {
        // Trim whitespace
        let localTrimmed = local.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteTrimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle empty cases
        if localTrimmed.isEmpty && remoteTrimmed.isEmpty {
            return ""
        }
        if localTrimmed.isEmpty {
            return remoteTrimmed
        }
        if remoteTrimmed.isEmpty {
            return localTrimmed
        }

        // If identical, return one copy
        if localTrimmed == remoteTrimmed {
            return localTrimmed
        }

        // Combine with semicolon separator
        return "\(localTrimmed); \(remoteTrimmed)"
    }

    // MARK: - Validation Helpers

    /// Check if two image number strings represent the same content (ignoring formatting)
    static func areEquivalent(first: String, second: String) -> Bool {
        let firstTokens = Set(parseImageNumbers(first))
        let secondTokens = Set(parseImageNumbers(second))
        return firstTokens == secondTokens
    }

    /// Normalize image numbers to standard format (for display/comparison)
    static func normalize(_ imageNumbers: String) -> String {
        let tokens = parseImageNumbers(imageNumbers)
        var sorted = tokens
        sorted.sort { sortToken($0) < sortToken($1) }
        return sorted.joined(separator: ", ")
    }
}

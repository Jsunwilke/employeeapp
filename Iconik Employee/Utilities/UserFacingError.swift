import Foundation

/// Turns raw errors (Postgrest/URLSession/decoding) into short, human messages
/// suitable for an alert. Field users were seeing things like
/// "The operation couldn't be completed. (PostgrestError error 1.)"; this maps
/// the common cases to plain English and falls back to a friendly generic
/// message instead of leaking internals.
///
/// Usage: `Text(UserFacing.message(for: error))`, or `error.userFacingMessage`.
enum UserFacing {
    static func message(for error: Error) -> String {
        // App-defined errors already write for humans — trust their text.
        if let localized = error as? LocalizedError, let desc = localized.errorDescription {
            // ...unless it's the generic Cocoa wrapper, which isn't helpful.
            if !desc.contains("couldn't be completed") { return desc }
        }

        // No connection.
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You appear to be offline. Check your connection and try again."
            case .timedOut:
                return "The server took too long to respond. Please try again."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Can't reach the server right now. Please try again in a moment."
            default:
                return "Network problem. Please check your connection and try again."
            }
        }

        let raw = String(describing: error).lowercased()

        // PostgREST / Supabase surfaces.
        if raw.contains("offline") || raw.contains("network") || raw.contains("connection") {
            return "You appear to be offline. Check your connection and try again."
        }
        if raw.contains("duplicate key") || raw.contains("already exists") {
            return "That already exists."
        }
        if raw.contains("permission") || raw.contains("row-level security") || raw.contains("not authorized") || raw.contains("403") {
            return "You don't have permission to do that."
        }
        if raw.contains("jwt") || raw.contains("token") || raw.contains("401") || raw.contains("not authenticated") {
            return "Your session expired. Please sign in again."
        }
        if raw.contains("decoding") || raw.contains("decode") {
            return "Something went wrong reading data from the server."
        }

        // Unknown — don't leak internals.
        return "Something went wrong. Please try again."
    }
}

extension Error {
    /// Convenience: `error.userFacingMessage`.
    var userFacingMessage: String { UserFacing.message(for: self) }
}

//
//  SupabasePowerSyncConnector.swift
//  Iconik Employee
//
//  Connector that bridges Supabase authentication with PowerSync
//  Handles credential fetching and data upload to Supabase
//

import Foundation
import PowerSync
import Supabase

/// PowerSync connector that uses Supabase for authentication and data writes
final class SupabasePowerSyncConnector: PowerSyncBackendConnectorProtocol {

    // PowerSync instance URL
    private let powerSyncURL = "https://693dfb6e7e2a07e6df7c4519.powersync.journeyapps.com"

    // Reference to Supabase client
    private var supabase: SupabaseClient { SupabaseManager.shared.client }

    // MARK: - PowerSyncBackendConnectorProtocol

    /// Fetch credentials for PowerSync using Supabase JWT
    func fetchCredentials() async throws -> PowerSyncCredentials? {
        // First, try to refresh the session to get a fresh token
        // This prevents "JWT has expired" errors in PowerSync
        do {
            _ = try await supabase.auth.refreshSession()
            print("SupabasePowerSyncConnector: Session refreshed successfully")
        } catch {
            print("SupabasePowerSyncConnector: Could not refresh session: \(error)")
            // Continue - maybe the current token is still valid
        }

        // Get the current Supabase session (now with refreshed token)
        guard let session = supabase.auth.currentSession else {
            print("SupabasePowerSyncConnector: No active session")
            return nil
        }

        // Use the Supabase JWT access token for PowerSync authentication
        return PowerSyncCredentials(
            endpoint: powerSyncURL,
            token: session.accessToken
        )
    }

    /// Upload local changes to Supabase
    /// This is called by PowerSync when there are pending local changes to sync
    func uploadData(database: PowerSyncDatabaseProtocol) async throws {
        // Get the next batch of pending changes
        guard let transaction = try await database.getNextCrudTransaction() else {
            // No changes to upload
            return
        }

        do {
            // Process each pending operation in the transaction
            for op in transaction.crud {
                do {
                    switch op.op {
                    case .put:
                        try await upsertRecord(table: op.table, id: op.id, data: op.opData)
                    case .patch:
                        try await updateRecord(table: op.table, id: op.id, data: op.opData)
                    case .delete:
                        try await deleteRecord(table: op.table, id: op.id)
                    }
                } catch {
                    let errorStr = String(describing: error)
                    // Skip unrecoverable errors (constraint violations, RLS, not found)
                    // These will never succeed on retry — don't block the queue
                    if errorStr.contains("23") || errorStr.contains("violates") ||
                       errorStr.contains("403") || errorStr.contains("404") ||
                       errorStr.contains("PGRST") || errorStr.contains("not_found") {
                        print("SupabasePowerSyncConnector: Skipping unrecoverable error for \(op.op) \(op.table)/\(op.id): \(error)")
                        continue
                    }
                    // Rethrow transient errors (network, timeout) for retry
                    throw error
                }
            }

            // Mark the transaction as complete - this removes it from the upload queue
            try await transaction.complete()

        } catch {
            print("SupabasePowerSyncConnector: Upload error: \(error)")
            // Re-throw the error - PowerSync will retry after a delay
            throw error
        }
    }

    // MARK: - Supabase Operations

    private func upsertRecord(table: String, id: String, data: [String: String?]?) async throws {
        guard let data = data else { return }

        // Build record with id included
        var record: [String: String] = ["id": id]
        for (key, value) in data {
            if let value = value {
                record[key] = value
            }
        }

        try await supabase
            .from(table)
            .upsert(record)
            .execute()

        print("SupabasePowerSyncConnector: Upserted \(table)/\(id)")
    }

    private func updateRecord(table: String, id: String, data: [String: String?]?) async throws {
        guard let data = data else { return }

        // Build record without nil values
        var record: [String: String] = [:]
        for (key, value) in data {
            if let value = value {
                record[key] = value
            }
        }

        try await supabase
            .from(table)
            .update(record)
            .eq("id", value: id)
            .execute()

        print("SupabasePowerSyncConnector: Updated \(table)/\(id)")
    }

    private func deleteRecord(table: String, id: String) async throws {
        try await supabase
            .from(table)
            .delete()
            .eq("id", value: id)
            .execute()

        print("SupabasePowerSyncConnector: Deleted \(table)/\(id)")
    }
}

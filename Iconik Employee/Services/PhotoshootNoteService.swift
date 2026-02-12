//
//  PhotoshootNoteService.swift
//  Iconik Employee
//
//  Created on 2026-02-07
//  Service for managing photoshoot notes in Supabase
//  Enables standalone note submission without daily reports
//

import Foundation
import Supabase
import UIKit
import Photos

/// Service for managing photoshoot notes with Supabase backend
/// Supports offline-first with AppStorage and syncs to server
actor PhotoshootNoteService {
    static let shared = PhotoshootNoteService()

    // MARK: - Dependencies

    private let supabase = SupabaseManager.shared.client

    // MARK: - Initialization

    private init() {}

    // MARK: - Create/Update

    /// Save note to Supabase (insert or update)
    /// - Parameter note: The note to save
    /// - Returns: Updated note with sync status
    func saveNote(_ note: PhotoshootNote, organizationID: String) async throws -> PhotoshootNote {
        print("📝 PhotoshootNoteService: Saving note \(note.id)")

        // Get current user
        guard let currentUser = await SupabaseAuthService.shared.currentUser else {
            throw PhotoshootNoteError.notAuthenticated
        }

        // Upload any new photos that haven't been uploaded yet
        let uploadedPhotoURLs: [String]
        if !note.photoURLs.isEmpty {
            // Photos already uploaded (URLs exist)
            uploadedPhotoURLs = note.photoURLs
        } else {
            // No photos to upload
            uploadedPhotoURLs = []
        }

        // Prepare payload for Supabase
        var payload: [String: AnyJSON] = [
            "id": .string(note.id.uuidString.lowercased()),
            "date": .string(ISO8601DateFormatter().string(from: note.timestamp)),
            "photographer_id": .string(currentUser.id.uuidString.lowercased()),
            "photographer_name": .string(note.photographerName),
            "organization_id": .string(organizationID),
            "school": .string(note.school),
            "shoot_type": .string(note.shootType.isEmpty ? "photoshoot" : note.shootType),
            "notes": .string(note.noteText),
            "photo_urls": .array(uploadedPhotoURLs.map { .string($0) }),
            "status": .string(note.status.rawValue)
        ]

        // Add optional fields
        if let submittedAt = note.submittedAt {
            payload["submitted_at"] = .string(ISO8601DateFormatter().string(from: submittedAt))
        }
        if let dailyReportId = note.dailyReportId {
            payload["daily_report_id"] = .string(dailyReportId)
        }

        // Upsert (insert or update)
        do {
            try await supabase
                .from("photoshoot_notes")
                .upsert(payload)
                .execute()

            print("✅ PhotoshootNoteService: Note saved successfully")

            // Return updated note with sync status
            var updatedNote = note
            updatedNote.syncedToServer = true
            updatedNote.lastSyncedAt = Date()
            updatedNote.photographerID = currentUser.id.uuidString.lowercased()

            return updatedNote
        } catch {
            print("❌ PhotoshootNoteService: Failed to save note - \(error.localizedDescription)")
            throw PhotoshootNoteError.saveFailed(error.localizedDescription)
        }
    }

    /// Submit note (marks as submitted and saves)
    /// - Parameter note: The note to submit
    /// - Returns: Updated note with submitted status
    func submitNote(_ note: PhotoshootNote, organizationID: String) async throws -> PhotoshootNote {
        print("📤 PhotoshootNoteService: Submitting note \(note.id)")

        // Validate note has required fields
        guard !note.school.isEmpty else {
            throw PhotoshootNoteError.missingSchool
        }
        guard !note.noteText.isEmpty else {
            throw PhotoshootNoteError.missingNotes
        }

        var submittedNote = note
        submittedNote.status = .submitted
        submittedNote.submittedAt = Date()

        return try await saveNote(submittedNote, organizationID: organizationID)
    }

    // MARK: - Read

    /// Fetch notes for a photographer within a date range
    /// - Parameters:
    ///   - photographerID: UUID of the photographer
    ///   - startDate: Start date of range
    ///   - endDate: End date of range
    /// - Returns: Array of notes
    func fetchNotes(photographerID: String, startDate: Date, endDate: Date) async throws -> [PhotoshootNote] {
        print("📂 PhotoshootNoteService: Fetching notes for \(photographerID)")

        let dateFormatter = ISO8601DateFormatter()

        do {
            let response: PostgrestResponse<[PhotoshootNoteDTO]> = try await supabase
                .from("photoshoot_notes")
                .select()
                .eq("photographer_id", value: photographerID.lowercased())
                .gte("date", value: dateFormatter.string(from: startDate))
                .lte("date", value: dateFormatter.string(from: endDate))
                .is("deleted_at", value: true)
                .order("date", ascending: false)
                .execute()

            // Convert DTOs to PhotoshootNote models
            let notes = response.value.compactMap { dto in
                dto.toPhotoShootNote()
            }

            print("✅ PhotoshootNoteService: Fetched \(notes.count) notes")
            return notes
        } catch {
            print("❌ PhotoshootNoteService: Failed to fetch notes - \(error.localizedDescription)")
            throw PhotoshootNoteError.fetchFailed(error.localizedDescription)
        }
    }

    /// Fetch a single note by ID
    /// - Parameter id: UUID of the note
    /// - Returns: The note, or nil if not found
    func fetchNote(id: UUID) async throws -> PhotoshootNote? {
        print("📂 PhotoshootNoteService: Fetching note \(id)")

        do {
            let response: PostgrestResponse<PhotoshootNoteDTO> = try await supabase
                .from("photoshoot_notes")
                .select()
                .eq("id", value: id.uuidString.lowercased())
                .single()
                .execute()

            let note = response.value.toPhotoShootNote()
            print("✅ PhotoshootNoteService: Fetched note \(id)")
            return note
        } catch {
            print("❌ PhotoshootNoteService: Failed to fetch note - \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Delete

    /// Soft-delete a note
    /// - Parameter id: UUID of the note to delete
    func deleteNote(id: UUID) async throws {
        print("🗑️ PhotoshootNoteService: Deleting note \(id)")

        do {
            try await supabase
                .from("photoshoot_notes")
                .update(["deleted_at": ISO8601DateFormatter().string(from: Date())])
                .eq("id", value: id.uuidString.lowercased())
                .execute()

            print("✅ PhotoshootNoteService: Note deleted successfully")
        } catch {
            print("❌ PhotoshootNoteService: Failed to delete note - \(error.localizedDescription)")
            throw PhotoshootNoteError.deleteFailed(error.localizedDescription)
        }
    }

    // MARK: - Photo Upload

    /// Upload photo to Supabase Storage
    /// - Parameter imageData: JPEG image data
    /// - Returns: Public URL of uploaded photo
    func uploadPhoto(_ imageData: Data) async throws -> String {
        print("📸 PhotoshootNoteService: Uploading photo")

        let fileName = "photoshoot_\(UUID().uuidString).jpg"

        do {
            // Upload to Supabase Storage
            _ = try await supabase.storage
                .from("daily-report-photos")
                .upload(
                    path: fileName,
                    file: imageData,
                    options: FileOptions(contentType: "image/jpeg")
                )

            // Get signed URL (valid for 1 year)
            let signedURL = try await supabase.storage
                .from("daily-report-photos")
                .createSignedURL(path: fileName, expiresIn: 31536000)

            print("✅ PhotoshootNoteService: Photo uploaded successfully")
            return signedURL.absoluteString
        } catch {
            print("❌ PhotoshootNoteService: Failed to upload photo - \(error.localizedDescription)")
            throw PhotoshootNoteError.uploadFailed(error.localizedDescription)
        }
    }

    // MARK: - Attach to Daily Report

    /// Link a note to a daily report
    /// - Parameters:
    ///   - noteId: UUID of the note
    ///   - reportId: String ID of the daily report
    func attachToReport(noteId: UUID, reportId: String) async throws {
        print("🔗 PhotoshootNoteService: Attaching note \(noteId) to report \(reportId)")

        do {
            try await supabase
                .from("photoshoot_notes")
                .update(["daily_report_id": reportId])
                .eq("id", value: noteId.uuidString.lowercased())
                .execute()

            print("✅ PhotoshootNoteService: Note attached to report successfully")
        } catch {
            print("❌ PhotoshootNoteService: Failed to attach note to report - \(error.localizedDescription)")
            throw PhotoshootNoteError.attachFailed(error.localizedDescription)
        }
    }
}

// MARK: - Data Transfer Objects

/// DTO for decoding photoshoot notes from Supabase
private struct PhotoshootNoteDTO: Codable {
    let id: String
    let created_at: String?
    let updated_at: String?
    let date: String
    let photographer_id: String
    let photographer_name: String
    let organization_id: String
    let school: String
    let shoot_type: String
    let notes: String
    let photo_urls: [String]
    let status: String
    let submitted_at: String?
    let daily_report_id: String?
    let deleted_at: String?

    func toPhotoShootNote() -> PhotoshootNote? {
        guard let noteId = UUID(uuidString: id) else {
            print("⚠️ Invalid UUID for note: \(id)")
            return nil
        }

        let dateFormatter = ISO8601DateFormatter()
        guard let timestamp = dateFormatter.date(from: date) else {
            print("⚠️ Invalid date for note: \(date)")
            return nil
        }

        let submittedDate = submitted_at != nil ? dateFormatter.date(from: submitted_at!) : nil

        let noteStatus: PhotoshootNote.NoteStatus = status == "submitted" ? .submitted : .draft

        return PhotoshootNote(
            id: noteId,
            timestamp: timestamp,
            school: school,
            noteText: notes,
            photoURLs: photo_urls,
            status: noteStatus,
            submittedAt: submittedDate,
            dailyReportId: daily_report_id,
            syncedToServer: true,
            lastSyncedAt: Date(),
            photographerName: photographer_name,
            photographerID: photographer_id,
            shootType: shoot_type
        )
    }
}

// MARK: - Errors

enum PhotoshootNoteError: LocalizedError {
    case notAuthenticated
    case missingSchool
    case missingNotes
    case saveFailed(String)
    case fetchFailed(String)
    case deleteFailed(String)
    case uploadFailed(String)
    case attachFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to save notes"
        case .missingSchool:
            return "Please select a school before submitting"
        case .missingNotes:
            return "Please add some notes before submitting"
        case .saveFailed(let message):
            return "Failed to save note: \(message)"
        case .fetchFailed(let message):
            return "Failed to load notes: \(message)"
        case .deleteFailed(let message):
            return "Failed to delete note: \(message)"
        case .uploadFailed(let message):
            return "Failed to upload photo: \(message)"
        case .attachFailed(let message):
            return "Failed to attach note to report: \(message)"
        }
    }
}

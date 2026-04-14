//
//  SubjectModel.swift
//  Iconik Employee
//
//  FPSubject — maps directly to Production's `subjects` table via PowerSync.
//  Single source of truth: iPad reads/writes subjects directly, no roster_entries duplication.
//  Image numbers use semicolon separator (Production convention), not comma (Captura convention).
//

import Foundation

// MARK: - FP Subject Model (matches Production subjects table)

struct FPSubject: Identifiable, Hashable {
    var id: UUID
    var galleryId: String               // REQUIRED — FK to Production galleries
    var organizationId: String

    // Name
    var firstName: String
    var lastName: String

    // School/roster info
    var grade: String
    var teacher: String
    var homeroom: String
    var studentId: String
    var rosterId: String                // Dedicated roster/jersey ID

    // Sports fields
    var jerseyNumber: String
    var sport: String                   // Maps from RosterEntry.groupName
    var position: String

    // Organization/event
    var organizationName: String

    // Contact
    var email: String
    var phone: String

    // Status
    var imageCount: Int
    var isAbsent: Bool
    var isPhotographed: Bool
    var needsRetake: Bool
    var checkedInAt: String?

    // Image numbers — SEMICOLON separated (Production convention)
    var imageNumbers: String
    var notes: String

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // Soft locking (multi-device editing)
    var lockedBy: UUID?
    var lockedByName: String?
    var lockedAt: Date?

    // MARK: - Init

    init(
        id: UUID = UUID(),
        galleryId: String,
        organizationId: String = "",
        firstName: String = "",
        lastName: String = "",
        grade: String = "",
        teacher: String = "",
        homeroom: String = "",
        studentId: String = "",
        rosterId: String = "",
        jerseyNumber: String = "",
        sport: String = "",
        position: String = "",
        organizationName: String = "",
        email: String = "",
        phone: String = "",
        imageCount: Int = 0,
        isAbsent: Bool = false,
        isPhotographed: Bool = false,
        needsRetake: Bool = false,
        checkedInAt: String? = nil,
        imageNumbers: String = "",
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lockedBy: UUID? = nil,
        lockedByName: String? = nil,
        lockedAt: Date? = nil
    ) {
        self.id = id
        self.galleryId = galleryId
        self.organizationId = organizationId
        self.firstName = firstName
        self.lastName = lastName
        self.grade = grade
        self.teacher = teacher
        self.homeroom = homeroom
        self.studentId = studentId
        self.rosterId = rosterId
        self.jerseyNumber = jerseyNumber
        self.sport = sport
        self.position = position
        self.organizationName = organizationName
        self.email = email
        self.phone = phone
        self.imageCount = imageCount
        self.isAbsent = isAbsent
        self.isPhotographed = isPhotographed
        self.needsRetake = needsRetake
        self.checkedInAt = checkedInAt
        self.imageNumbers = imageNumbers
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lockedBy = lockedBy
        self.lockedByName = lockedByName
        self.lockedAt = lockedAt
    }

    // MARK: - Locking Helpers

    /// Whether this subject is currently locked (lock expires after 2 minutes)
    var isLocked: Bool {
        guard let lockedAt = lockedAt else { return false }
        return Date().timeIntervalSince(lockedAt) < 120
    }

    /// Check if locked by a specific user
    func isLockedBy(userId: UUID) -> Bool {
        return lockedBy == userId && isLocked
    }

    /// Check if locked by a different device
    func isLockedByOtherDevice(editorIdentifier: String, userId: UUID?) -> Bool {
        guard isLocked else { return false }
        if let name = lockedByName {
            return name != editorIdentifier
        }
        guard let lockedBy = lockedBy, let userId = userId else { return false }
        return lockedBy != userId
    }

    // MARK: - Image Number Helpers (semicolon-separated)

    /// Parsed image numbers as array of ints
    var parsedImageNumbers: [Int] {
        imageNumbers
            .split(separator: ";")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Add an image number (appends with semicolon separator)
    mutating func addImageNumber(_ num: Int) {
        if imageNumbers.isEmpty {
            imageNumbers = "\(num)"
        } else {
            imageNumbers += ";\(num)"
        }
    }

    /// Remove an image number
    mutating func removeImageNumber(_ num: Int) {
        let nums = imageNumbers
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0 != "\(num)" }
        imageNumbers = nums.joined(separator: ";")
    }

    /// Display name (lastName, or "Blank" if empty)
    var displayName: String {
        if lastName.trimmingCharacters(in: .whitespaces).isEmpty {
            return rosterId.isEmpty ? "Blank" : "ID \(rosterId)"
        }
        return lastName
    }

    /// Whether this is a "blank" placeholder subject (empty last name)
    var isBlank: Bool {
        lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

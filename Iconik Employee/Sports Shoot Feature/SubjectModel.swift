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

    // Organization / event
    var organizationName: String
    var year: String
    var subjectType: String
    var title: String
    var referenceNumber: String
    var photographer: String
    var photoSessionDate: String
    var expirationDate: String

    // Contact
    var email: String
    var phone: String
    var phone2: String
    var address1: String
    var address2: String
    var city: String
    var state: String
    var zip: String
    var country: String

    // Family
    var mother: String
    var father: String

    // Online ordering
    var onlineCode: String

    // Additional
    var personalization: String
    var discountCode: String

    // Custom fields (custom1 through custom20)
    var custom1: String
    var custom2: String
    var custom3: String
    var custom4: String
    var custom5: String
    var custom6: String
    var custom7: String
    var custom8: String
    var custom9: String
    var custom10: String
    var custom11: String
    var custom12: String
    var custom13: String
    var custom14: String
    var custom15: String
    var custom16: String
    var custom17: String
    var custom18: String
    var custom19: String
    var custom20: String

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
        year: String = "",
        subjectType: String = "",
        title: String = "",
        referenceNumber: String = "",
        photographer: String = "",
        photoSessionDate: String = "",
        expirationDate: String = "",
        email: String = "",
        phone: String = "",
        phone2: String = "",
        address1: String = "",
        address2: String = "",
        city: String = "",
        state: String = "",
        zip: String = "",
        country: String = "",
        mother: String = "",
        father: String = "",
        onlineCode: String = "",
        personalization: String = "",
        discountCode: String = "",
        custom1: String = "",
        custom2: String = "",
        custom3: String = "",
        custom4: String = "",
        custom5: String = "",
        custom6: String = "",
        custom7: String = "",
        custom8: String = "",
        custom9: String = "",
        custom10: String = "",
        custom11: String = "",
        custom12: String = "",
        custom13: String = "",
        custom14: String = "",
        custom15: String = "",
        custom16: String = "",
        custom17: String = "",
        custom18: String = "",
        custom19: String = "",
        custom20: String = "",
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
        self.year = year
        self.subjectType = subjectType
        self.title = title
        self.referenceNumber = referenceNumber
        self.photographer = photographer
        self.photoSessionDate = photoSessionDate
        self.expirationDate = expirationDate
        self.email = email
        self.phone = phone
        self.phone2 = phone2
        self.address1 = address1
        self.address2 = address2
        self.city = city
        self.state = state
        self.zip = zip
        self.country = country
        self.mother = mother
        self.father = father
        self.onlineCode = onlineCode
        self.personalization = personalization
        self.discountCode = discountCode
        self.custom1 = custom1
        self.custom2 = custom2
        self.custom3 = custom3
        self.custom4 = custom4
        self.custom5 = custom5
        self.custom6 = custom6
        self.custom7 = custom7
        self.custom8 = custom8
        self.custom9 = custom9
        self.custom10 = custom10
        self.custom11 = custom11
        self.custom12 = custom12
        self.custom13 = custom13
        self.custom14 = custom14
        self.custom15 = custom15
        self.custom16 = custom16
        self.custom17 = custom17
        self.custom18 = custom18
        self.custom19 = custom19
        self.custom20 = custom20
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

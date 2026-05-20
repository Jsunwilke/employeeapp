//
//  FPSubjectWireCoding.swift
//  Iconik Employee
//
//  FROM_SCRATCH_ARCHITECTURE.md §13 H1.12 — wire-dict round-trip for the
//  SubscriptionCache persistence layer (PHASE_AC_PLAN.md §13-§17 scope
//  expansion). Added 2026-05-20.
//
//  The SubscriptionCache stores FPSubject values in memory. The disk
//  persistence layer stores subjects as wire-dict JSON (the same shape
//  state_sync delivers over the wire). This extension provides the
//  toWireDict() helper that produces the wire-dict for a given FPSubject,
//  mirroring SubscriptionCache._parseSubjectFromWire's field mapping
//  exactly so the round-trip is lossless.
//
//  Why wire-dict on disk rather than FPSubject directly:
//    - The wire-dict shape is the existing stable contract used by
//      state_sync, broadcasts, and SubscriptionCache._parseSubjectFromWire.
//      Reusing it means hydration on cold launch shares the same parser
//      as hydration from state_sync — no duplicate parsing code paths.
//    - FPSubject is not Codable (verified via grep at trace time). Adding
//      Codable conformance would tie the on-disk shape to the struct
//      definition, requiring schema migration on every FPSubject field
//      change. The wire-dict shape is the wire-protocol shape, which has
//      its own change discipline (§6.1 PROTOCOL_VERSION bumps).
//    - Mirror-of-mirror principle: disk mirrors in-memory; in-memory
//      mirrors the wire. Both translations go through the same parser.
//
//  Field set must match _parseSubjectFromWire in SubscriptionCache.swift
//  exactly. The keys here use snake_case to match the wire format. When
//  a new field is added to FPSubject + state-sync wire-protocol, BOTH
//  this encoder AND _parseSubjectFromWire must update in lockstep — the
//  enforcement is the round-trip test in SubscriptionCacheTests.swift.
//

import Foundation

extension FPSubject {

    /// Produce the wire-dict representation of this FPSubject. Inverse of
    /// SubscriptionCache._parseSubjectFromWire — applying parse(toWireDict(s))
    /// returns an FPSubject equal to s for all production-shape inputs.
    ///
    /// Boolean fields encode as Int 0/1 to match the wire-format convention
    /// (PowerSync's SQLite-as-text storage uses 0/1; the parser accepts
    /// Bool / Int / String for boolean fields, but the canonical wire
    /// shape is Int 0/1).
    ///
    /// Dates encode as ISO8601 strings via ISO8601DateFormatter (no
    /// fractional seconds — matches the wire format).
    func toWireDict() -> [String: Any] {
        let isoFormatter = ISO8601DateFormatter()
        var dict: [String: Any] = [
            "id": id.uuidString.lowercased(),
            "gallery_id": galleryId,
            "organization_id": organizationId,
            "first_name": firstName,
            "last_name": lastName,
            "grade": grade,
            "teacher": teacher,
            "homeroom": homeroom,
            "student_id": studentId,
            "roster_id": rosterId,
            "jersey_number": jerseyNumber,
            "sport": sport,
            "position": position,
            "organization_name": organizationName,
            "year": year,
            "subject_type": subjectType,
            "title": title,
            "reference_number": referenceNumber,
            "photographer": photographer,
            "photo_session_date": photoSessionDate,
            "expiration_date": expirationDate,
            "email": email,
            "phone": phone,
            "phone2": phone2,
            "address1": address1,
            "address2": address2,
            "city": city,
            "state": state,
            "zip": zip,
            "country": country,
            "mother": mother,
            "father": father,
            "online_code": onlineCode,
            "personalization": personalization,
            "discount_code": discountCode,
            "custom1": custom1,
            "custom2": custom2,
            "custom3": custom3,
            "custom4": custom4,
            "custom5": custom5,
            "custom6": custom6,
            "custom7": custom7,
            "custom8": custom8,
            "custom9": custom9,
            "custom10": custom10,
            "custom11": custom11,
            "custom12": custom12,
            "custom13": custom13,
            "custom14": custom14,
            "custom15": custom15,
            "custom16": custom16,
            "custom17": custom17,
            "custom18": custom18,
            "custom19": custom19,
            "custom20": custom20,
            "image_count": imageCount,
            "is_absent": isAbsent ? 1 : 0,
            "is_photographed": isPhotographed ? 1 : 0,
            "needs_retake": needsRetake ? 1 : 0,
            "image_numbers": imageNumbers,
            "notes": notes,
            "created_at": isoFormatter.string(from: createdAt),
            "updated_at": isoFormatter.string(from: updatedAt),
        ]
        // Optional fields — only include when present so the wire-dict
        // round-trip preserves nil vs empty-string distinctions where
        // applicable. The parser reads stringOpt for these.
        if let checkedInAt = checkedInAt { dict["checked_in_at"] = checkedInAt }
        if let lockedBy = lockedBy { dict["locked_by"] = lockedBy.uuidString.lowercased() }
        if let lockedByName = lockedByName { dict["locked_by_name"] = lockedByName }
        if let lockedAt = lockedAt { dict["locked_at"] = isoFormatter.string(from: lockedAt) }
        return dict
    }
}

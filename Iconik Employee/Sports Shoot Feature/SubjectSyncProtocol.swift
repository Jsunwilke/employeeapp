//
//  SubjectSyncProtocol.swift
//  Iconik Employee
//
//  Wire protocol for the iPad ↔ Surface subject-sync rewrite. Mirrors the
//  TypeScript file at src/data/sync/subject-sync-protocol.ts on the Mac side.
//  Both sides MUST stay in lockstep on field names, shapes, and the
//  reconciliation hash function (compute_subjects_hash).
//
//  See IPAD_SURFACE_SYNC_REWRITE.md §5.5.
//
//  Validation strategy: every inbound message is decoded via Codable. Decoding
//  failure is treated as a protocol violation — the message is dropped and a
//  structured event is emitted (never a silent drop, per §4.7).
//

import Foundation

// MARK: - Protocol version

let kSubjectSyncProtocolVersion = 1

// MARK: - Message types

enum SubjectSyncMessageType: String, Codable {
    case subjectUpdate = "subject.update"
    case subjectCreate = "subject.create"
    case subjectDelete = "subject.delete"
    case subjectAck    = "subject.ack"
    case subjectSummary = "subject.summary"
    case syncHello     = "sync.hello"
    case syncHeartbeat = "sync.heartbeat"
}

// MARK: - Subject fields (mirrors SubjectFields Zod schema)

/// All subject fields the protocol can carry. All optional — partial updates
/// only set the fields that changed. Names mirror Supabase column names.
struct SubjectSyncFields: Codable, Equatable {
    var firstName: String?
    var lastName: String?
    var grade: String?
    var teacher: String?
    var homeroom: String?
    var studentId: String?
    var rosterId: String?
    var jerseyNumber: String?
    var sport: String?
    var position: String?
    var email: String?
    var phone: String?
    var notes: String?
    var imageNumbers: String?
    var isAbsent: Bool?
    var needsRetake: Bool?
    var isPhotographed: Bool?
    var checkedInAt: String?           // ISO8601
    var primaryImageUrl: String?
    var thumbnailUrl: String?

    // Create-only — present in subject.create messages, optional elsewhere.
    var organizationId: String?
    var galleryId: String?

    enum CodingKeys: String, CodingKey {
        case firstName       = "first_name"
        case lastName        = "last_name"
        case grade
        case teacher
        case homeroom
        case studentId       = "student_id"
        case rosterId        = "roster_id"
        case jerseyNumber    = "jersey_number"
        case sport
        case position
        case email
        case phone
        case notes
        case imageNumbers    = "image_numbers"
        case isAbsent        = "is_absent"
        case needsRetake     = "needs_retake"
        case isPhotographed  = "is_photographed"
        case checkedInAt     = "checked_in_at"
        case primaryImageUrl = "primary_image_url"
        case thumbnailUrl    = "thumbnail_url"
        case organizationId  = "organization_id"
        case galleryId       = "gallery_id"
    }

    /// The list of field names that are present (non-nil). Used by the event
    /// log so we can attribute "what changed" without dumping values.
    var fieldsTouched: [String] {
        var names: [String] = []
        if firstName       != nil { names.append("first_name") }
        if lastName        != nil { names.append("last_name") }
        if grade           != nil { names.append("grade") }
        if teacher         != nil { names.append("teacher") }
        if homeroom        != nil { names.append("homeroom") }
        if studentId       != nil { names.append("student_id") }
        if rosterId        != nil { names.append("roster_id") }
        if jerseyNumber    != nil { names.append("jersey_number") }
        if sport           != nil { names.append("sport") }
        if position        != nil { names.append("position") }
        if email           != nil { names.append("email") }
        if phone           != nil { names.append("phone") }
        if notes           != nil { names.append("notes") }
        if imageNumbers    != nil { names.append("image_numbers") }
        if isAbsent        != nil { names.append("is_absent") }
        if needsRetake     != nil { names.append("needs_retake") }
        if isPhotographed  != nil { names.append("is_photographed") }
        if checkedInAt     != nil { names.append("checked_in_at") }
        if primaryImageUrl != nil { names.append("primary_image_url") }
        if thumbnailUrl    != nil { names.append("thumbnail_url") }
        if organizationId  != nil { names.append("organization_id") }
        if galleryId       != nil { names.append("gallery_id") }
        return names
    }
}

// MARK: - Discrete message envelopes

struct SubjectUpdateEnvelope: Codable {
    let type: SubjectSyncMessageType  // .subjectUpdate
    let v: Int
    let idempotencyKey: String        // UUID
    let seq: Int
    let senderDeviceId: String
    let galleryId: String             // UUID
    let subjectId: String             // UUID
    let fields: SubjectSyncFields
    let ts: String                    // ISO8601

    enum CodingKeys: String, CodingKey {
        case type, v, seq, fields, ts
        case idempotencyKey = "idempotency_key"
        case senderDeviceId = "sender_device_id"
        case galleryId      = "gallery_id"
        case subjectId      = "subject_id"
    }
}

struct SubjectCreateEnvelope: Codable {
    let type: SubjectSyncMessageType  // .subjectCreate
    let v: Int
    let idempotencyKey: String
    let seq: Int
    let senderDeviceId: String
    let galleryId: String
    let subjectId: String
    let fields: SubjectSyncFields
    let ts: String

    enum CodingKeys: String, CodingKey {
        case type, v, seq, fields, ts
        case idempotencyKey = "idempotency_key"
        case senderDeviceId = "sender_device_id"
        case galleryId      = "gallery_id"
        case subjectId      = "subject_id"
    }
}

struct SubjectDeleteEnvelope: Codable {
    let type: SubjectSyncMessageType  // .subjectDelete
    let v: Int
    let idempotencyKey: String
    let seq: Int
    let senderDeviceId: String
    let galleryId: String
    let subjectId: String
    let ts: String

    enum CodingKeys: String, CodingKey {
        case type, v, seq, ts
        case idempotencyKey = "idempotency_key"
        case senderDeviceId = "sender_device_id"
        case galleryId      = "gallery_id"
        case subjectId      = "subject_id"
    }
}

struct SubjectAckEnvelope: Codable {
    let type: SubjectSyncMessageType  // .subjectAck
    let v: Int
    let idempotencyKey: String
    let senderDeviceId: String
    let galleryId: String
    let outcome: String               // "committed" | "rejected"
    let errorCode: String?
    let errorMessage: String?
    let ts: String

    enum CodingKeys: String, CodingKey {
        case type, v, outcome, ts
        case idempotencyKey = "idempotency_key"
        case senderDeviceId = "sender_device_id"
        case galleryId      = "gallery_id"
        case errorCode      = "error_code"
        case errorMessage   = "error_message"
    }
}

struct SubjectSummaryEnvelope: Codable {
    let type: SubjectSyncMessageType  // .subjectSummary
    let v: Int
    let senderDeviceId: String
    let galleryId: String
    let subjectCount: Int
    let hash: String                  // FNV-1a 32-bit, see compute_subjects_hash
    let ts: String

    enum CodingKeys: String, CodingKey {
        case type, v, hash, ts
        case senderDeviceId = "sender_device_id"
        case galleryId      = "gallery_id"
        case subjectCount   = "subject_count"
    }
}

struct SyncHelloEnvelope: Codable {
    let type: SubjectSyncMessageType  // .syncHello
    let v: Int
    let senderDeviceId: String
    let deviceName: String
    let mode: String                  // "surface" | "ipad"
    let lastSeq: Int?

    enum CodingKeys: String, CodingKey {
        case type, v, mode
        case senderDeviceId = "sender_device_id"
        case deviceName     = "device_name"
        case lastSeq        = "last_seq"
    }
}

struct SyncHeartbeatEnvelope: Codable {
    let type: SubjectSyncMessageType  // .syncHeartbeat
    let v: Int
    let senderDeviceId: String
    let ts: String

    enum CodingKeys: String, CodingKey {
        case type, v, ts
        case senderDeviceId = "sender_device_id"
    }
}

// MARK: - Discriminated union

enum SubjectSyncMessage {
    case update(SubjectUpdateEnvelope)
    case create(SubjectCreateEnvelope)
    case delete(SubjectDeleteEnvelope)
    case ack(SubjectAckEnvelope)
    case summary(SubjectSummaryEnvelope)
    case hello(SyncHelloEnvelope)
    case heartbeat(SyncHeartbeatEnvelope)
}

// MARK: - Validation result

enum SubjectSyncValidation {
    case ok(SubjectSyncMessage)
    case rejected(reason: String)
}

// MARK: - Validation entry point

enum SubjectSyncProtocolError: Error {
    case invalidJSON
    case missingType
    case unknownType(String)
    case versionMismatch(Int)
    case invalidUUID(String)
    case decodeFailed(String)
}

/// Single entry point for parsing inbound messages. Returns a tagged result so
/// callers can never accidentally use an unvalidated message. Mirrors `validate`
/// in subject-sync-protocol.ts.
func validateSubjectSyncMessage(_ raw: Data) -> SubjectSyncValidation {
    let decoder = JSONDecoder()
    // First peek at `type` to dispatch the right envelope. We can't use a
    // single discriminated decode like Zod because Codable doesn't have a
    // direct equivalent, so we route by the discriminator.
    guard let any = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
        return .rejected(reason: "invalid_json")
    }
    guard let typeRaw = any["type"] as? String else {
        return .rejected(reason: "missing_type")
    }
    guard let typed = SubjectSyncMessageType(rawValue: typeRaw) else {
        return .rejected(reason: "unknown_type:\(typeRaw)")
    }
    if let v = any["v"] as? Int, v != kSubjectSyncProtocolVersion {
        return .rejected(reason: "version_mismatch:\(v)")
    }
    do {
        switch typed {
        case .subjectUpdate:
            return .ok(.update(try decoder.decode(SubjectUpdateEnvelope.self, from: raw)))
        case .subjectCreate:
            return .ok(.create(try decoder.decode(SubjectCreateEnvelope.self, from: raw)))
        case .subjectDelete:
            return .ok(.delete(try decoder.decode(SubjectDeleteEnvelope.self, from: raw)))
        case .subjectAck:
            return .ok(.ack(try decoder.decode(SubjectAckEnvelope.self, from: raw)))
        case .subjectSummary:
            return .ok(.summary(try decoder.decode(SubjectSummaryEnvelope.self, from: raw)))
        case .syncHello:
            return .ok(.hello(try decoder.decode(SyncHelloEnvelope.self, from: raw)))
        case .syncHeartbeat:
            return .ok(.heartbeat(try decoder.decode(SyncHeartbeatEnvelope.self, from: raw)))
        }
    } catch {
        return .rejected(reason: "decode_failed:\(error)")
    }
}

// MARK: - Reconciliation hash

/// FNV-1a 32-bit hash over `${id}|${first_name?.lowercased()}|${last_name?.lowercased()}|`
/// after sorting rows by id. MUST produce identical output to the TypeScript
/// `compute_subjects_hash` in subject-sync-protocol.ts. Mismatches between
/// Mac and iPad here will cause spurious "drift" banners — keep both in sync.
struct SubjectsHashRow {
    let id: String
    let firstName: String?
    let lastName: String?
}

func computeSubjectsHash(_ rows: [SubjectsHashRow]) -> String {
    let sorted = rows.sorted { $0.id < $1.id }
    var hash: UInt32 = 0x811c9dc5
    for r in sorted {
        let s = "\(r.id)|\((r.firstName ?? "").lowercased())|\((r.lastName ?? "").lowercased())|"
        for byte in s.unicodeScalars {
            hash ^= UInt32(byte.value & 0xff)
            // FNV-1a 32-bit prime: hash * 0x01000193, modulo 2^32.
            // The TS version uses the equivalent shift form:
            //   hash + ((hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24))
            // We replicate it byte-for-byte to guarantee identical output.
            let h = hash
            hash = h &+ ((h &<< 1) &+ (h &<< 4) &+ (h &<< 7) &+ (h &<< 8) &+ (h &<< 24))
        }
    }
    return String(hash, radix: 16)
}

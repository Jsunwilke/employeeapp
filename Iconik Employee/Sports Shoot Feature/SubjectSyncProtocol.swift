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
    var onlineCode: String?
    var jerseyNumber: String?
    var sport: String?
    var position: String?
    var organizationName: String?
    var year: String?
    var subjectType: String?
    var title: String?
    var referenceNumber: String?
    var photographer: String?
    var photoSessionDate: String?
    var expirationDate: String?
    var email: String?
    var phone: String?
    var phone2: String?
    var address1: String?
    var address2: String?
    var city: String?
    var state: String?
    var zip: String?
    var country: String?
    var mother: String?
    var father: String?
    var personalization: String?
    var discountCode: String?
    var custom1: String?
    var custom2: String?
    var custom3: String?
    var custom4: String?
    var custom5: String?
    var custom6: String?
    var custom7: String?
    var custom8: String?
    var custom9: String?
    var custom10: String?
    var custom11: String?
    var custom12: String?
    var custom13: String?
    var custom14: String?
    var custom15: String?
    var custom16: String?
    var custom17: String?
    var custom18: String?
    var custom19: String?
    var custom20: String?
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
        case onlineCode      = "online_code"
        case jerseyNumber    = "jersey_number"
        case sport
        case position
        case organizationName = "organization_name"
        case year
        case subjectType     = "subject_type"
        case title
        case referenceNumber = "reference_number"
        case photographer
        case photoSessionDate = "photo_session_date"
        case expirationDate  = "expiration_date"
        case email
        case phone
        case phone2
        case address1
        case address2
        case city
        case state
        case zip
        case country
        case mother
        case father
        case personalization
        case discountCode    = "discount_code"
        case custom1, custom2, custom3, custom4, custom5
        case custom6, custom7, custom8, custom9, custom10
        case custom11, custom12, custom13, custom14, custom15
        case custom16, custom17, custom18, custom19, custom20
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
        if firstName        != nil { names.append("first_name") }
        if lastName         != nil { names.append("last_name") }
        if grade            != nil { names.append("grade") }
        if teacher          != nil { names.append("teacher") }
        if homeroom         != nil { names.append("homeroom") }
        if studentId        != nil { names.append("student_id") }
        if rosterId         != nil { names.append("roster_id") }
        if onlineCode       != nil { names.append("online_code") }
        if jerseyNumber     != nil { names.append("jersey_number") }
        if sport            != nil { names.append("sport") }
        if position         != nil { names.append("position") }
        if organizationName != nil { names.append("organization_name") }
        if year             != nil { names.append("year") }
        if subjectType      != nil { names.append("subject_type") }
        if title            != nil { names.append("title") }
        if referenceNumber  != nil { names.append("reference_number") }
        if photographer     != nil { names.append("photographer") }
        if photoSessionDate != nil { names.append("photo_session_date") }
        if expirationDate   != nil { names.append("expiration_date") }
        if email            != nil { names.append("email") }
        if phone            != nil { names.append("phone") }
        if phone2           != nil { names.append("phone2") }
        if address1         != nil { names.append("address1") }
        if address2         != nil { names.append("address2") }
        if city             != nil { names.append("city") }
        if state            != nil { names.append("state") }
        if zip              != nil { names.append("zip") }
        if country          != nil { names.append("country") }
        if mother           != nil { names.append("mother") }
        if father           != nil { names.append("father") }
        if personalization  != nil { names.append("personalization") }
        if discountCode     != nil { names.append("discount_code") }
        for i in 1...20 {
            switch i {
            case 1:  if custom1  != nil { names.append("custom1") }
            case 2:  if custom2  != nil { names.append("custom2") }
            case 3:  if custom3  != nil { names.append("custom3") }
            case 4:  if custom4  != nil { names.append("custom4") }
            case 5:  if custom5  != nil { names.append("custom5") }
            case 6:  if custom6  != nil { names.append("custom6") }
            case 7:  if custom7  != nil { names.append("custom7") }
            case 8:  if custom8  != nil { names.append("custom8") }
            case 9:  if custom9  != nil { names.append("custom9") }
            case 10: if custom10 != nil { names.append("custom10") }
            case 11: if custom11 != nil { names.append("custom11") }
            case 12: if custom12 != nil { names.append("custom12") }
            case 13: if custom13 != nil { names.append("custom13") }
            case 14: if custom14 != nil { names.append("custom14") }
            case 15: if custom15 != nil { names.append("custom15") }
            case 16: if custom16 != nil { names.append("custom16") }
            case 17: if custom17 != nil { names.append("custom17") }
            case 18: if custom18 != nil { names.append("custom18") }
            case 19: if custom19 != nil { names.append("custom19") }
            case 20: if custom20 != nil { names.append("custom20") }
            default: break
            }
        }
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

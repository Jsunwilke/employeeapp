//
//  SubjectSyncOverlay.swift
//  Iconik Employee
//
//  In-memory optimistic overlay for in-flight subject edits on the iPad.
//  Mirror of src/data/sync/subject-sync-overlay.ts on the Mac side. Sits
//  ABOVE the local SQLite store (PowerSync). Views read:
//      let overlaid = overlay.merge(subjectId, baseSubject)
//
//  The overlay is local-only, in-memory, never persisted. Cleared when:
//    1. The PowerSync row matches the overlay (round-trip confirmed).
//    2. The overlay entry is older than 5 minutes (timeout protection).
//    3. The user explicitly discards via the recovery panel.
//
//  Why an overlay instead of writing optimistically to PowerSync? Writing
//  to local SQLite triggers PowerSync's CRUD upload — exactly the dual-write
//  race we are eliminating. The overlay is a pure UI-layer cache.
//
//  See IPAD_SURFACE_SYNC_REWRITE.md §5.4.
//

import Foundation
import Combine

struct SubjectOverlayEntry {
    let fields: SubjectSyncFields
    let appliedAt: Date
    let idempotencyKey: String
    let source: Source

    enum Source: String {
        case localEdit       = "local-edit"
        case remoteWebsocket = "remote-websocket"
    }
}

@MainActor
final class SubjectSyncOverlay: ObservableObject {
    static let shared = SubjectSyncOverlay()

    /// Bumped whenever an overlay entry is added, modified, or cleared.
    /// SwiftUI views can observe this to trigger re-render even though the
    /// dictionary itself is private.
    @Published private(set) var revision: Int = 0

    private var entries: [String: SubjectOverlayEntry] = [:]
    private static let timeoutSeconds: TimeInterval = 5 * 60

    private init() {}

    // MARK: - Mutations

    func apply(
        subjectId: String,
        fields: SubjectSyncFields,
        idempotencyKey: String,
        source: SubjectOverlayEntry.Source = .localEdit
    ) {
        let merged = mergeFields(existing: entries[subjectId]?.fields, incoming: fields)
        entries[subjectId] = SubjectOverlayEntry(
            fields: merged,
            appliedAt: Date(),
            idempotencyKey: idempotencyKey,
            source: source
        )
        revision &+= 1
    }

    /// Clear the overlay if the local row now matches what the overlay was
    /// promising — i.e., the cloud or peer round-trip completed and the
    /// overlay is no longer needed. Returns true if cleared.
    func clearIfMatches(subjectId: String, localSubject: FPSubject) -> Bool {
        guard let entry = entries[subjectId] else { return false }
        if !overlayMatchesSubject(entry.fields, localSubject) { return false }
        entries.removeValue(forKey: subjectId)
        revision &+= 1
        return true
    }

    /// Force-clear an overlay (recovery panel discard).
    @discardableResult
    func discard(subjectId: String) -> Bool {
        guard entries[subjectId] != nil else { return false }
        entries.removeValue(forKey: subjectId)
        revision &+= 1
        return true
    }

    // MARK: - Reads

    func get(subjectId: String) -> SubjectOverlayEntry? {
        guard let entry = entries[subjectId] else { return nil }
        // Lazy expiry — drop stale overlays on read.
        if Date().timeIntervalSince(entry.appliedAt) > SubjectSyncOverlay.timeoutSeconds {
            entries.removeValue(forKey: subjectId)
            revision &+= 1
            return nil
        }
        return entry
    }

    /// Apply the overlay's pending fields onto a base subject. Pure — does
    /// not mutate either input. Returns the base subject unchanged if no
    /// overlay exists for this id.
    func merge(subjectId: String, base: FPSubject) -> FPSubject {
        guard let entry = get(subjectId: subjectId) else { return base }
        var out = base
        let f = entry.fields
        if let v = f.firstName       { out.firstName = v }
        if let v = f.lastName        { out.lastName = v }
        if let v = f.grade           { out.grade = v }
        if let v = f.teacher         { out.teacher = v }
        if let v = f.homeroom        { out.homeroom = v }
        if let v = f.studentId       { out.studentId = v }
        if let v = f.rosterId        { out.rosterId = v }
        if let v = f.jerseyNumber    { out.jerseyNumber = v }
        if let v = f.sport           { out.sport = v }
        if let v = f.position        { out.position = v }
        if let v = f.email           { out.email = v }
        if let v = f.phone           { out.phone = v }
        if let v = f.notes           { out.notes = v }
        if let v = f.imageNumbers    { out.imageNumbers = v }
        if let v = f.isAbsent        { out.isAbsent = v }
        if let v = f.needsRetake     { out.needsRetake = v }
        if let v = f.isPhotographed  { out.isPhotographed = v }
        if let v = f.checkedInAt     { out.checkedInAt = v }
        // primaryImageUrl / thumbnailUrl don't exist on FPSubject yet —
        // leave the protocol field as a no-op until that mapping lands.
        return out
    }

    var size: Int { entries.count }

    func staleEntries(olderThan ageSeconds: TimeInterval) -> [String] {
        let cutoff = Date().addingTimeInterval(-ageSeconds)
        return entries.compactMap { id, entry in
            entry.appliedAt < cutoff ? id : nil
        }
    }

    func allEntries() -> [(subjectId: String, entry: SubjectOverlayEntry)] {
        entries.map { ($0.key, $0.value) }
    }

    // MARK: - Helpers

    private func mergeFields(existing: SubjectSyncFields?, incoming: SubjectSyncFields) -> SubjectSyncFields {
        guard var merged = existing else { return incoming }
        // Incoming wins for any non-nil field.
        if let v = incoming.firstName       { merged.firstName = v }
        if let v = incoming.lastName        { merged.lastName = v }
        if let v = incoming.grade           { merged.grade = v }
        if let v = incoming.teacher         { merged.teacher = v }
        if let v = incoming.homeroom        { merged.homeroom = v }
        if let v = incoming.studentId       { merged.studentId = v }
        if let v = incoming.rosterId        { merged.rosterId = v }
        if let v = incoming.jerseyNumber    { merged.jerseyNumber = v }
        if let v = incoming.sport           { merged.sport = v }
        if let v = incoming.position        { merged.position = v }
        if let v = incoming.email           { merged.email = v }
        if let v = incoming.phone           { merged.phone = v }
        if let v = incoming.notes           { merged.notes = v }
        if let v = incoming.imageNumbers    { merged.imageNumbers = v }
        if let v = incoming.isAbsent        { merged.isAbsent = v }
        if let v = incoming.needsRetake     { merged.needsRetake = v }
        if let v = incoming.isPhotographed  { merged.isPhotographed = v }
        if let v = incoming.checkedInAt     { merged.checkedInAt = v }
        if let v = incoming.primaryImageUrl { merged.primaryImageUrl = v }
        if let v = incoming.thumbnailUrl    { merged.thumbnailUrl = v }
        if let v = incoming.organizationId  { merged.organizationId = v }
        if let v = incoming.galleryId       { merged.galleryId = v }
        return merged
    }

    private func overlayMatchesSubject(_ fields: SubjectSyncFields, _ s: FPSubject) -> Bool {
        if let v = fields.firstName,      v != s.firstName    { return false }
        if let v = fields.lastName,       v != s.lastName     { return false }
        if let v = fields.grade,          v != s.grade        { return false }
        if let v = fields.teacher,        v != s.teacher      { return false }
        if let v = fields.homeroom,       v != s.homeroom     { return false }
        if let v = fields.studentId,      v != s.studentId    { return false }
        if let v = fields.rosterId,       v != s.rosterId     { return false }
        if let v = fields.jerseyNumber,   v != s.jerseyNumber { return false }
        if let v = fields.sport,          v != s.sport        { return false }
        if let v = fields.position,       v != s.position     { return false }
        if let v = fields.email,          v != s.email        { return false }
        if let v = fields.phone,          v != s.phone        { return false }
        if let v = fields.notes,          v != s.notes        { return false }
        if let v = fields.imageNumbers,   v != s.imageNumbers { return false }
        if let v = fields.isAbsent,       v != s.isAbsent     { return false }
        if let v = fields.needsRetake,    v != s.needsRetake  { return false }
        if let v = fields.isPhotographed, v != s.isPhotographed { return false }
        if let v = fields.checkedInAt,    v != s.checkedInAt  { return false }
        return true
    }
}

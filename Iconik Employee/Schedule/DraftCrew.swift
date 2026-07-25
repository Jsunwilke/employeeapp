//  DraftCrew.swift
//  Iconik Employee — the one place a draft's crew is dropped
//
//  PUB.1 (2026-07-25). Photographers now see UNPUBLISHED sessions so they know
//  what work is coming, and a draft never shows who is on it — not other
//  people's assignment, not your own (decision P2). A draft says what work is
//  coming; it is not a commitment to anyone until it is published, and hiding
//  your own name too is what keeps "My Shifts" meaning one thing: what has
//  actually been announced to you.
//
//  WHY ONE HELPER AND NOT A CHECK PER VIEW (decision P4)
//      Five places read a session's crew: two row layouts, the detail's stat
//      tile, the detail's crew card, and the message-crew recipient list. Hiding
//      it view by view would eventually leak through one of them, and the worst
//      one is the recipient list — it would text people about a shoot that has
//      not been announced. So the crew is emptied ONCE, where a session crosses
//      into the view layer, and every consumer downstream inherits it.
//
//  WHY IT ALSO EMPTIES EVERY DAY-ROW
//      Crew lives on `session_days`, not on the session (MD7). `Session.with(day:)`
//      rebuilds an occurrence from a day-row's own photographers, so a session
//      whose top-level array was cleared but whose day-rows were not would put
//      the crew straight back the moment the detail screen switched days.
//
//  WHAT THIS IS NOT (decision P3)
//      This is not an enforced boundary. The server still sends the crew and the
//      app drops it client-side, so anyone willing to attach a proxy or a
//      debugger to their own device can read it. That is an accepted operator
//      ruling — "it's not sensitive data" — recorded here so nobody later
//      mistakes this file for a security control. Making it one is server-side
//      work on the SHARED database and a different arc.

import Foundation

enum DraftCrew {

    /// True when this viewer must not be shown who is on a draft.
    ///
    /// Schedule-edit rights are the line: the people who build the schedule need
    /// the crew on a draft to build it, and they are the ones the redaction
    /// would otherwise break. Everyone else sees the work without the names.
    @MainActor
    static var isHiddenFromViewer: Bool {
        !Permissions.has("schedule", level: .edit)
    }

    /// A session with its crew emptied when it is a draft and this viewer may not
    /// see one. A published session, or any session shown to a scheduler, is
    /// returned untouched — identity included, so `==` and diffing are unaffected.
    ///
    /// `hide` is passed in rather than read here because the index builder that
    /// calls this is not main-actor isolated and `Permissions` is. Compute it once
    /// per context from `isHiddenFromViewer`.
    static func redacted(_ session: Session, hidingDraftCrew hide: Bool) -> Session {
        guard hide, !session.isPublished else { return session }

        return Session(
            id: session.id,
            organization_id: session.organization_id,
            school_id: session.school_id,
            school_name: session.school_name,
            date: session.date,
            start_time: session.start_time,
            end_time: session.end_time,
            days: session.days.map { day in
                SessionDay(
                    id: day.id,
                    session_id: day.session_id,
                    date: day.date,
                    start_time: day.start_time,
                    end_time: day.end_time,
                    day_notes: day.day_notes,
                    sort_order: day.sort_order,
                    // Empty, not nil: `with(day:)` falls back to the session's own
                    // crew when a day-row carries none, and nil here would send it
                    // looking for exactly the array we are clearing.
                    photographers: []
                )
            },
            session_types: session.session_types,
            custom_session_type: session.custom_session_type,
            photographers: [],
            notes: session.notes,
            status: session.status,
            session_color: session.session_color,
            is_published: session.is_published,
            is_time_off: session.is_time_off,
            has_class_group_job: session.has_class_group_job,
            has_class_candids: session.has_class_candids,
            has_sports_job: session.has_sports_job,
            photographers_needed: session.photographers_needed,
            posers_needed: session.posers_needed,
            helpers_needed: session.helpers_needed,
            created_at: session.created_at,
            updated_at: session.updated_at,
            created_by: session.created_by
        )
    }

    static func redacted(_ sessions: [Session], hidingDraftCrew hide: Bool) -> [Session] {
        guard hide else { return sessions }
        return sessions.map { redacted($0, hidingDraftCrew: hide) }
    }
}

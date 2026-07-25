# PUB — draft visibility on the iOS schedule

Plan doc for the PUB arc. Registered in the family registry,
FocalPointProduction/docs/PHASES.md. One phase.

Written 2026-07-25 from an operator decision. Not part of the AMB arc: AMB is a
restyle and its D2 forbids behaviour changes inside a phase. This changes what a
photographer can see, so it gets its own code.


## What changes

TODAY  a photographer's app asks the server for published sessions only. Drafts
       exist, are worked on by schedulers, and are invisible until published.
       The week strip carries a staffing "temperature" — a heat-coloured dot per
       day for the whole org's staffing need, plus a long-press breakdown.

AFTER  photographers see unpublished sessions too, so they know what is coming.
       Every draft is unmistakably marked as not published. NOBODY's assignment
       is shown on a draft — not other people's, not your own. The temperature
       and its breakdown are gone.


## Decisions

P1  DRAFTS ARE VISIBLE TO EVERYONE. The client already controls this: the app
    passes includeUnpublished: canEdit, and SessionService adds
    .eq("is_published", true) only when that is false. So this is a client
    change with no migration and no policy work, and the shared database — and
    therefore the web app and Captura — is untouched.

P2  NO ASSIGNMENTS ON A DRAFT, INCLUDING YOUR OWN. A draft says what work is
    coming, never who is on it. Operator rule 2026-07-25, and hiding your own
    name too is what keeps "My Shifts" meaning one thing: what has actually been
    announced to you. A draft is not a commitment until it is published.

P3  REDACTION IS CLIENT-SIDE ONLY, AND THAT IS ACCEPTED. The server still sends
    the crew; the app drops it before anything renders. Anyone willing to attach
    a debugger or a proxy to their own device can read it. Operator ruling
    2026-07-25: "its not sensitive data and if they want to go to that extreme
    to see it, that is fine." Recorded so nobody later mistakes this for an
    enforced boundary — if it ever needs to BE one, that is server-side work on
    the shared DB and a different arc.

P4  ONE REDACTION POINT, NOT PER VIEW. A single helper returns a session with
    its crew emptied when the session is unpublished and the viewer lacks
    schedule-edit rights, applied where the store builds its per-day index.
    Every consumer inherits it. Five places read a session's crew today (see
    below); hiding it view-by-view would eventually leak through one of them —
    the message-crew recipient list being the worst, since it would text people
    about a shoot that has not been announced.

P5  THE TEMPERATURE GOES, FOR EVERYONE. Not just photographers — managers lose
    it too, because it is the same strip and there is no second copy on iOS.
    Operator decision 2026-07-25. What goes: the heat dot, the staffing
    breakdown popover, and the long-press that was meant to open it (which never
    fired anyway — it was attached to a Button, whose own gesture wins, inside a
    horizontal ScrollView whose scroll gesture also competes). The dot that
    means "you are on this day" stays.

P6  DRAFTS SIT APART FROM SHIFTS. They appear in both My Shifts and All Shifts,
    grouped and labelled as not published rather than mixed in with real shifts —
    since with P2 they carry no assignment, they cannot belong to "mine" at all.


## Scope

CHANGE

    ScheduleView          fetch with includeUnpublished always true; redact at
                          the index; drop the heat dot, the popover and the
                          long-press; add the drafts grouping
    ScheduleRows          draft treatment on the row: unmistakable, and no crew
    ShiftDetailView       a draft's detail shows no crew, no coworker photos, no
                          message-crew action; the staffing tiles stay (they are
                          counts of need, not people)
    HeatMapUtils          getHeatMapColor and StaffingPopoverView lose their only
                          callers — delete both with the change that orphans them

THE FIVE CREW READERS, all of which must go through P4's helper

    ScheduleRows.swift:154   day-layout row avatar stack
    ScheduleRows.swift:459   timeline row avatar stack + names
    ShiftDetailView.swift:361  "On crew" stat tile
    ShiftDetailView.swift:509  the crew card
    ShiftDetailView.swift:1764 message-crew recipients (the one that would leak
                               loudest — texting people about an unannounced job)

    Plus ShiftDetailView.swift:1901, "other jobs at this school today", which
    must not contribute crew from a draft either.

DO NOT TOUCH

    EditSessionView.swift:129 reads crew to populate the editor — that is a
    manager path behind schedule-edit rights, and redaction must not reach it.
    Publishing itself, the publish-a-day action, and every server behaviour.


## What "unmistakable" means

A draft has to be unreadable AS a shift at a glance, not merely labelled:

    a DRAFT / NOT PUBLISHED pill, present on the row and in the detail hero
    a dashed border rather than the solid one a real shift carries
    no crew, no avatars, and no message action anywhere on it
    grouped under its own heading, not interleaved with announced shifts
    excluded from the countdown card, which is about YOUR next call time and
      must never count something that has not been announced


## Verification

    build clean, zero warnings from changed files
    a draft renders with no crew anywhere: row, detail, coworker card, and the
      message-crew sheet reports nobody rather than the hidden crew
    a published session is unchanged in every respect
    a manager (schedule-edit) still sees crew on drafts and can still edit them
    the temperature is gone from the strip and HeatMapUtils is deleted, with no
      dangling references
    operator smoke on iPhone AND iPad
    /code-review before push — this changes what a class of user can see, which
      is exactly the kind of change that earns one

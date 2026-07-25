# OFF — the offline schedule

Plan doc for the OFF arc. Registered in the family registry,
FocalPointProduction/docs/PHASES.md. Two phases.

Written 2026-07-25, from a defect found during PUB.1's audit and an operator
question: photographers should be able to see their schedule with no signal.


## What changes

TODAY  The app writes a schedule cache to disk on every fetch and has NEVER once
       read it back. ScheduleCacheManager.loadMetadata decodes with a bare
       JSONDecoder while saveSessions encodes dates as ISO-8601 text, so the
       decode throws, the catch returns nil, and every read concludes there is no
       cache. Verified by running the round trip:

           ENCODED: {"lastSync":"2026-07-25T17:02:45Z", ...}
           FAILED:  typeMismatch - Expected to decode Double but found a string

       The identical bug is in TimeEntryCacheManager.loadMetadata. It has been
       this way since the file was written - all three commits it has ever had
       lack the date strategy, so this has never worked for any user.

       Consequences today: no cached first paint on launch, the "Offline - last
       synced" banner can never appear because isUsingOfflineData can never
       become true, offline the schedule throws instead of showing anything, and
       time-entry history does not load offline. The running clock-in DOES
       survive, because loadCurrentEntry reads its own file and does not go
       through metadata.

AFTER  No signal, open the app, see your shifts - schools, dates, times, notes,
       crew, drafts - with an honest last-synced time. Time-entry history comes
       back too. A cache that fails is reported instead of silently looking like
       an empty one.


## Decisions

O1  A FILE CACHE, NOT POWERSYNC. This app already runs PowerSync, it is live,
    and it already syncs 44 tables including schools and users - but not sessions
    or session_days. Adding them was considered and rejected:

      - the need is READ-ONLY. PowerSync earns its cost on bidirectional offline,
        writing without signal and reconciling later. Photographers do not edit
        the schedule; schedulers do, online.
      - the blast radius is disproportionate. Sync rules forbid JOINs and
        subqueries, so session_days would need organization_id denormalized onto
        it - a schema change, trigger and backfill on the SHARED database. And
        sync rules deploy from FocalPointProduction, so adding a table changes
        what the LIVE web app syncs.
      - it is a rewrite, not a fix: SessionService, the in-memory cache, the
        realtime listener and eight consumers would all have to be re-pointed.

    REVISIT THIS DECISION if photographers ever need to WRITE offline - clock in
    without signal, file a daily job report from a school basement. That is when
    a sync engine is the right answer and this cache is not.

O2  BOTH CACHES IN ONE PHASE. ScheduleCacheManager and TimeEntryCacheManager
    carry the same one-line bug, in the same method, for the same reason. Same
    fix, same risk, same verification shape. Splitting them would mean running
    the identical proof twice.

O3  BOUND WHAT IS WRITTEN TO DISK, NOT WHAT IS FETCHED. The cache is a whole-file
    replace: the entire session list is rewritten on every fetch and every
    debounced realtime event, and read back whole. That is fine for a list the
    screen loads into memory anyway, but SessionService.performFetch has NO date
    bound - it pulls every session the organisation has ever had - so the file
    grows forever.

    The fix goes at the cache WRITE, not the query. Eight callers share that
    fetch (the dashboard, ICS export, three time-tracking paths, photoshoot
    notes, template forms, daily job reports); narrowing the query underneath
    them would break several things to fix one.

O4  THE WINDOW IS THE SCHEDULE'S OWN WINDOW: 7 days back, 42 days forward. Not an
    invented number - it is what ScheduleIndex.build already uses to construct the
    timeline, and what loadTimeOff already widens to. The cache should hold what
    the screen can actually show.

    NAMED CONSEQUENCE, accepted: offline, every consumer of the cache sees that
    window, not just the schedule. Checked against the three time-tracking
    callers: getTodayAssignedSessions (today) and the two-week upcoming list both
    fall inside it. getSessionsForDate takes an ARBITRARY date, so offline it
    would find nothing outside the window - but today, offline, it finds nothing
    at all, so this is strictly better and never worse. Recorded so nobody later
    reads a short list as data loss.

O5  A FAILED READ IS NOT AN EMPTY CACHE. This is the decision that matters most,
    and the one the original bug is really about. Today both a genuine failure
    and a first-ever launch return nil, which is why a typo survived five months
    and two commits without anyone noticing - a broken cache is indistinguishable
    from one that has not been filled yet.

    The read path must tell the two apart: a decode or read FAILURE is logged
    with its error and surfaced, and is never silently reported as "no cache".
    Fixing only the date strategy without this leaves the next fault just as
    invisible.

O6  PROVE THE ROUND TRIP BEFORE THE DEVICE. This storage path has never executed
    in production, so nothing has ever confirmed a session survives being written
    and read back. Session carries a hand-written decoder, its crew lives on child
    day-rows, and multi-day jobs render from those rows - all of which must come
    back intact. A test that saves and reloads would have caught the original bug
    on day one; that is the deliverable, not an extra.

O7  THE SCHOOL AND TRAVEL SURFACE IS OFF.2, NOT OFF.1. After OFF.1 the LIST works
    offline; tapping into a shift still will not give the address, drive time or
    weather, because those are direct network calls. The sharpest of them is
    SchoolService.getSchool, which queries Supabase for a school even though
    schools is ALREADY synced to the device by PowerSync. That is a different
    subsystem with different callers and it gets its own session - it is what
    turns "I can see my schedule" into "I can get to the job".


## Scope

CHANGE, OFF.1

    ScheduleCacheManager      loadMetadata decodes with .iso8601; saveSessions
                              writes only the window (O3, O4); read failures are
                              distinguished from an absent cache and logged (O5)
    TimeEntryCacheManager     the same loadMetadata fix and the same failure
                              reporting
    SessionService            surface a cache read FAILURE in the offline banner
                              state rather than treating it as no data
    tests                     round-trip proofs (O6)

DO NOT TOUCH

    SessionService.performFetch's query shape - eight consumers share it (O3).
    The PowerSync sync rules, session_days' schema, and anything that reaches the
    shared database. This arc is device-local storage only: no schema change, no
    policy change, no sync-rule deploy, no migration.
    PUB.1's redaction. The cache stores the raw crew and the view layer drops it;
    that boundary is correct and stays.


## What "the window" means precisely

    lower bound   today minus 7 days
    upper bound   today plus 42 days
    applied       at the point sessions are written to disk, to the day-rows a
                  session carries - a session is kept if ANY of its days falls in
                  the window, so a multi-day job straddling the edge is not cut in
                  half
    NOT applied   to what the app asks Supabase for, or to the in-memory cache


## Verification

    the round trip, proved in tests before anything runs on a phone:
      - a session saved and reloaded is unchanged: day-rows, crew, multi-day
        structure, session types, times
      - a draft reloaded from cache is still redacted for a non-scheduler, so
        PUB.1's rule survives a trip through disk
      - a time entry saved and reloaded is unchanged
      - a multi-day session straddling the window edge is kept whole
    the guards that become reachable for the first time actually fire:
      - a cache belonging to another organisation is refused
      - a cache older than 7 days is refused and cleared
    a deliberately corrupted cache file reports a failure and does not present
      itself as an empty schedule (O5)
    build clean, zero new warnings from changed files
    operator smoke, iPhone AND iPad:
      - airplane mode, open the app: the schedule is there, with a last-synced
        time that is honest
      - the running clock-in still behaves, and time-entry history is present
      - back online, the schedule refreshes and the offline banner clears


## Risks, stated plainly

    THE MAIN ONE: this switches on a code path that has never run in production,
    for every user, on every launch. The write side has been running correctly all
    along, which is the reason to believe the data is sound - but "believe" is why
    O6 exists. If the round-trip proof fails, that is the phase finding its own
    reason to exist, not a setback.

    Session's decoder derives its representative date, times and crew from the
    embedded day-rows and falls back to legacy columns. Encoding writes the
    derived values back, so a reload must be checked to produce the same session
    rather than a subtly different one.

    Dates re-encoded as ISO-8601 lose fractional seconds. Harmless for created_at
    and updated_at, which are only displayed and ordered - to be confirmed, not
    assumed.

    A cache write now happens on every debounced realtime event as before, but
    against a bounded list, so the file gets smaller rather than larger. No new
    cost.


## Drift audit

Run before this plan is called done, and again at the phase's close.

    No work in this plan is described as deferred, a follow-up, or belonging to a
    later phase. OFF.2 is a SEPARATE, NAMED phase with its own scope, not a
    parking space for anything OFF.1 found inconvenient - the split is by
    subsystem (device files vs PowerSync reads), not by effort.
    O5 is in OFF.1 and not postponed, even though the arc would "work" without it.
    It is the reason the original defect went unseen, so shipping the date fix
    alone would repeat the mistake this arc exists to correct.
    The bounded window is in OFF.1 rather than left as a scaling concern for
    later, because an unbounded whole-file rewrite is a defect the moment the
    cache starts being read - which is exactly what this phase does.


## Phases

    OFF.1  The cache reads back. Both files, the bounded window, failure
           visibility, the round-trip proofs. Ships when the airplane-mode smoke
           passes on iPhone and iPad.

    OFF.2  The shift detail offline. SchoolService reads schools from PowerSync
           instead of Supabase, so address, coordinates and the travel plan work
           without signal. Weather stays online - it is a forecast, and a stale
           one is worse than none.

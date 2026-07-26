# Batch 2 parity inventory — Reports family + Time Off

Read from the source at the end of AMB.6, 2026-07-26, BEFORE any mockup exists.
Batch 2 is AMB.7 (Reports family) and AMB.8 (Time off).

This exists because four consecutive phases of this arc shipped feature LOSS when
a mockup was drawn from how screens LOOK rather than from what they DO. AMB.3
lost three capabilities inside a design the operator had already approved, AMB.4
seventeen, AMB.5 four, AMB.6 four. The inventory is the check.

STATUS: TIME OFF IS COMPLETE BELOW. The Reports family was inventoried in the
same pass and its structure is recorded here, but its field-by-field detail was
not transcribed into this file — the mockup build must re-derive it from source
first. Said plainly rather than left as a gap to discover.


## The surfaces, and two that the line counts hide

    AMB.7 Reports family
      Misc Features/DailyJobReportView.swift          1995   the standard form
      Misc Features/TemplateFormView.swift            1005   custom/template form
      Misc Features/CustomDailyReportsView.swift        306   template picker
      Misc Features/MyJobReportsView.swift             208   "my reports" list
      Misc Features/EditDailyJobReportView.swift        417   editor pushed from list
      Misc Features/PhotoshootNotesView.swift         1201   photoshoot notes
      Misc Features/LocationPhotoAttachmentView.swift   792   location photos
      Misc Features/TemplateReportListView.swift        558   *** ORPHANED ***
      plus Models.swift, TemplateService.swift, DailyJobReportService.swift,
      Services/PhotoshootNoteService.swift for the FIELD DEFINITIONS

    AMB.8 Time off
      TimeOff/Views/MyTimeOffRequestsView.swift        473   list + the shared card
      TimeOff/Views/TimeOffRequestView.swift           518   create AND edit, one form
      TimeOff/Views/TimeOffApprovalView.swift          383   manager, three tabs
      TimeOff/Views/TimeOffDetailView.swift            331   reached ONLY from Schedule
      TimeOff/Services + Models                              status, reasons, PTO

TWO SURFACES THE 3,763-LINE FIGURE DOES NOT INCLUDE, and a single mockup would
miss both:

  Settings/PTOBalanceView.swift (243) — the ONLY dedicated balance screen, and it
    is reached from SETTINGS, not from Time Off.
  Schedule/ScheduleRows.swift ScheduleTimeOffRow (214-236) — time off rendered
    inside the already-converted Schedule, with its OWN colour mapping in
    ScheduleStyleKit (30-37) that DISAGREES with the status enum on approved.

Nothing in TimeOff/ or PTOBalanceView uses ambientCard, AmbientStyle or
AmbientBadge. Every card is hand-rolled. ScheduleTimeOffRow is the exception and
is already Ambient — it uses a DASHED border to distinguish time off from a
shift, which is a deliberate signal worth keeping.

DEVICE BRANCHES: zero across all of TimeOff/ and PTOBalanceView. There is no
second, device-conditional screen. The iPad layout is the iPhone layout
stretched, which is what exists rather than a second design.


## THINGS THAT MUST BE FIXED OR DELIBERATELY CARRIED — found while inventorying

These are not style. Several are payroll-adjacent, which raises the bar.

1. THE APPROVAL SCREEN HAS NO PERMISSION CHECK AT ALL. TimeOffApprovalView
   contains zero permission calls. Approve, Deny and Put-in-Review are gated only
   by the VISIBILITY of a row in AllFeaturesView — and that row is gated on
   Permissions.has("users", .edit), a DIFFERENT area code from
   timeOffApprovals. Anything that sets the selected tab to timeOffApprovals
   reaches live approve/deny buttons. TimeOffService.canManageRequests() exists
   and is never called.

2. THE OWNERSHIP CHECK IN TimeOffDetailView IS BROKEN. It reads
   UserDefaults "userID", and NOTHING IN THE APP EVER WRITES THAT KEY — every
   other identity read goes through UserManager.getCurrentUserIDUnified(). So
   isOwnRequest is always false and the Cancel/Delete buttons appear only for
   holders of timeOffApprovals edit. Verified in code, not on a device.

3. "Delete Time Off" CAN ONLY EVER FAIL. It is shown only for APPROVED entries
   and calls cancelTimeOffRequest, which rejects any status that is not pending
   or underReview. A visible button whose every press is a 403.

4. THE WHOLE "Schedule Conflicts" SECTION IS UNREACHABLE. checkForConflicts
   builds an empty array, loops the date range doing nothing, and returns it. The
   header, the conflict rows and the line "Your manager will need to reassign
   these sessions if your request is approved." never render. Do not mock it as
   working; it is either built or dropped, and building it is a feature.

5. STATUS COLOURS DO NOT RESOLVE. TimeOffStatus.colorName and
   TimeOffReason.colorName return plain strings that views pass to Color(_:),
   which is the ASSET-CATALOG initialiser. The only colorset in the project is
   AccentColor. So none of these lookups find the system colours the enums
   describe. Verified in code; on-screen result not verified.

6. THREE DIVERGENT STATUS RENDERINGS. The card uses a filled capsule from
   colorName; TimeOffDetailView uses real SwiftUI colours and renders
   rawValue.capitalized, so underReview reads as the literal "Underreview";
   ScheduleStyleKit maps by status AND partial-day and makes approved ORANGE when
   partial and GREY when not. A redesign must pick one knowingly.

7. "Used This Year" IS ALWAYS ZERO. PTOBalance.usedThisYear is declared outside
   CodingKeys, so it is never decoded, and nothing assigns it. PTOBalanceView
   renders it anyway.

8. PTO FAILURES ARE SWALLOWED. reservePTOHours throws "Insufficient PTO balance",
   and the caller catches it and only prints a warning — so the request is
   created regardless. Same swallow on release and on deduct at approval. Editing
   a request NEVER adjusts an existing reservation.

9. TimeOffRequest.validate() IS NEVER CALLED. Its rules — start date not in the
   past, partial day must be same day, photographer name required — therefore
   have no runtime effect; only the picker bounds enforce anything.

10. No view ever displays TimeOffService.errorMessage. There is no error state
    and no offline state on any Time Off screen.

11. A dead template-report list (TemplateReportListView, 558 lines) is orphaned in
    the Reports family, and MainEmployeeView.managerFeatures (a whole declared
    array) is never referenced.


## TIME OFF — capability inventory

### MyTimeOffRequestsView — "My Time Off"

Shell-wrapped (not self-nav). No permission gate. Also a bottom-tab quick-access
candidate.

    KEEP  "New Time Off Request" primary button, always present in the header
    KEEP  An "All" chip plus five status chips: Pending, In Review, Approved,
          Denied, Cancelled — ALWAYS RENDERED even at zero count; only the
          numeric badge is conditional. That is the opposite of Tasks, where
          AMB.5 shipped a literal zero deliberately. Decide knowingly.
    KEEP  The chip row scrolls horizontally
    KEEP  "Create First Request" — CONDITIONAL: empty state AND no filter active
    KEEP  Pull to refresh — present ONLY on the populated list, absent in loading
          and empty states
    KEEP  "Edit" pill — CONDITIONAL on status pending or underReview
    KEEP  "Cancel" pill — same condition, with a confirmation alert
    KEEP  "Approved by NAME" + date, green check — conditional on BOTH approver
          name and approvedAt being present
    KEEP  "In review by NAME", blue magnifier
    KEEP  "Denied by NAME" plus "Reason: ..." in red, indented — the reason line
          conditional on a denial reason existing
    KEEP  Five distinct empty states: unfiltered says "No Time Off Requests" /
          "You haven't submitted any time off requests yet."; filtered says
          "No STATUS Requests" / "You don't have any status requests."
    KEEP  Loading copy "Loading your requests..."
    KEEP  Newest-first order (created_at descending, from the fetch)
    NOTE  NO swipe actions anywhere on this screen
    OPEN  No error state, no offline state

### TimeOffRequestView — create and edit, ONE form

Owns its own NavigationView. Title switches between "Request Time Off" and
"Edit Request".

    KEEP  Full Day / Partial Day segmented picker. Switching to partial FORCES
          end date = start date
    KEEP  Partial mode: one "Date" picker, bounded to today or later
    KEEP  Full mode: "Start Date" and "End Date". Start bounded to today or
          later; END BOUNDED BY START. Moving start past end drags end with it
    KEEP  "Start Time" / "End Time", partial mode only. If end <= start the app
          AUTO-CORRECTS end to start + 1 hour rather than erroring
    KEEP  A read-only "Duration" row — hours to one decimal for partial, and
          days+1 for full (INCLUSIVE of both endpoints)
    KEEP  "Reason" picker, six reasons, each with its own icon and colour
    KEEP  "Notes (Optional)", a TextEditor, minimum height 80
    KEEP  "Use PTO Balance" toggle, DEFAULTING TO ON
    KEEP  "Current Balance:" row — OMITTED ENTIRELY when the balance is nil
    KEEP  "Projected Balance by DATE:" — green when sufficient, ORANGE when not
    KEEP  "PTO Hours Requested:" decimal field, width 80. Auto-filled, but only
          while untouched — manual entry wins
    KEEP  Two inline validation messages: orange "You will not have sufficient
          PTO by the request date", and blue "This uses future PTO accrual"
    KEEP  A Summary section: Type, Dates, Duration, Reason
    KEEP  Submit disabled only by the 30-minute partial-day minimum; full-day is
          never blocked
    NOTE  The sheet auto-closes only when the alert text CONTAINS "successfully"
          — a string-matched success test
    OPEN  Editing a past request leaves the seeded date outside the picker's own
          allowed range
    DROP  The Schedule Conflicts section — see finding 4

### TimeOffApprovalView — manager, three tabs

Shell-wrapped. No permission check inside it — see finding 1.

    KEEP  Three tabs: Pending, In Review, History, with red count badges — and
          HISTORY DELIBERATELY PASSES NO BADGE, so it never shows a count
    KEEP  Horizontal swipe between tabs (a real but undiscoverable gesture)
    KEEP  Pull to refresh on all three
    KEEP  "Put in Review" — CONDITIONAL on pending, and wired ONLY on the
          Pending tab, deliberately not on In Review
    KEEP  "Approve" and "Deny" — conditional on pending or underReview
    KEEP  The denial alert with an INLINE reason field, and reason REQUIRED both
          client-side and in the service
    KEEP  The same card as the employee list, with actions suppressed
    KEEP  THE QUEUE IS FIFO — pending and in-review sort OLDEST FIRST, which
          deliberately reverses the employee list's newest-first. This is real
          workflow knowledge: a manager works a queue.
    KEEP  History sorts by WHEN IT WAS ACTIONED (updated_at descending)
    KEEP  Three distinct empty states with their own icons: "All Caught Up!",
          "No Requests In Review", "No History"
    NOTE  Buttons are NOT disabled while an update is in flight
    NOTE  The tabs read the org-wide array — every employee's requests, with no
          client-side scoping to the manager's own reports

### TimeOffDetailView — reached ONLY from Schedule

Owns its own NavigationView. Operates on a CALENDAR ENTRY (one per DAY of a
multi-day request), not on the request.

    KEEP  Read-only rows: Date in full style, Time Range or "Full Day",
          Photographer, Reason, Notes (row omitted when empty), and a
          "Partial Day Request" / "Full Day Request" line
    KEEP  A status dot plus label
    KEEP  "Cancel Request" — conditional on pending
    KEEP  Confirmation alerts, both saying "This action cannot be undone."
    DROP  "Delete Time Off" — see finding 3
    NOTE  Success dismisses the sheet WITHOUT showing its alert; only failures
          show one

### PTOBalanceView — in Settings, not in Time Off

    KEEP  Current Balance hero: a 36pt number plus "hours available"
    KEEP  Breakdown rows, signed with a leading +: "Total Balance", "Pending
          Requests" as a NEGATIVE in orange (conditional on being > 0),
          "Available to Use" in green, "Banking Balance" in blue (conditional)
    KEEP  Year-to-Date: "Used This Year" and "Total Accrued" — but see finding 7
    KEEP  Accrual Policy card — CONDITIONAL on settings existing AND enabled,
          which DEFAULTS TO FALSE, so this card usually just disappears
    KEEP  Human-readable policy copy: "1 hour per 40 hours worked",
          "240 hours (30 days)", "No rollover" / "Up to N hours" / "Unlimited"
    KEEP  A date picker, "Calculate balance for:", defaulting to 30 days out
    KEEP  Balance Projection, and "You will accrue N more hours by this date"
    KEEP  Error state with a Retry button — the only Retry in the surface
    NOTE  No pull-to-refresh; loads once per appear

### Domain logic to carry forward deliberately

    Duration is INCLUSIVE of both endpoints — days + 1
    A full day is 8 PTO hours
    Accrual counts BUSINESS DAYS ONLY, Monday to Friday, assumed 8h/day
    A partial day has a 30-MINUTE MINIMUM
    An invalid time range is AUTO-REPAIRED, not rejected
    The manager queue is FIFO; the employee list is newest-first
    A multi-day request FANS OUT into one calendar entry per day, all sharing a
      request id — so cancelling from any day cancels the whole request
    All-day time off sorts to the TOP of a day on the schedule; partial-day
      sorts by its start time among the shifts
    Full-day entries are stamped 09:00-17:00 purely for calendar placement
    PTO defaults to ON for a new request
    Denial requires a reason, enforced twice

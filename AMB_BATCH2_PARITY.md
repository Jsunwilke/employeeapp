# Batch 2 parity inventory — Reports family + Time Off

Read from the source at the end of AMB.6, 2026-07-26, BEFORE any mockup exists.
Batch 2 is AMB.7 (Reports family) and AMB.8 (Time off).

This exists because four consecutive phases of this arc shipped feature LOSS when
a mockup was drawn from how screens LOOK rather than from what they DO. AMB.3
lost three capabilities inside a design the operator had already approved, AMB.4
seventeen, AMB.5 four, AMB.6 four. The inventory is the check.

STATUS: COMPLETE. Time Off was read from source at AMB.6's close. The Reports
family half was re-derived from source on 2026-07-26 at the start of the batch-2
mockup work and is recorded in full below — the gap this file previously named
is closed.

That re-derivation found THIRTY-SIX further non-style defects in the Reports
family, listed in their own section after the inventory. Several are the same
class as AMB.6's conversations query: a failure that renders as an empty state.
Two are live data-loss paths into tables the web app and Captura also read.


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


## REPORTS FAMILY — capability inventory

Re-derived from source 2026-07-26. Nothing below is inferred from a file name.

Read the SHAPE of this family before the screens: it is not one feature. It is
TWO PARALLEL REPORT SYSTEMS plus two note-taking surfaces, and an org flag
switches between the first two.

  usePhotoshootNotesOnly TRUE   hides dailyJobReport, customDailyReports and
                                myDailyJobReports entirely, and is ALSO the flag
                                that turns ON the submit button and the
                                Submitted Notes section in Photoshoot Notes.
  usePhotoshootNotesOnly FALSE  the three report features are visible, and
                                Photoshoot Notes is a purely LOCAL scratchpad
                                whose notes reach the server only by being
                                attached to a daily job report.

ONE BOOLEAN THEREFORE SELECTS WHICH OF TWO WORKFLOWS THE ORG USES. A redesign
that draws only one of them strands the other. Verified at MainEmployeeView
231-249 and 257-267, AllFeaturesView 253-265, PhotoshootNotesView 394 and 474.

DEVICE BRANCHES: zero, in every file of this family. The iPad layout is the
iPhone layout stretched. The one exception is not a branch in these files —
DashboardWidgets presents the WHOLE of PhotoshootNotesView in an iPad sheet with
its own NavigationView and a Done button, so that view renders under two
different containers and sets its own nav title to the empty string.

DESIGN SYSTEM: zero usage across the entire family. No ambientCard, no
AmbientBadge, no AmbientStyle, no AmbientEmptyState in any of the eight files.
Every card is hand-rolled. Note the inversion worth keeping: the iPad
PhotoshootNotesWidget in DashboardWidgets IS already Ambient (AMB.4 converted
it); the full screen behind it is not, so today the widget and the screen it
opens are two different design languages.

### DailyJobReportView — the standard form, 1995 lines

Shell-wrapped. Sets NO navigationTitle, so the bar carries only Home and Submit.

    KEEP  Submit lives in the NAV BAR, always present, disabled only while
          submitting, its label swapping to a spinner. There is NO in-content
          submit button
    KEEP  An in-CONTENT title "Daily Job Report" at 24pt bold, which is separate
          from the empty nav title
    KEEP  "N sessions scheduled today" in green — CONDITIONAL on the day having
          sessions. The word "today" is hardcoded, so a back-dated report says it
          too
    KEEP  A progress bar over EIGHT sections whose denominator is SEVEN — Photos
          is excluded from the count and always reports itself complete
    KEEP  Copy "N/7 Completed" and a separate percentage
    KEEP  EIGHT collapsible sections, all always rendered, ALL STARTING EXPANDED,
          in this fixed order: Basic Information, Photoshoot Note, Schools and
          Mileage, Job Description, Extra Items, Scan Status, Notes, Photos
    KEEP  Each section header is a full-width tap target with its own 32pt
          coloured circular icon, a green check when complete, and a chevron
    KEEP  Completion rules, which are ADVISORY ONLY and never gate submit:
          basicInfo = a photographer is picked; photoshootNote = a note is
          selected; schools = at least one school AND mileage non-empty AND not
          mid-calculation; jobDescription and extraItems = at least one ticked;
          scanStatus = ALL THREE radios answered; notes = a note selected OR free
          text; photos = always true
    KEEP  Report Date row opening a SHEET at medium detent with a graphical
          picker that AUTO-COMMITS AND CLOSES 0.3s after any change. It has a
          Cancel button and deliberately NO Done
    KEEP  Changing the date resets session auto-selection so the new day re-runs it
    KEEP  Photographer menu picker, sorted case-insensitively, with a
          "Loading photographers..." row before it arrives. No none option, no search
    KEEP  Default photographer = exact first+last match on the stored name, else
          the FIRST photographer in the list
    KEEP  "Checking your schedule..." row while the schedule loads
    KEEP  Session menu picker — CONDITIONAL on the day having sessions. First row
          is "No scheduled session (off-schedule)", then sessions EARLIEST FIRST
          with undated ones last
    KEEP  Picking a session manually latches, so a listener re-fire cannot undo it
    KEEP  With a session chosen: a READ-ONLY school row labelled
          "School (from schedule)" with a building icon and a TRAILING LOCK
    KEEP  With no session: the manual MULTI-school picker, starting at exactly one
          slot, each slot labelled "School N", each opening SearchableSchoolPicker
          (its own sheet, its own NavigationView, searchable with prompt
          "Search schools...", a refresh button, a Done button, rows showing name
          plus address, a checkmark on the selection)
    KEEP  A red minus button per slot — CONDITIONAL on there being more than one
    KEEP  "Add School" button, always present in the manual branch
    KEEP  "Total Mileage" free-text decimal field with a trailing "miles" label.
          NO bounds, NO validation. The auto-calculation WRITES INTO THIS FIELD
    KEEP  "Calculating route distances..." row while mileage computes
    KEEP  Vehicle: a REQUIRED segmented control marked with a red asterisk, whose
          segment tap DELIBERATELY DISCARDS the value and raises a confirmation
          dialog instead. Copy: "Select the vehicle again to confirm — this sets
          your mileage reimbursement and can't be changed by an accidental tap."
          THIS TWO-STEP IS A DELIBERATE PAYROLL SAFEGUARD. Do not simplify it
    KEEP  Helper caption "Required — tap a vehicle, then confirm the selection."
          — CONDITIONAL on nothing being chosen yet
    KEEP  Job Description: a 2-column grid of 22 named checkboxes, verbatim list
          in AMB_BATCH2_PARITY's source order. "NONE" is an ORDINARY option with
          no exclusivity
    KEEP  Extra Items: the same, 12 options, same non-exclusive "NONE"
    KEEP  Scan Status: three radio groups — Cards Scanned (Yes/No),
          Job Box and Camera Cards Turned In (Yes/No/NA), Sports Background Shot
          (Yes/No/NA). None can be CLEARED once set
    KEEP  Notes: an "Additional Notes" TextEditor with a keyboard Done toolbar
    KEEP  A SECOND editor titled "Photoshoot Note for SCHOOL" — CONDITIONAL on a
          note being attached — which AUTOSAVES ON EVERY KEYSTROKE into shared
          AppStorage. This is the ONLY autosave in the screen
    KEEP  Photos: empty state is a full-width blue "Add Photos" button; populated
          state is a 3-column grid of 100pt thumbnails each with a delete chip,
          plus a trailing plus tile, plus "N photos selected"
    KEEP  Photo picking is ONE IMAGE PER PRESENTATION via UIImagePickerController,
          photo library only. NO camera, NO multi-select, NO reorder, NO preview
    KEEP  Photos are ALSO auto-imported from the attached photoshoot note, by
          downloading each of its URLs
    KEEP  Photoshoot Note section has three distinct states: none available
          ("No photoshoot notes available"), exactly one (auto-selected, showing
          "Using note from TIME", with NO way to deselect), and several (a picker
          whose first row is "None")
    KEEP  Choosing a note AUTO-FILLS school slot 0 when the note's school matches
    KEEP  Session auto-select picks the FIRST session of the day in start order
          that this photographer has not already reported; if all are reported it
          selects none. It runs at most once per date
    KEEP  Keyboard avoidance via a real keyboard-height publisher, animated
    KEEP  Alert "Error" with the raw message; confirmation dialog "Confirm Vehicle"
    KEEP  On success the screen does NOT dismiss — it posts a notification that
          the SHELL turns into "Report submitted successfully" and jumps to Home
    NOTE  ONLY ONE THING IS VALIDATED BEFORE SUBMIT: the vehicle type. Copy:
          "Please select whether this was your Personal vehicle or a Company
          vehicle before submitting." A report with no school, no mileage, no job
          descriptions and no scan answers submits happily
    NOTE  ZERO pushes. Two sheets only, plus the school picker's own
    NOTE  NO pull-to-refresh, NO swipe, NO long-press, NO context menu
    OPEN  NO DRAFT AND NO AUTOSAVE for the report itself. Every field is plain
          view state. Leaving the screen discards everything typed. The only
          persisted writing is the photoshoot note's text
    OPEN  No offline awareness at all. Mileage silently becomes 0.0 with no
          signal, and submit simply fails

### CustomDailyReportsView — the template picker, 306 lines

Shell-wrapped. Title "Custom Daily Reports", large.

    KEEP  A search field, ALWAYS present, placeholder "Search templates...", with
          a clear button CONDITIONAL on non-empty text
    KEEP  Search matches name, description and shoot type — but see finding R7:
          two of those three are always empty, so it is name-only in practice
    KEEP  A summary row — CONDITIONAL on there being templates — reading
          "N templates available" on the left and "N categories" on the right,
          both counting the FILTERED set
    KEEP  Four content states in this exact precedence: loading, error, empty, list
    KEEP  Loading copy "Loading templates..."
    KEEP  Error state: an orange warning triangle, "Unable to Load Templates", the
          message verbatim, and a "Try Again" button
    KEEP  Empty state: "No Templates Available" / "Contact your administrator to
          set up daily report templates for your organization." NO action button
    KEEP  Category sections in ascending alphabetical order, each with a title and
          a count pill
    KEEP  A 2-COLUMN GRID of template cards, fixed height 160, defaults first
    KEEP  Card anatomy: title (2 lines, scaling); a "DEFAULT" badge CONDITIONAL on
          isDefault; a description of up to 3 lines, ELSE the italic placeholder
          "No description available"; a footer of "N fields" on the left and
          "vN" on the right; and a smart-field row with a sparkles icon
          CONDITIONAL on the template having any
    KEEP  A green 2pt border CONDITIONAL on isDefault
    KEEP  Tapping a card presents TemplateFormView as a SHEET. This is the only
          destination — there is no push anywhere in the file
    NOTE  Two columns on iPhone AND iPad alike
    OPEN  No pull-to-refresh. No offline state. No empty-SEARCH-RESULT state — a
          search matching nothing renders blank with the header still counting

### TemplateFormView — the dynamic form, 1005 lines

Presented as a SHEET. Owns NO nav container — it FAKES a nav bar with a blue
gradient header. Swipe-to-dismiss is NOT disabled.

    KEEP  The fake header bar: a leading chevron plus "Back", and a trailing
          two-line stack of the template name over "vN"
    KEEP  A progress bar, always present even for an empty template, counting only
          fields that are not readOnly, with "N/M Fields Completed" and a percentage
    KEEP  Fields auto-grouped into at most FOUR sections, rendered ALPHABETICALLY:
          Basic Information, Calculated Fields, Media and Location, Report Details
    KEEP  A section exists only if its bucket is non-empty; all start expanded;
          each header carries a coloured icon badge, an "N fields" subtitle, a
          green check when complete, and a chevron
    KEEP  Every field row carries: its label, a red asterisk CONDITIONAL on
          required, and an "AUTO" pill CONDITIONAL on readOnly
    KEEP  FOURTEEN RENDERED FIELD TYPES, each with its own control — text, email,
          phone, textarea, number, currency, date, time, select, multiselect,
          radio, toggle, file, and the eight read-only smart types. An UNKNOWN
          type falls through to a plain text field, which is how "location"
          renders today
    KEEP  select always offers a blank first row, so a choice can be un-made
    KEEP  radio is a VERTICAL list of full-width buttons, not a segmented control,
          and cannot be deselected once picked
    KEEP  multiselect is a checkbox list storing an array
    KEEP  file renders the same 3-column grid + delete chips + plus tile as the
          standard form, with the caption "N photos selected"
    KEEP  Smart fields render as READ-ONLY grey text and are recomputed on every
          body pass
    KEEP  A session card ABOVE all field sections — CONDITIONAL on the user having
          sessions today — with the same "No scheduled session (off-schedule)"
          first row, the same earliest-first order, and the same run-once
          auto-select as the standard form
    KEEP  Empty-template state: "No Fields Available" / "This template doesn't
          contain any fields to display." with a blue "Go Back" button. The header
          and progress bar STILL render above it
    KEEP  Submit button at the BOTTOM OF THE SCROLL CONTENT, not a fixed footer.
          Disabled when submitting or invalid, dimmed to 60% when invalid
    KEEP  Success alert "Report Submitted" / "Your daily report has been submitted
          successfully.", whose OK dismisses the whole sheet
    KEEP  Error alert "Error" with the raw message
    NOTE  Unlike the standard form, EVERY field must validate before submit — and
          that includes read-only and smart fields
    OPEN  No draft. Swipe-dismiss or Back discards a filled form with NO
          confirmation
    OPEN  No offline handling; a failed submit loses the data with the sheet

### MyJobReportsView — the list, 208 lines

Shell-wrapped. Title "My Daily Job Reports", large.

    KEEP  A plain List, newest-first (date descending, from the query)
    KEEP  Row anatomy in reading order: the date as a headline; the school as a
          subheadline, ALWAYS RENDERED even when empty; "Mileage: N" to one
          decimal, always; and a blue photo-count pill CONDITIONAL on there being
          photos
    KEEP  Each row PUSHES to EditDailyJobReportView. That is the only destination
    KEEP  Swipe-to-delete, which does NOT delete — it raises a confirmation
    KEEP  Alert "Delete Report" / "Are you sure you want to delete the report from
          DATE?" with Cancel and a destructive Delete
    KEEP  Loading state: "Loading reports..." plus a "Please wait" line
    KEEP  Error state: an orange triangle, the message in red, and a Retry button
          that re-resolves the user id
    KEEP  The whole screen disables while a delete is in flight
    NOTE  NO empty state at all — an empty List renders with no icon, message or
          call to action
    NOTE  NO search, NO filter, NO sort control, NO grouping, NO pull-to-refresh
    NOTE  NO create affordance — creation is a different feature entirely
    OPEN  No offline state. A failed delete is invisible

### EditDailyJobReportView — the editor, 417 lines

Pushed from the list. Title "Edit Job Report", inline.

    KEEP  Section "Report Details": a date picker, a decimal Total Mileage field,
          a SEGMENTED Personal/Company vehicle picker, and a FREE-TEXT
          School / Destination field
    NOTE  THE TWO-STEP VEHICLE CONFIRMATION DOES NOT EXIST HERE. The create form
          guards this field with a dialog and the edit form does not — the same
          payroll value, two different levels of protection. Decide knowingly
    KEEP  Section "Job Notes" — a TextEditor of height 80, deliberately renamed
          from "Job Description"
    KEEP  Section "Photoshoot Note Info:" — a TextEditor of height 80. The
          trailing colon is in the shipped string
    KEEP  The same 22 job descriptions and 12 extra items, as 2-column checkbox
          grids, in the same order as the create form
    KEEP  The same three radio groups with the same options and the same defaults
          — Cards Scanned defaults "Yes", the other two default "NA"
    KEEP  An "Update Report" button as a bare Form row, swapping to a spinner
    KEEP  ONE inline red error slot under the button, which carries load, save,
          delete AND school-fetch errors alike
    KEEP  Section "Attached Photos" — CONDITIONAL on there being any — rendering a
          3-wide gallery whose photos are VIEW-ONLY, each opening a detail sheet.
          NO add, NO delete, NO reorder in this screen
    KEEP  A red trash toolbar button with its own alert: "Delete Report" / "Are
          you sure you want to delete this report? This action cannot be undone."
          Note this copy DIFFERS from the list screen's alert
    KEEP  The session link is loaded and written back verbatim, so editing never
          breaks it. It is NOT re-selectable here
    NOTE  NO loading state — the form shows defaults and then repopulates
    NOTE  The checkbox tap target is the ICON ONLY, not the row
    OPEN  No empty, offline or error state beyond the single inline slot

### PhotoshootNotesView — 1201 lines

Shell-wrapped on iPhone, and ALSO presented whole in an iPad sheet by
DashboardWidgets with its own NavigationView and Done button. Sets its own nav
title to the EMPTY STRING and draws a hand-rolled largeTitle instead.

    KEEP  A hand-rolled in-content "Photoshoot Notes" largeTitle
    KEEP  A "New..." button with a plus icon, always present, which creates and
          selects a draft immediately and tries to set its school from the schedule
    KEEP  A red "Delete" button — CONDITIONAL on a note being selected
    KEEP  An "N sessions today" green pill — CONDITIONAL on there being any
    KEEP  A HORIZONTAL note strip of 200x80 cards, each showing a short date and
          time, the school, and one line of body — with "(No content)" as the
          fallback. INSERTION ORDER, so OLDEST FIRST. Note the iPad widget sorts
          the opposite way and caps at five
    KEEP  Strip empty state "No notes created yet"
    KEEP  Unselected state "Select a note to edit or create a new one"
    KEEP  A "School" section ABOVE the note editor, deliberately in that order
    KEEP  A MENU picker of schools — NOT the SearchableSchoolPicker the sibling
          screens use, so there is no search and no refresh here
    KEEP  "Loading schools..." state
    KEEP  Auto-select the school when EXACTLY ONE session today matches, with the
          message "Auto-selected school from your schedule"
    KEEP  With MORE than one session, a confirmation dialog "Select School for
          Note" / "You have multiple photoshoots today. Which school would you
          like to use for this note?" listing "SCHOOL - TIME" per session, sorted
          by start time, plus Cancel
    KEEP  A note TextEditor of fixed height 150 with a live "N characters" counter
    KEEP  EVERY KEYSTROKE SAVES. There is no Save button anywhere
    KEEP  A "Photos" section with SEPARATE "Camera" (blue) and "Library" (green)
          buttons — this is the only screen in the family offering the camera
    KEEP  Photos empty state "No photos added"
    KEEP  A horizontal 100pt thumbnail strip whose AsyncImage has THREE states —
          spinner, image, and a fallback glyph on failure
    KEEP  A per-photo red delete chip with NO confirmation
    KEEP  An "Uploading photo..." progress row
    KEEP  A sync row: a green dot for synced, orange otherwise, reading
          "Submitted" (plus a relative time), "Synced to server", or
          "Local only (not synced)"
    KEEP  Relative times as "just now" / "Nm ago" / "Nh ago" / "Nd ago"
    KEEP  A "Submit Note" button — CONDITIONAL on the org flag AND the note being
          a draft — greying out and disabling on an empty school or empty text
    KEEP  A read-only lock state "Note submitted (read-only)" — same flag,
          non-draft
    KEEP  A green success banner "Note submitted successfully!" that auto-hides
          after 3 seconds
    KEEP  Validation copy "Please select a school before submitting" and
          "Please add some notes before submitting"
    KEEP  A collapsible "Submitted Notes" section — CONDITIONAL on the org flag —
          which fetches on first expansion, shows a count badge, and renders
          read-only cards with a green border, the school, the date, a green
          "Submitted" label, the body, and an 80pt photo strip. Window: LAST 30 DAYS
    KEEP  Delete confirmation "Delete this note?" / "This permanently deletes the
          note and any attached photos. This can't be undone."
    KEEP  Red error and green success banners at the bottom
    NOTE  There are NO categories, NO tags and NO note types. A note carries ONE
          school NAME (not an id) and is bound to no session
    NOTE  Storage is a SINGLE AppStorage JSON blob of the whole array, written by
          THREE different screens
    NOTE  NO swipe, NO pull-to-refresh, NO long-press, NO zoom. The only sheets
          are the two image pickers; there are ZERO pushes
    OPEN  No offline state. No search, filter or sort

### LocationPhotoAttachmentView — 792 lines

Shell-wrapped. Title "Location Photos", inline.

    KEEP  A trailing "+" toolbar button, disabled until a school is chosen
    KEEP  A leading location button that detects the current school — and note the
          shell ALSO injects a Home item, so this screen shows TWO leading items
    KEEP  A "Select Location" section using SearchableSchoolPicker
    KEEP  A detection status chip — CONDITIONAL on there being a message
    KEEP  "Loading locations..." state
    KEEP  An inline detect button beside the picker, disabled while detecting
    KEEP  Empty state: a 70pt icon, "No Photos Added", "Add photos to help others
          identify this location", and a CTA that SWITCHES on selection — "Add
          Photo" when a school is chosen, "Detect Current School" when not
    KEEP  An ADAPTIVE grid (minimum 150, maximum 200) inside a scroll view capped
          at 500pt — the only adaptive grid in the family
    KEEP  Per photo: a delete chip with no confirmation, a SOURCE badge reading
          "Camera" or "Library" with its own icon, and a free-text "Enter label"
          field
    KEEP  An "Upload Photos" button — CONDITIONAL on a school AND photos
    KEEP  An action sheet "Add Photo" / "Choose a source" with Take Photo,
          Photo Library and Cancel
    KEEP  A full-screen loading overlay whose copy switches between
          "Detecting Location..." and "Uploading Photos..."
    KEEP  A full-screen success overlay: a 60pt green check, "Photos Uploaded!",
          "Your photos have been successfully uploaded to SCHOOL", which
          AUTO-DISMISSES AFTER 2 SECONDS and clears the staged photos
    KEEP  Location denial copy "Location access required for auto-detection" —
          the only in-app iOS-permission copy in the family
    KEEP  Distance-tiered result copy: under 500m "You are at SCHOOL"; under 5km
          "Nearest school: SCHOOL (Nm away)"; beyond that "Selected SCHOOL (Nkm
          away)"
    KEEP  "No nearby schools found" and "Could not determine your location"
    NOTE  Staged photos are IN-MEMORY ONLY until Upload is pressed — leaving the
          screen loses them, unlike Photoshoot Notes
    NOTE  This screen can only ADD. Deleting an uploaded location photo lives in
          Settings/SchoolDetailView, a different screen entirely
    OPEN  No offline state, no retry, no per-photo progress or "3 of 7" count

### TemplateReportListView — ORPHANED, 558 lines, VERIFIED

Zero call sites. The only instantiation in the repo is its own PreviewProvider
instantiating itself. It IS compiled and shipped — the project uses synchronised
file groups with no membership exceptions, so every file under those folders
builds. It fetches THE SAME data as MyJobReportsView.

It is nonetheless the ONLY place several capabilities exist in this codebase, so
they are recorded rather than lost — a redesign either builds them somewhere real
or drops them knowingly:

    a search field over name, template and date; a segmented date filter of All /
    This Week / This Month / Last 30 Days; grouping by template name with
    "Legacy Reports" for the rest; per-group headers with counts; TEMPLATE versus
    LEGACY badges; a smart-fields-used count; a fields-completed count with a
    relative time; a proper empty state ("No Reports Found" / "You haven't created
    any template-based reports yet. Create your first report using the Custom
    Daily Reports feature."); an error state with "Try Again"; and a read-only
    detail sheet that renders form_data generically as key/value rows.

MyJobReportsView, the list that IS reachable, has none of these — no search, no
filter, no grouping, and no empty state at all.

### Domain rules to carry forward deliberately

    ONE ORG FLAG SELECTS BETWEEN TWO WHOLE WORKFLOWS — see the top of this section
    The report date is a DATE KEY, not an instant
    A report belongs to one org and one user; your_name is a DISPLAY key and not
      an identity, and the standard form stores only the FIRST name while the
      template form stores "First Last"
    The report list is NEWEST FIRST everywhere
    Template reports group by template name, groups alphabetical, newest first inside
    Submitted photoshoot notes are limited to the LAST 30 DAYS
    Local photoshoot notes are in CREATION order and never sorted
    Session linkage: nil means off-schedule; auto-select takes the first
      unreported session of the day and runs ONCE per date; a manual pick latches;
      a chosen session makes the school READ-ONLY; editing preserves the link
    The ONLY thing validated before a standard submit is the vehicle type, and it
      takes a deliberate TWO-STEP confirmation because it sets reimbursement
    A template submit requires EVERY field to validate, including read-only ones
    A photoshoot note requires a school and a body, enforced twice
    An edit can never CLEAR a field back to empty — the update path omits nils
    There is NO photo count or size limit anywhere in any of the three upload paths
    Attaching a note COPIES its photo URLs into the report, then removes the note
      but deliberately NOT its photos
    Signed photo URLs expire in ONE YEAR
    A photo that fails to upload does not abort the submit — the report saves without it
    Templates are read-only in this app; authoring is web-only


## HOW THE CONVERSION IS HELD TO THIS — mechanism, not instruction

Operator, 2026-07-26: "how will you ensure it creates these exactly as we have
designed instead of just using them as inspiration?"

The honest answer is that the mechanism we had already failed. Step 3b of the
phase kickoff says to put the converted screen beside the mockup and account for
EVERY difference — that instruction was in place when AMB.1 shipped a static day
strip where the lab scrolled, and then shipped it scrolling at the wrong capsule
width. Prose does not hold a design. So there are now three mechanisms, and the
strongest one removes the matching step entirely.

    1. THERE IS NOTHING TO MATCH. The design lives in production code that the
       LAB imports, not the other way round:

           Reports/ReportFormKit.swift     ReportSection, ReportMultiSelect,
                                           ReportChoiceRow, ReportVehiclePicker
           Reports/ReportRules.swift       ReportMileage, VehicleSelection,
                                           SessionAutoSelect
           Reports/ReportSchoolLink.swift  school ownership

       The converted screen imports the SAME components. It cannot have
       different padding, a different checkbox, a different heading weight or a
       different confirm layout, because it does not draw them. The mockup went
       from ~40 raw shape uses to 4 doing this — everything else is shared.
       Same reasoning as AmbientCard and its drift gate: a design nobody is
       forced to use is decoration.

    2. THE BEHAVIOUR RULES ARE EXECUTABLE. scripts/test_report_rules.sh compiles
       the REAL Reports/*.swift the app builds and runs them — 44 checks. Not a
       reimplementation in another language, which is a mistake already made once
       here and caught by the operator ("your logic was fake"). The suite covers
       every rule the contract below asserts: a typed mileage surviving
       recalculation, the first vehicle tap never committing, auto-select taking
       the first unreported session once per date and latching on a manual pick,
       and school ownership replacing rather than appending.
       It has been proved to FAIL when a rule is broken; a test that cannot fail
       is the same fake evidence in another costume.

    3. PARITY-WALK THE NEW SCREEN, every round, with a grep-per-capability pass
       rather than by reading. Five capabilities were lost inside these
       redesigns and the operator found four of them.

WHAT IS STILL ONLY PROSE, and therefore still at risk: spacing and type scale
inside the sections the kit does not own, and the order of the nine sections.
Judge those against the running mockup.


## THE BEHAVIOUR CONTRACT — what AMB.7 must build for real

Operator, 2026-07-26: "the real deal will act EXACTLY as the mockup does", and
then, on the mockup's own logic being throwaway: "that is why I said its fake.
and thats ok. as long as it all works when built for real."

So the mockup is a SPECIFICATION, and its sample-data plumbing is not. This list
is the part that has to survive into the real screen. It exists because this arc
has already lost five capabilities inside redesigns — the denial reason, the
report date, the photographer, the session link and the photoshoot note — and
the operator found four of them, not the parity walk.

### The daily job report

    ONE SCREEN. Nothing collapses, nothing expands, every field ready on arrival.
      Rejected on the operator's instruction: a wizard, an accordion, and any
      disclosure step in front of a field filled in every day.

    NINE PEER SECTIONS, all with the same heading, card and spacing, and a status
      on the right of each heading. Nothing is styled as secondary — a wrong
      school or vehicle is a payroll error and a missing job description is a
      billing error.

    EVERY PREFILLED VALUE IS EDITABLE, in place, with no extra step. Date,
      photographer, session, schools, mileage, vehicle, what you shot, extras,
      the scan answers, the attached note, notes, photos.

    SCHOOL OWNERSHIP — specified and tested in ReportSchoolLink.swift, which the
      conversion should carry over rather than reimplement:
        each source remembers the school IT contributed
        changing a session or note REPLACES its own school, never appends
        off-schedule, or "No photoshoot note", removes it
        a school added by hand is owned by nobody and is never auto-removed
        a school BOTH sources point at survives until both let go
        stop order is route order, and is preserved through add and remove

    MILEAGE
      calculated from the route between the schools on the report, point to
        point — NOT GPS trip detection (splits on every stop, silent
        non-capture is its top real-world complaint)
      the route is ALWAYS shown under the figure, never a bare number
      a TYPED value wins and is never overwritten by a recalculation, with the
        calculated figure still offered alongside
      a figure well out of line with this photographer's own history at that
        school is flagged in place

    VEHICLE
      lives WITH the mileage — one decision, not two sections
      NO DEFAULT. Nothing is pre-selected and the photographer must choose.
      BOTH options take the two-step, and the first tap never commits.
      The confirmation appears INLINE, directly under the buttons that raised
        it — never as a sheet or dialog anchored elsewhere. The vehicle sits in
        a long scroll, and finishing at the top something you started at the
        bottom means changing your grip.
      The armed-but-unconfirmed option is drawn as armed (dashed edge), so it is
        obvious which choice the confirmation belongs to, without pretending it
        has been applied.
      Superseded 2026-07-26: my earlier proposal was to default to the
        photographer's usual vehicle and confirm only on a CHANGE, aimed at
        alert fatigue. The operator's rule is better here — with nothing
        pre-selected the confirm is the second half of a choice just made, not a
        dialog interrupting an already-correct value.

    THE TWO LISTS
      all 22 job descriptions and all 12 extra items, visible, never behind a
        disclosure control
      grouped under families, TWO COLUMNS, checkbox leading, whole cell tappable
      the families and their contents NEVER reorder themselves — no recency
        sorting; frequent users learn where things are
      "NONE" alongside other items warns, and still saves both, because
        exclusivity is a data rule and out of this arc's scope

    SESSION
      today's sessions, earliest first
      "No scheduled session (off-schedule)" is a first-class choice
      auto-select takes the first session NOT already reported, once per date,
        and a manual pick is never undone by a refresh
      a session already reported says so on its row

    PHOTOSHOOT NOTE
      attach one, or choose "No photoshoot note"
      auto-selected ONLY when there is exactly one
      attaching fills in the school and copies the note's photos onto the report
      the note's text is editable from the report

    SUBMIT
      lives in the navigation bar, and is NEVER blocked. Warnings do not gate.

### Not specified by the mockup — decide before conversion

    Loading states. The live form has "Checking your schedule...",
      "Calculating route distances..." and "Loading photographers...". Sample
      data never loads, so the mockup cannot show them and does not.
    Offline. The live form has none at all, and the mockup adds none.
    The draft strip is drawn and marked PROPOSED. There is no draft or autosave
      in the live form; adding one is a data-layer change and out of scope here.


## REPORTS FAMILY — non-style findings

Thirty-six defects found while inventorying, none of them style. They are NOT
this phase's to fix — recorded here so the redesign does not draw them as if they
worked, and so they can be scoped as real work. Grouped by how much they matter.

### Failures that render as legitimate emptiness — the AMB.6 class

R1  THE SUBMITTED-NOTES QUERY CANNOT SUCCEED. PhotoshootNoteService:136 sends
    is("deleted_at", value: true), which emits deleted_at=is.true against a
    TIMESTAMPTZ column. The intent was is.null. Verified in the service and in
    migration 009.
R2  AND IF R1 WERE FIXED, EVERY ROW WOULD STILL BE DROPPED. The DTO parses the
    date column with a default ISO8601DateFormatter, which returns nil for
    "2026-07-26" — verified by executing the formatter. The row is then discarded
    by a compactMap with only a print. The count would report zero with no error.
R3  THE PHOTOGRAPHER ID USED FOR THAT FETCH IS ALWAYS THE EMPTY STRING.
    AppStorage "userID" is READ in three places and WRITTEN NOWHERE in the app —
    it is only ever removed on sign-out. Verified repo-wide.
R4  A FAILED "already reported" LOOKUP RETURNS AN EMPTY ARRAY in both forms, so a
    session that WAS reported is silently offered again.
R5  A CORRUPT LOCAL NOTES BLOB WIPES EVERY VISIBLE DRAFT with no message — both
    readers decode with try? and fall back to an empty array.
R6  MyJobReportsView HAS NO EMPTY STATE, so "you have no reports" and "the query
    returned nothing" are the same blank screen.

### Live data-loss paths

R7  A LOCATION-PHOTO UPLOAD CAN WIPE A SCHOOL'S EXISTING PHOTOS. The upload does a
    read-modify-write of the whole schools.location_photos array, and the parser
    it reads through SWALLOWS a decode failure and returns an empty array — so a
    blob it cannot parse is replaced by just the new photos. This writes to
    schools, a table SHARED with the web app and Captura.
R8  SUBMITTING A PHOTOSHOOT NOTE DELETES THE ONLY COPY. The local note is removed
    immediately after submit, and the server round-trip that would show it again
    is broken by R1 and R2.
R9  THREE SCREENS READ-MODIFY-WRITE THE SAME AppStorage BLOB and none observes the
    others. The iPad case is concrete: the widget stays mounted while presenting
    the full screen in a sheet, so notes created there are reverted when the
    widget saves.
R10 AN EDIT CAN NEVER CLEAR A FIELD. The update path writes a column only when
    non-nil, and the edit form turns empty values into nil — so emptying Job
    Notes or School leaves the old value in the shared database and the screen
    shows the stale value next time.
R11 A FAILED REPORT LOAD LEAVES THE EDIT FORM BLANK WITH NO ERROR, and pressing
    Update then writes those defaults over the real record.
R12 A TEMPLATE PHOTO UPLOAD THAT FAILS MID-LOOP ORPHANS THE ALREADY-UPLOADED
    OBJECTS and files no report at all.

### Dead features — shipped, unreachable

R13 SIX ReportTemplate PROPERTIES ARE OUTSIDE CodingKeys, so they are never
    decoded. Consequences, all live: every card shows "No description available";
    every template shows v1 and every template report records version 1; the
    DEFAULT badge and its green border are dead code; shoot_type is always empty
    so ALL templates fall into ONE category with a BLANK header; and search over
    description and shoot type can never match.
R14 A REQUIRED "file" FIELD CAN NEVER BE SATISFIED — file input writes to a
    view-level array, never to the field's own key, so Submit stays disabled forever.
R15 AN OPTIONAL, UNTOUCHED "number" FIELD ALSO DISABLES SUBMIT FOREVER, because
    its validator returns false for nil regardless of whether it is required.
R16 weather_conditions AND current_location ARE PERMANENT PLACEHOLDERS. Users see
    "Weather loading..." and "Location pending..." forever, and those strings are
    what get SAVED into the report.
R17 THE TEMPLATE FORM HAS NO SCHOOL PICKER, so its school_name smart field always
    renders the fallback and its mileage always renders 0.0.
R18 TemplateReportListView, 558 lines, IS ORPHANED but compiled and shipped.
R19 MainEmployeeView.managerFeatures IS A DEAD DUPLICATE of the live array in
    AllFeaturesView — verified identical, and it will drift.
R20 A LARGE DEAD SERVICE SURFACE: checkExistingReport, loadReports and its
    published array, one getReports overload, both getTotalMileage overloads,
    getMileageBySchool, four TemplateService authoring methods, calculateWeatherField,
    getTemplatesByCategory, fetchNote and uploadPhoto. All verified by grep.
R21 DEAD UI IN THE STANDARD FORM: a "Permission Error" alert that is never
    triggered, an orange schedule-error caption whose variable is only ever set to
    empty, a local toast wired to state nothing sets, and a completion check that
    compares a non-optional date to nil.

### Correctness

R22 TWO MILEAGE ENGINES DISAGREE. The standard form uses real MKDirections driving
    routes; the template form's mileage smart field uses straight-line Haversine.
    Both write the same total_mileage column that feeds reimbursement.
R23 SUBMITTING WHILE MILEAGE STILL READS "Calculating..." STORES 0.0.
R24 A TYPED MILEAGE VALUE CAN BE SILENTLY OVERWRITTEN by a recalculation, or
    cleared entirely when the user has no home address set.
R25 THE "already reported" LOOKUP IS KEYED ON FIRST NAME, so two photographers
    sharing one first name share that state.
R26 TEMPLATE REPORTS NEVER APPEAR IN THE MANAGER DRILL-DOWN, because the manager
    queries by first name and the template path stores "First Last". Its mileage
    totals under-count accordingly.
R27 DATE KEYS ARE WRITTEN IN GMT AND READ IN LOCAL — verified by executing the
    formatters. An evening report can be stored on the following day.
R28 "TODAY" RANGE QUERIES INCLUDE THE FOLLOWING CALENDAR DAY, because an exclusive
    end bound is passed to an inclusive comparison.
R29 photoshoot_note_id IS DECODED BUT NEVER WRITTEN — the report-to-note link
    exists only in the reverse direction. The value passed is also an UPPERCASE
    UUID, against the project rule.
R30 NON-PRIMITIVE form_data VALUES ARE SILENTLY PERSISTED AS null.
R31 A TEMPLATE FIELD WITH BOTH A BASIC TYPE AND A SMART CONFIG RENDERS TWICE, in
    two different sections.
R32 multiselect AND radio IGNORE readOnly — they show the AUTO pill and still
    accept taps.
R33 A "date" FIELD VISUALLY SNAPS BACK TO TODAY after every selection, because it
    is written as a full-date string and read with a formatter that cannot parse
    one. The stored value is correct; only the picker reverts.
R34 A PHOTO-UPLOAD FAILURE IN THE STANDARD FORM PRODUCES BOTH AN ERROR ALERT AND A
    SUCCESSFUL SUBMIT, with the photo lost and nothing recording the loss.
R35 THE CUSTOM REPORTS EMPTY STATE IS UNREACHABLE — an empty result throws, and
    the view checks the error before the empty case, so a new org sees a warning
    triangle instead of the written onboarding copy. A transient failure also
    HIDES templates the user already had.
R36 TWO SCHEMA QUESTIONS THAT ONLY THE LIVE DATABASE CAN ANSWER, and one of them
    could mean this feature has never worked: the template fetch orders by
    created_at, a column the repo's own schema reference does not list for that
    table; and DATABASE_SCHEMA.md is demonstrably STALE (it predates vehicle_type
    and session_name, both of which are written today). NOT ASSERTED — it is one
    query away from certain, and it is the same failure class as AMB.6.

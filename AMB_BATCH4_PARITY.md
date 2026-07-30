# Batch 4 parity inventory — Job box / NFC (the rest), the tail, and the shell

Read from the source 2026-07-30, BEFORE any batch-4 mockup exists. Batch 4 is
AMB.11 (Job box / NFC — the remaining surface) and AMB.12 (Settings, Manager
features, Training — the tail, D9). PART THREE adds the five shell surfaces
`AMB_SHELL_INVENTORY.md` named, which belong to no phase and which AMB.12 closes
the arc over.

This exists because every phase of this arc that skipped or shortcut the
source-inward inventory shipped feature LOSS: AMB.3 lost three capabilities
inside an approved design, AMB.4 seventeen, AMB.5 four, AMB.6 four. D12 makes it
a parity contract: layout, hierarchy and information architecture are in scope,
and NO FEATURE MAY BE LOST. The inventory is the check; the mockup is only the
proposal.

Method: every file in `NFC/`, `JobBox/`, `Manager Features/`, `Settings/`,
`Training/` and the time-tracking surface read completely, plus the services
those views consume, plus `MainEmployeeView.swift`'s registration/dispatch/
container machinery, `DesignTokens.swift`'s theme registry and
`scripts/check_card_drift.py`'s allowlist. Live DB checks were run against the
shared project where a column's existence changed a finding; those are marked
PROVED. Everything else is cited file:line.

---

## 0. HEADLINE FINDINGS (read these before designing anything)

### Scope

1. **AMB.11's "18 views" is exactly the `NFC/` directory** — 18 top-level `View`
   structs across 17 files, 5,373 lines as it stands today (the plan's 5,198 is
   stale). The shipped progress-meter slice added `JobBox/` (3 files, 2 views)
   which is NOT part of that 18, and converted 20 lines inside
   `ManagerJobBoxTrackerView` — which lives in `Manager Features/`, i.e. AMB.12's
   directory. **Job box functionality straddles the two phases by directory.**
   This is the same shape as batch 3's ManagerMileageView, and the gate's own
   header has already ruled on that one: ManagerMileageView is **deferred to
   AMB.12 by the operator** (`scripts/check_card_drift.py:118-121`). The tracker
   and its settings sheet need the same ruling, made once, not twice.
2. **AMB.12 is materially larger than "~6,600 lines".** Settings (3,269) +
   Manager Features (2,682) + Training (864) = 6,815, which is the plan's figure.
   But the drift allowlist assigns **AMB.12** to a further set outside those three
   directories: `AllFeaturesView`, `LoadingOverlay`, `AddressAutocompleteField`,
   `SessionSelectionView`, `TimeTrackingButton`, `TimeTrackingMainView`,
   `TimeEntryListView`. And the plan's own Open section
   (`AMBIENT_ROLLOUT_PLAN.md:659-680`) records that **the time-tracking surface —
   2,540 lines across nine screens, verified exactly by `wc -l` — is named in NO
   phase**, with three resolutions offered and none chosen. That question is still
   open and AMB.12 is the last phase in which it can be answered.
3. **A tenth time-tracking screen exists that no list names**:
   `NotesInputView.swift` (122 lines), the clock-out notes sheet, on the primary
   clock-out path from the home dashboard. Absent from the plan's Open list, from
   `AMB_SHELL_INVENTORY.md`, and from the allowlist.
4. **`UIComponents.swift` does not exist.** `AMB_SHELL_INVENTORY.md:120-121` lists
   it as AMB.12 work; it was **deleted** by AMB.7's Reports conversion
   (`b5679dc`), and `ModernCheckboxRow`/`ModernSegmentButton` have zero references
   anywhere. That inventory row is stale.
5. **`PTOBalanceView` lives in `Settings/` but was converted by AMB.8** — it is
   the one already-Ambient screen in that directory
   (`Settings/PTOBalanceView.swift:59`, `:135`, `:163`, `:208`, `:267`) and its
   second route in is the Time Off feature, not Settings
   (`TimeOff/Views/MyTimeOffRequestsView.swift:162`). Do not re-design it.

### Things that are broken and must be decided, not merely redrawn

6. **The manager tracker's "Flag for Attention" writes to three columns that do
   not exist.** `ManagerJobBoxTrackerView.swift:404-428` writes `flagged`,
   `flag_note`, `flagged_at`; **PROVED by live query: `job_boxes` has exactly ten
   columns** — `id, organization_id, status, photographer, school, box_number,
   school_id, shift_uid, timestamp, user_id`. PostgREST rejects the statement as a
   unit. The swipe action (`:686-692`), the context-menu item (`:702-707`) and the
   entire flag sheet (`:899-942`) are a fake affordance whose only outcome is a red
   error string. Nothing anywhere reads a flag. **This is the FLG.1 defect class
   again, and the PSH.1 class before it.**
7. **`FlaggedStatusView.swift` is a dead screen** — 104 lines, **zero call sites in
   the entire tree** (independently verified: the only occurrence of the name is
   its own declaration at `:4`). It is the only employee-side response to being
   flagged that exists anywhere in the app, and the two columns it writes
   (`unflag_request_note`, `is_unflag_requested`, `:84-85`) have zero readers. **A
   flagged photographer has no in-app way to respond; only a manager can clear it.**
8. **`PhotoCritiqueDetailView` crashes on Save/Share for any legacy critique row.**
   `imageUrls` defaults to `[]` (`Models.swift:880`); `:245` and `:271` index it
   unguarded and `:247`/`:273` force-unwrap `URL(string:)!`. The backward-compat
   singular `image_url` (`Models.swift:855`) is never consulted.
9. **Sign-in proceeds even when the profile fetch fails** — `SignInView.swift:168-175`
   signs the user in with an empty org id, `role` defaulting to `"employee"` and
   **no permissions loaded**, after which every org-scoped screen guards out to
   blank. This is the highest-severity finding in the tail.
10. **`CreateAccountView` inserts the user row with a user-typed `organization_id`
    and a client-supplied `role: "employee"`** (`:193`, `:202`, insert `:206-209`),
    with no validation that the org exists and no membership check. A partial
    signup also orphans an auth user with no profile row, which then fails forever
    with "already exists" (`:163` vs `:206-209`).
11. **A bad password-reset link produces no UI at all.** `handleOAuthCallback`
    fails → `error` is set but `showingResetPassword` is never set
    (`PasswordResetViewModel.swift:88-91`), so the sheet never appears and the user
    sees nothing. `IOS_PASSWORD_RESET_FLOW.md` documents an "Invalid/Expired link"
    state that does not exist, along with four error strings that are not in the
    code (§2.1.5).
12. **`SchoolDetailView` persists a signed URL with a one-year expiry into the
    database** (`:383-385`, stored `:396-397`) — every location photo silently
    404s exactly one year after upload.
13. **Renaming a school orphans its entire history.** Every school↔report join in
    Settings is by NAME (`SchoolInfoListView.swift:138`,
    `Services/DailyJobReportService.swift:680`), and `SchoolDetailView.swift:326-330`
    offers the rename with no warning and no migration.
14. **`PTOBalanceView` — a read-only balance screen — CREATES a database row as a
    side-effect of being opened.** `getPTOBalance` defaults `createIfMissing: true`
    (`TimeOff/Services/PTOService.swift:53`, write `:92`); the read-only opt-out
    exists at `:88-91` and `PTOBalanceView.swift:286` does not pass it.
15. **`JobBoxStalledTimings.defaultTimings.leftJob = 192.0` is outside its own
    slider's range of `0.5...48`** (`JobBoxSettingsView.swift:13` vs `:148`). On
    first open the slider renders clamped, and the first touch silently rewrites a
    192-hour threshold to ≤48 — changing which boxes the tracker calls stalled,
    with no confirmation.

### Things that change a design decision

16. **The `scan` feature's registered colour never reaches its own screens.**
    `FeatureTheme` gives `scan` `#2AA7D8` (cyan, `DesignTokens.swift:57`), and it
    is applied to the **bottom tab bar only** (`BottomTabBar.swift:207`). Every NFC
    surface is hand-rolled **orange** (`ScanView.swift:109-110`,
    `NFCContainerView.swift:31`, `WriteNFCView.swift:65`). The bar and the screen
    it opens are different colours today. Zero `ambientCard`/`FeatureTheme`/
    `AmbientStyle` tokens exist anywhere in `NFC/`.
17. **`NFCContainerView` is a five-tab sub-shell inside a feature the shell already
    wrapped, and three of its five tabs wrap themselves AGAIN.** Stats (`:53`),
    Write NFC (`:63`) and Manual Entry (`:67`) each add their own `NavigationView`;
    Scan (`:46`) and Search (`:48`) are bare. **Two different chrome layouts inside
    one feature** — `WriteNFCView`'s title renders in an inner bar below the shell's
    Home button, `ScanView`'s renders in the shell bar itself. The five tab colours
    (`.orange/.blue/.green/.purple/.teal`, `:29-37`) bypass `FeatureTheme` entirely.
18. **On iPad the Scan tab is deliberately removed from the bottom bar because
    iPads have no NFC** (`BottomTabBar.swift:180-193`, with the reason in the
    comment) — **but `AllFeaturesView` does not filter it**
    (`AllFeaturesView.swift:253-257` drops only the three photoshoot-notes ids). So
    the full NFC feature is one tap away on an iPad that cannot scan, rendering a
    60pt rail sized for a phone and a 200pt scan disc that answers "NFC scanning is
    not supported on this device." Three of the five tabs *are* genuinely useful on
    iPad, and nothing tells the user which.
19. **There are FOUR different device predicates in the shell** and they disagree
    in iPad Split View: `horizontalSizeClass == .regular && idiom == .pad`
    (`MainEmployeeView.swift:616`), `idiom != .phone` (`:775`), and
    `idiom == .pad` twice in the tab bar (`BottomTabBar.swift:184`, `:585`). A
    narrow iPad gets the **iPhone widget set**, the **iPad** self-nav treatment for
    sports, the **iPad** centre-Home bar, **10** tab slots and **no top-left Home
    button** — a configuration no single predicate describes and that nobody has
    looked at. The AMB.4 lesson, still live.
20. **Only ONE real device-conditional layout exists in all of batch 4's feature
    directories**: `Training/PhotoCritiqueListView.swift:14-23` + `:155`, a 2-column
    iPhone / 3-column iPad `LazyVGrid` switched on `UIDevice` idiom rather than size
    class — so an iPad in Slide Over still draws 3 columns. `NFC/`, `JobBox/`,
    `Manager Features/`, `Settings/` and the entire time-tracking surface have
    **zero** device conditionals (Settings' single grep hit is a comment,
    `SettingsView.swift:15`). AMB.11 and AMB.12 design the iPad layout from
    scratch; they are not adapting one.
21. **Three colour maps describe one job-box status vocabulary and they disagree on
    three of four statuses.** `JobBoxTripStage.meterTint` (the shipped Ambient one),
    `ManagerJobBoxTrackerView.rowBackground` (`:813-823`), and
    `NFC/StatusColors.swift:19-24` — which `STATUS_COLORS_DOCUMENTATION.md` presents
    as the **iOS↔web contract**. Packed is slate / blue-tint / blue; Picked Up is
    teal / purple / green; Turned In is green / green / grey. `StatusColors` is
    consumed only inside `NFC/` (verified: `StatisticsView.swift:93`,
    `RecordBubbleView.swift:14`, `JobBoxBubbleView.swift:14`) — the manager screens
    never call it, so the two vocabularies never meet on one screen and the
    disagreement has stayed invisible.
22. **`job_boxes` is an append-only scan log** (`JobBoxProgressRules.swift:11-14`)
    and there is no update-status path in either client. The manager's "Update
    Status" buttons INSERT a new row (`ManagerJobBoxTrackerView.swift:348-401`) with
    **no transition validation whatsoever** — Turned In → Packed is one tap, no
    confirmation, no undo.
23. **Neither tracker query is bounded, and both are silently windowed to 30 days**
    (`:144`, `:171`) with nothing in the UI saying so. Live: 1,059 rows total, **17
    within 30 days**. A manager looking for a box last scanned five weeks ago gets
    "No job boxes found" and no explanation.
24. **Every filter, sort, date and search control on the tracker triggers a full
    network refetch, per keystroke, with no debounce** (`:343-345`, `:475-477`), and
    the full-screen spinner replaces the list each time.
25. **`ScanView` never calls the pickup guard.** `JobBoxPickupRules.pickupWarning`
    — the wrong-box / nothing-packed / no-job-link warning added after a live
    failure — is called from `JobBoxFormView.swift:214` and
    `ManualEntryView.swift:607`, never from `ScanView`, which calls only
    `inheritableShiftUid` (`:549`). ScanView is safe today **only because it
    delegates to `JobBoxFormView`**. A redesign that inlines the form into the scan
    screen loses the guard silently.
26. **PROVED: the `records` table has no `photographer` column at all** — live
    schema is `id, organization_id, card_number, school, status, user_id, timestamp,
    uploaded_from_andys_house, uploaded_from_jasons_house, created_at`. `job_boxes`
    does have one; `records` does not. **Four visible SD-card capabilities are
    attached to data the table cannot hold**, and all four fail silently:
    - `saveRecord` accepts a `photographer` argument and **discards it on the online
      path**, persisting it only offline (`DatabaseManager+NFC.swift:44-53` vs `:81-91`);
    - `fetchRecords` hardcodes `photographer: ""` on every decoded row (`:145`) —
      no join is ever performed — so `RecordBubbleView.swift:42` renders
      `"Photographer: "` with nothing after it on every SD row;
    - **SD-card photographer SEARCH can never return a row** — it issues
      `.eq("photographer", …)` against the nonexistent column, PostgREST errors, and
      the catch falls back to cached rows whose `photographer` is `""`
      (`SearchView.swift:360`; fallback `DatabaseManager+NFC.swift:162`, `:225`);
    - **the "Photographer Activity" chart is unconditionally empty in SD Card
      mode** — it groups by `$0.photographer` then drops empty names
      (`StatisticsView.swift:852`, `:857`), rendering a titled chart with no data and
      no empty-state text (`:698-721`).

    The photographer PICKERS in `FormView.swift:41-45` and `ManualEntryView.swift:93-98`
    are therefore real controls whose value is thrown away server-side. A redesign
    that "preserves" these keeps a broken feature; one that drops them removes
    controls that look functional today. **This is an operator decision, not a
    design one.**
27. **The toast's three call sites are actually two, and the shell inventory's
    reasoning was structurally wrong.** Repo-wide there are exactly two `.toast(`
    call sites — `MainEmployeeView.swift:689` and `NFC/ScanView.swift:278`. There is
    no `DailyJobReportView.swift`; the daily-report toast is posted as a
    notification (`Reports/DailyReportView.swift:1352`) and rendered by the
    **MainEmployeeView** site (`:690-693`). So only ScanView gets the shell's 84pt
    inset, and the **bare** site is the one that fires on every successful daily
    report. The open device check is narrower and more routine than recorded.
28. **`TimeEntryDetailView` (245 lines) and `TimeTrackingButton` (127 lines) are
    dead** — zero call sites, only their own previews. `TimeTrackingButton`
    nonetheless holds 2 allowlist cards, so the gate is guarding dead pixels. And
    `TimeEntryDetailView:38,41` carries **the only copy anywhere that explains the
    30-day edit window to a photographer**; deleting the screen loses that sentence.
29. **A fetch failure is rendered as an empty state on at least six screens**, three
    of them payroll- or manager-critical: `SessionSelectionView.swift:145-149`
    ("No sessions assigned for today" + "You can still clock in without selecting a
    session" — inviting an unattributed clock-in), `TimeEntryListView.swift:258-264`
    ("No time entries for pay period" — payroll appearing to be zero),
    `UnflagUserView.swift:52-65` (a green "All users are currently in good standing"
    rendered **during** the fetch, because there is no loading state at all),
    `PhotoCritiqueListView` ("No Training Photos Yet"),
    `NFCSessionSelectionView.swift:26-35`, and `SchoolInfoListView`'s per-row
    mileage (`--` for both a failure and a genuine zero).
30. **Three functionally identical `UIActivityViewController` wrappers exist under
    three names**, and the cross-feature one is the coupling to watch: `ShareSheet`
    is declared inside the **Yearbook** module and consumed by
    **`Training/PhotoCritiqueDetailView.swift:61`** as well as by Yearbook itself.
    `MetricsShareSheet` is private to `Settings/MetricsDashboardView.swift:188`;
    `ImageShareSheet` is in `Chat/Views/FullScreenImageViewer.swift:223`.
    **The line number already moved while this inventory was being written** — the
    AMB.10 conversion running in parallel shifted the declaration from
    `YearbookChecklistView.swift:297` to `:243` between two reads, which is precisely
    why this is recorded as a coupling and not as a location. **The durable statement
    is that Training depends on an app-level activity-sheet wrapper it does not
    own**, and that a Yearbook conversion which moves, renames or file-privates that
    declaration breaks Training at compile time.
31. **`AllFeaturesView`'s `.task` installs a 1Hz timer after an `await` without
    checking `Task.isCancelled`** (`:148-151`, `:230-238`) — the exact leak the
    AMB.4 widget documents and guards against (`DashboardWidgets.swift:59-74`).
    Three independent 1Hz timers for one clock can be live at once (the service's
    at `TimeTrackingService.swift:512`, this one, and HoursWidget's at
    `DashboardWidgets.swift:283`).
32. **Permission checks barely exist in batch 4.** Across `NFC/`, `JobBox/`,
    `Settings/`, `Training/` and all nine time-tracking screens there is **not a
    single `Permissions.has` call** (verified by repo-wide grep). The only gates are
    `AllFeaturesView.swift:95` (section-level, `users:edit`) and the in-view guards
    in `FlagUserView.swift:32` / `UnflagUserView.swift:21`. `featureView(for:)`
    re-checks nothing, so any write to `tabBarManager.selectedTab` opens the Job Box
    Tracker or Statistics regardless — the same hole batch 3 recorded for Stats.
    Server-side RLS is the real boundary throughout.
33. **The drift gate has rows for four AMB.11 files and ten AMB.12 files, and its
    silence over everything else means nothing.** Unallowlisted-but-unconverted
    files in this batch include `RecordBubbleView`, `JobBoxBubbleView`,
    `NFCContainerView`, `WriteNFCView`, `NFCSessionSelectionView`,
    `ManagerJobBoxTrackerView`, `JobBoxSettingsView` and every auth screen — they
    use `.background(...) + .cornerRadius(...)`, the shape the gate does not match
    (`scripts/check_card_drift.py:116-120`). This is the AMB.5 lesson in its fourth
    consecutive phase.

---

## Scope reconciliation

| Directory / surface | Files | Lines | Views | Phase by plan | Allowlist rows | Notes |
|---|---|---|---|---|---|---|
| `NFC/` | 17 | 5,373 | 18 | **AMB.11** | 4 files (`ScanView` 2, `StatisticsView` 6, `JobBoxNotification` 2, `DeleteConfirmationAlert` 1) | The "18 views" figure is exactly this directory |
| `JobBox/` | 3 | 575 | 2 | AMB.11 — **SHIPPED 2026-07-29** | none | Rules + meter + card; converted, out of scope |
| `Manager Features/` | 8 | 2,682 | 7 | AMB.12 by directory; job-box half is AMB.11 by feature | none | `ManagerMileageView` already deferred to AMB.12 by operator ruling |
| `Settings/` | 14 | 3,269 | 13 | AMB.12 | 2 (`EmployeeInfoView` 1, `SchoolDetailView` 3) | `PTOBalanceView` already converted by AMB.8 |
| `Training/` | 6 | 864 | 6 | AMB.12 | 3 (the three component cards) | |
| Time tracking | 10 | 2,662 | 10 | **NO PHASE** | 3 (`TimeTrackingMainView` 2, `TimeEntryListView` 2, `TimeTrackingButton` 2) | 2,540 across the nine the plan names, + `NotesInputView` 122 |
| Shell orphans | 6 | ~850 | 6 | **NO PHASE** (PART THREE) | 3 (`AllFeaturesView` 1, `LoadingOverlay` 1, `AddressAutocompleteField` 2) | |

The gate currently reports **30 files, 60 hand-rolled cards, "Card drift: clean."**
AMB.11 owns 11 of those cards; AMB.12 owns 17. Both are shrink-only and must reach
zero. **An empty allowlist row means nothing about whether a surface is converted**
(§0.33).

---

# PART ONE — AMB.11: Job box / NFC, the remaining surface

Files read completely: `NFC/` all 17 files (5,373 lines, 18 View structs);
`JobBox/` all 3 (575 lines, already shipped); `Manager Features/JobBoxStatus.swift`
(315), `ManagerJobBoxTrackerView.swift` (957), `JobBoxSettingsView.swift` (217);
`Services/DatabaseManager+NFC.swift` (817). Live DB checks run against the shared
project.

**Surface count for the redesign: 4 full screens + 5 container tabs + 2 manager
screens + 7 reusable sub-surfaces.**

## 1.0 What ALREADY SHIPPED — freeze, do not redesign

The progress-meter slice shipped, was pushed and was operator-smoked 2026-07-29
(`be68ed4..2c199a2`, "works perfect").

| Artifact | file:line | Status |
|---|---|---|
| `JobBoxTripStage` + `.meterTint` / `.meterIcon` | `JobBox/JobBoxProgressMeter.swift:44-71` | DONE — stage colours + SF Symbols are the single vocabulary |
| `JobBoxProgressReading.meterTint` / `detailLine(relativeTo:)` / shared `meterRelative` formatter | `:73-91` | DONE — formatter is a `static let`, not per-body |
| `JobBoxProgressReading.init(rows:)` | `:102-109` | DONE — unmapped status rows are DROPPED, not guessed |
| `JobBoxProgressMeter` (scrubber: rail, puck, 4 notches; `compact` variant) | `:115-191` | DONE — geometry inside `GeometryReader`; a11y label `:161-162`, `:186-190` |
| `JobBoxProgressCard` | `:197-242` | DONE — already uses `AmbientSectionTitle` (`:207`) and `.ambientCard(density:.roomy, fillWidth:true)` (`:240`). Consumer is `Schedule/ShiftDetailView.swift:677` |
| The rules layer (`currentTrip`, `state`, `positionFraction`, `headline`, `holder`, `skipNote`, `scannedCount`, `skipped`) | `JobBox/JobBoxProgressRules.swift:55-222` | DONE + 60 checks via `scripts/test_jobbox_progress_rules.sh` |
| The tracker's `statusMeterView(for:)` | `ManagerJobBoxTrackerView.swift:829-848` | DONE — meter capped at 116pt, tinted headline, `"N/4"` badge when `reading.skipped` is non-empty |
| `JobBoxWithEvent.log` / `.reading` | `:21-31`, populated `:225-227`, `:253-257` | DONE |
| `JobBoxPickupRules` | `JobBox/JobBoxPickupRules.swift:20-111` | DONE as logic, tested by `scripts/test_jobbox_pickup_rules.sh` |

**Two constraints this creates:**
- `JobBoxProgressRules.swift` is **SwiftUI-free by design** and its test harness
  depends on that. A redesign must not add `Color`/`Font` to it.
- Two rules are load-bearing and tested: **position is not completeness** (fill
  shows where the box IS; each notch shows whether a scan exists), and **progress
  means the CURRENT TRIP** (the log is cut at the last Packed, because the tracker
  groups by box number across all time).

The old bars were deleted in the same commit — the shift detail's stepper plus
four helpers and three `@State` fields, and the tracker's private copy with a
**different colour map**. Tombstone at `ManagerJobBoxTrackerView.swift:944-949`.

## 1.1 Reach, nav ownership, theme

| Fact | Evidence |
|---|---|
| Feature registration | `FeatureItem(id: "scan", title: "Scan", systemImage: "wave.3.right.circle.fill", description: "Scan SD cards and job boxes")` — `MainEmployeeView.swift:114` |
| Dispatch | `case "scan": NFCContainerView()` — `:962-963` |
| Nav ownership | **Shell-wrapped.** `scan` is not in `isSelfNavFeature` (`:765-779`), so `featureContainer` (`:753-758`) supplies `NavigationView` + `.homeToolbarItem()` + `.tabBarClearance(...)` + `StackNavigationViewStyle` |
| Bottom bar | Permanent CENTRE button on iPhone — `centreID = isIPad ? "home" : "scan"` (`BottomTabBar.swift:193`), symbol `:200`, tint `FeatureTheme.color(for:"scan")` `:207`. Excluded from ordinary cells (`:707`, `TabBarItem.swift:317`) and force-re-added if a saved config lacks it (`TabBarItem.swift:279-292`). Default entry `order: 999` (`:109`), short title `"Scan"` (`:69`) |
| iPad | **No tab-bar slot at all** — All Features is the only route (§0.18) |
| All Features | `AllFeaturesView.swift:57-60` sets `tabBarManager.selectedTab`, re-entering through `featureContainer` |
| Dashboard widget | **none** targets `scan` |
| FeatureTheme | `#2AA7D8` — `DesignTokens.swift:57`, "Gear" family with `equipment` `#00A2C7` and `jobBoxTracker` `#0B8BA8`. **Never applied inside `NFC/`** (§0.16) |
| Availability gate | none — `isFeatureAvailable` (`MainEmployeeView.swift:257-267`) returns true under every org flag |
| Job Box Tracker | `FeatureItem(id:"jobBoxTracker", …)` `AllFeaturesView.swift:23` (and a dead duplicate `MainEmployeeView.swift:582`); dispatch `:1004-1005`; **shell-wrapped**; FeatureTheme `#0B8BA8` (`DesignTokens.swift:56`), applied today only as the AllFeatures tile circle — **the screen has no wash** |
| Job Box Settings | **sheet only**, from the tracker's unlabelled gear — `ManagerJobBoxTrackerView.swift:732-744`. No feature id, no theme, no other entry point |

**Colour collision to design around:** `#0B8BA8` is both the `jobBoxTracker`
feature colour AND `JobBoxTripStage.pickedUp.meterTint`
(`JobBoxProgressMeter.swift:57`). A wash in the feature colour would be
indistinguishable from a picked-up box's meter.

## 1.2 `NFCContainerView` — the five-tab sub-shell (206 lines)

**Layout:** `HStack` — content + a fixed **60pt vertical rail on the right**
(`:99`), `Color(UIColor.secondarySystemBackground)` with a 1pt leading hairline
`Color.gray.opacity(0.2)` (`:100-108`). 60pt on a 4.7" SE and on a 12.9" iPad
alike.

| Case | Label | SF Symbol (`:19-27`) | Hardcoded colour (`:29-37`) | Destination |
|---|---|---|---|---|
| `.scan` | `"Scan"` | `wave.3.right.circle.fill` | `.orange` | `ScanView()` `:46` — **bare** |
| `.search` | `"Search"` | `magnifyingglass` | `.blue` | `SearchView(initialStatus:initialIsJobBoxMode:)` `:48-51` — **bare** |
| `.stats` | `"Stats"` | `chart.bar.fill` | `.green` | `NavigationView { StatisticsView(onNavigateToSearch:) }` `:53-61` |
| `.writeNFC` | `"Write NFC"` | `pencil.circle.fill` | `.purple` | `NavigationView { WriteNFCView() }` `:63-65` |
| `.manualEntry` | `"Manual Entry"` | `square.and.pencil` | `.teal` | `NavigationView { ManualEntryView(onCancel:) }` `:67-73` |

Controls: five `ToolbarButton`s (`:80-89`) with `withAnimation(.spring(response:0.3, dampingFraction:0.7))`;
`matchedGeometryEffect(id:"selection")` sliding a `RoundedRectangle(cornerRadius:12)`
at `feature.color.opacity(0.2)` (`:134-137`); `Divider()` between items except the
last (`:91-94`); icon 24pt (`:140`) tinted `feature.color` when selected else
`.gray` (`:141`); press scale 0.85 (`:142`) via `PressedButtonStyle` (`:162-172`);
label `.caption2`, `lineLimit(2)`, `.frame(width: 50)` (`:147-152`) — **"Manual
Entry" and "Write NFC" wrap to two lines at 50pt, nothing else does**;
`.accessibilityLabel(feature.rawValue)` (`:157`).

**No gestures, no swipe between tabs, no toolbar items, no sheets, no alerts, no
refreshable, no searchable.** The container sets `.navigationBarTitleDisplayMode(.inline)`
(`:110`) but **no `navigationTitle`**, so the shell bar's title is empty on the
Scan and Search tabs.

Cross-tab deep link (the only working one): Statistics' `onNavigateToSearch`
closure (`:54-60`) sets `selectedFeature = .search`, `initialSearchStatus`,
`initialIsJobBoxMode`. These are plain `@State` fed as **init parameters**
(`:48-51`), so they land on re-creation but will not propagate to an
already-showing Search.

**States: loading, empty, error and offline are ALL ABSENT** at container level.
Lifecycle: `.onAppear` applies `initialFeature` (`:111-115`) — dead (§1.14 N2). No
`.onDisappear`, no `.task`, no subscriptions.

## 1.3 `ScanView` (730 lines)

Title `.navigationBarTitle("Scan")`, `.inline` (`:294-295`). Background
`Color(UIColor.systemBackground).ignoresSafeArea()` (`:51-52`).

### Controls — the complete set is SIX
| Control | Line | Behaviour |
|---|---|---|
| **Scan Tag** disc, 200×200, orange `LinearGradient` topLeading→bottomTrailing, `Circle()` fill, shadow `black 0.2/r10/y5` | `:89-118` | `nfcReader.beginScanning()` |
| SD sheet → `FormView(cardNumber:selectedSchool:selectedStatus:localStatuses:lastRecord:onSubmit:onCancel:)` | `:181-225` | |
| Job Box sheet → `JobBoxFormView(boxNumber:selectedSchool:selectedStatus:lastRecord:onSubmit:onCancel:)` | `:226-271` | |
| Alert `"Info"` | `:272-276` | validation errors only |
| Loading overlay (modal scrim, non-dismissible) | `:277` | |
| Toast (bottom, 3s, `.padding(.bottom, 50)`) | `:278` | |

**No toolbar items, no swipe actions, no `.refreshable`, no `.searchable`, no
gestures beyond the one button.** The offline banner and the Job Box Alert banner
are **not tappable** — `JobBoxNotification` has no button, no `onTapGesture`, no
link (`JobBoxNotification.swift:6-86`). It reports a problem with no route to fix it.

### Every displayed literal
`wifi.slash` `:58` · `"Offline Mode"` `:61` · `"• Sync Pending"` yellow `:66` ·
`"Tag #\(cardNumber)"` 32pt bold `:84` · `wave.3.right.circle.fill` 80×80 white
`:93-97` · `"Scan Tag"` `.title2.bold()` white `:99-101` · a11y `"Scan Tag"` / hint
`"Tap to scan an NFC tag"` `:119-120` · `nfcReader.errorMessage` verbatim, red, in
a `systemGray6` box `:122-133` · alert `"Info"` `:273` / `"OK"` `:275` ·
`"Card/Box number cannot be empty"` `:439` · `"Photographer cannot be empty"` `:444` ·
`"School cannot be empty"` `:449` · `"Status cannot be empty"` `:454` ·
`"Fetching job box history..."` `:152` · `"Fetching card history..."` `:155` ·
`"Saving card data..."` `:197` · `"Saving job box data..."` `:242` ·
`"User organization not found."` `:477`, `:532` · `"Failed to save record: …"` `:512` ·
`"Failed to save job box record: …"` `:596` · `"Could not fetch card history. Starting fresh."` `:655` ·
`"Could not fetch job box history. Starting fresh."` `:707` · **`"Iconik"`** —
hardcoded studio school name when the last SD status was "cleared" `:623`.

Status vocabularies, both hardcoded here:
`localStatuses = ["Job Box","Camera","Envelope","Uploaded","Cleared","Camera Bag","Personal"]` (`:40`)
and `jobBoxStatuses = ["Packed","Picked Up","Left Job","Turned In"]` (`:41`).

### The routing rule (the core business logic)
`:146-158`, on `nfcReader.$scannedCardNumber`:
`if let intNumber = Int(number), intNumber >= 3001` → JOB BOX, `else` → SD CARD.

- Any tag text that is **not an integer** falls to the SD path.
- Any integer **below 3001** — including 0, 1, 2500 — falls to the SD path.
  `WriteNFCView` enforces 1001–2000 for SD and ≥3001 for boxes (`:106-116`), but
  **the read path enforces nothing**; tags written outside the app are silently
  classified.
- The 3001 boundary is duplicated at `ScanView.swift:151`, `WriteNFCView.swift:106`
  and in the placeholder string `WriteNFCView.swift:41`. **No shared constant.**

### Status auto-advance (a feature that is easy to lose)
**SD** (`:628-638`): `defaultStatuses` = `localStatuses` minus `"camera bag"` and
`"personal"` → a 5-ring `Job Box→Camera→Envelope→Uploaded→Cleared`; pre-selects
`(index+1) % 5`; unknown/absent → `"Job Box"`. **"Camera Bag" and "Personal" are
choosable in the form but never auto-advanced to**, and a card sitting in either
falls back to "Job Box" rather than to its successor.
**Job box** (`:682-689`): `(index+1) % 4`; unknown → `"Packed"`.
**School pre-fill** (`:620-647`, `:678-695`): SD takes the last record's school
except that a last status of `"cleared"` forces `"Iconik"` (`:622-623`); with no
prior record it takes the alphabetically-first school from the `UserDefaults`
`"dropdownRecords"` cache. Job box takes the last record's school/school_id; **no
prior record leaves school AND status both empty**, deliberately, so the form's
session picker supplies them (`:692-694`).

### "Job Box Alert" filter logic — `checkForLeftJobBoxes()` (`:346-431`)
1. Guard on non-empty org id **and** non-empty `@AppStorage("userFirstName")`, else
   print and return silently (`:350-353`).
2. `fetchJobBoxRecords(field:"all", value:"", organizationID:)` — **fetches every
   job box row in the org, unpaginated** (`:362`).
3. Group by `boxNumber` (`:368`), take max-timestamp per box (`:375`).
4. Keep only `mostRecent.jobBoxStatus == .leftJob` (`:376`) **and**
   `mostRecent.scannedBy.lowercased() == currentUserName.lowercased()` (`:378`) —
   matched on **first name string, not user id**. Two photographers sharing a first
   name see each other's alerts; a spelling mismatch sees none.
5. Threshold `debugMode ? 300.0 : 43200.0` seconds (`:410`) — 5 min vs **12 h**.
6. Sort descending by elapsed (`:419`).

### States
| State | Present? | Evidence |
|---|---|---|
| Loading | **Yes** — full-screen scrim with four distinct messages | `:277`, `:152/155/197/242` |
| Empty | N/A — no list |
| Error (NFC) | **Yes, twice at once** — inline red box (`:122-133`) AND a red toast (`:279-293`), same source; auto-cleared after 10s (`:287-291`) |
| Error (fetch) | **Degraded only** — red toast, then the form opens anyway with no history (`:650-659`, `:702-719`) |
| Error (save) | Yes — red toast, form stays open (`:511-516`, `:595-600`) |
| Offline | **Yes** — red banner + optional "Sync Pending" (`:56-77`). The only NFC screen besides Search with one |
| **Org id missing** | **SILENT** — `fetchLastRecord`/`fetchLastJobBoxRecord` return with only `isLoading = false` and no message (`:607-610`, `:664-668`) |
| **Empty sheet** | **Reachable** — both sheet bodies are `if let` with no `else` (`:188`, `:233-234`) |
| NFC unavailable | Only via `errorMessage` — `"NFC scanning is not supported on this device."` (`NFCReaderCoordinator.swift:12`). **No pre-emptive disabling or hiding of the Scan button on hardware without NFC** |

### Lifecycle
`.onAppear` (`:160-174`): decode the schools cache and default the school;
`checkForLeftJobBoxes()`; `setupJobBoxListener()`. `.onDisappear` (`:175-180`):
remove the listener, nil it, clear `errorMessage`. Realtime (`:299-340`): channel
`job_boxes_scan_<orgID>`, `postgresChange(AnyAction, table:"job_boxes", filter:"organization_id=eq.<orgID>")`,
two unstructured `Task`s — one consuming the stream forever, one subscribing.
`ListenerRegistrationWrapper` only wraps `channel.unsubscribe()`
(`Utilities/SupabaseRealtimeWrapper.swift:7-17`), so **the `for await` Task is
never cancelled** (`:320-329`). **Every realtime event re-runs the full-table
`checkForLeftJobBoxes()`** (`:326`) — an org-wide fetch per row change.

## 1.4 `WriteNFCView` (271 lines)

Reached only from the rail's "Write NFC" tab, inside a **nested** `NavigationView`.
Title `"Write NFC"` `.inline` (`:76-77`).

Controls: segmented `Picker "Item Type"` — `"SD Card"` / `"Job Box"` (`:29-33`),
`.onChange` clears the number and re-fetches the suggestion (`:35-39`); `TextField`
`.numberPad`, `secondarySystemBackground`, radius 8, `maxWidth: 300` (`:41-46`);
the Write button, orange, full-width, radius 10 — **which becomes a bare
`ProgressView()` while `isSaving`** (`:57-69`), i.e. the button vanishes rather
than dims; `.alert` (`:92-100`) whose OK action `dismiss()`es **only if
`alertMessage.contains("successfully")`** (`:96-98`) — string-matched control flow.

Literals: `"Write to NFC Tag"` `.title` `:24` · placeholder
`"Enter Job Box Number (3001+)"` / `"Enter SD Card Number (1001-2000)"` `:41` ·
`"Suggested SD Card Number: \(n)"` `:50` / `"Suggested Job Box Number: \(n)"` `:53` ·
`"Write NFC"` `:61` · alert `"Info"`/`"OK"` `:93-95` ·
`"Please enter a valid job box number (3001 or greater)."` `:107` ·
`"Please enter a valid SD card number (between 1001-2000)."` `:113` ·
`"Unable to create NDEF payload."` `:126` · `"Unable to create type data."` `:138` ·
`"User organization not found."` `:158` · `"Job box record saved successfully."` `:178` ·
`"Failed to save job box record: …"` `:180` · `"SD card record saved successfully."` `:200` ·
`"Failed to save SD card record: …"` `:202`.

**Written payload** (`:122-151`): `languageCode = "en"`; status byte =
`UInt8(langData.count)` = 2; payload = `[0x02] + "en" + cardNumber`; type `"T"`,
`format: .nfcWellKnown`, empty identifier, one record. Symmetric with the reader's
parse (`NFCReaderCoordinator.swift:64-79`), which masks `statusByte & 0x3F`. **The
writer never sets the UTF-16 bit and never handles a non-`en` locale.**

**Write→save coupling:** `.onChange(of: nfcWriter.isWritingSuccessful) { if success { saveRecordAfterWriting() } }`
(`:78-82`). The seed record is saved with **`photographer: ""`, `school: ""`** and
status `"Packed"` (job box, `:167-171`) or `"Cleared"` (SD, `:190-193`).

**Suggestion logic** (`:209-271`): job box → `getHighestBoxNumber + 1`, error
fallback `"3001"`. SD → fetch **all** org records, max the parsed ints, `+1`, then
`max(1001, min(2000, suggestion))` — **so once the org reaches card 2000 the
suggestion pins at 2000 forever and pre-fills a duplicate number**. No records →
`"1001"`; error → `"1001"`.

States: loading **partial** (`isSaving` swaps the button; the suggestion fetch and
the NFC write itself have none). Error: alert only, including raw CoreNFC
`localizedDescription` (`:83-88`). **Offline ABSENT** — this view never reads
`OfflineDataManager`; writing a tag offline succeeds on the hardware and the record
silently takes the offline queue path while the alert still says "saved
successfully."

**Absent capabilities:** no way to READ a tag to confirm what was written; no
duplicate-number check before writing; no confirmation before overwriting a tag
that already holds a number.

## 1.5 `StatisticsView` (1,576 lines) — the largest file in the phase

Reached from the rail's "Stats" tab inside a nested `NavigationView`. Title
`"Statistics"` `.inline` (`:246-247`). No toolbar items.

### Controls
| Control | Line | Behaviour |
|---|---|---|
| Segmented `Picker("View Mode")` — `"SD Cards"` / `"Job Boxes"` | `:100-109` | recompute only, **no refetch** |
| Segmented `Picker("Time Frame")` — `Today`/`This Week`/`This Month`/`All Time` | `:117-125`, enum `:48-55` | recompute only |
| Legend row buttons, one per status | `:159-178` | `navigateToSearchView(status)` — **the only cross-screen navigation on this view** |
| Fallback bar-tap buttons | `:324-331` | same target |
| `.alert` `"Error"` / `"OK"` | `:252-256` | |

**No sort, no filter, no search, no refreshable, no share/export, no swipe
actions, no sheets.**

### Every literal
`"View Mode"`, `"SD Cards"`, `"Job Boxes"` `:100-102` · `"Time Frame:"` `:113` ·
`"Today"/"This Week"/"This Month"/"All Time"` `:49-52` ·
`"Job Box Status Distribution"` / `"Card Status Distribution"` `:131` ·
`"No data available"` `:137, :277, :345` · `"Total Job Boxes: n"` / `"Total Cards: n"` `:150` ·
pie slice `"\(Int)%"` `:300` · legend `"\(count) (\(%.1f%%))"` `:64, :173` ·
`"Average Time in Status"` `:192` · bar annotation `"%.1f hours"` under 24h else
`"%.1f days"` `:74-79` · `"Chart requires iOS 16+"` `:377` · `"Card Lifecycle"` `:203` ·
`"Card Lifecycle (Job Box → Cleared)"` `:439` · `"Average"/"Shortest"/"Longest"` +
`"%.1f days"` `:446-469` · `"Total completed cycles:"` `:537` ·
`"No complete card cycles found"` `:548` ·
`"Complete cycles go from Job Box to Cleared status"` `:551` ·
`"Job Box Process Time"` `:213` · `"Job Box Processing Timeline"` `:574` ·
`"Assignment Time"` / `"Packed → Picked Up"` / `"Completion Time"` /
`"Picked Up → Turned In"` + `"%.1f hours"` `:580-601` · axis categories
`"Assignment"` / `"Completion"` `:624, :630` · `"Photographer Performance"` `:224` ·
`"Photographer Activity"` `:691` ·
`"Job Box 'Left Job' Duration by Photographer"` `:235` ·
`"No 'Left Job' data available"` `:1406` · `"Average Time"` / `"Total Transitions"` /
`"Currently Left"` `:1428-1449` · `exclamationmark.triangle.fill` `:1420`.

### Exact number computations
**Time-frame windows** (`:1166-1210`, duplicated verbatim for SD and job box):
`.day` = same local day; `.week` = `dateComponents([.yearForWeekOfYear,.weekOfYear])` —
**locale-dependent first weekday**, force-unwrapped `:1176, :1199`; `.month` =
`dateComponents([.year,.month])`, force-unwrapped `:1181, :1204`; `.all` = no filter.

**Status distribution** (`:1212-1235` SD / `:1237-1260` JB): group by card/box →
take max-timestamp row per key → group by `status.lowercased()` → **`totalCards` is
a count of DISTINCT cards/boxes, not scans**. Label is `status.capitalized`.

**The pie chart is HAND-DRAWN, not Swift Charts.** `import Charts` is present
(`:2`) but the pie is a `PieSlice: Shape` building a `Path` with two `addArc`s
(`:1560-1577`), filled per slice (`:285-291`), slices starting at `-90°`
(`:1528-1543`). **No axes, no gridlines, no Charts legend** — the legend is
hand-built `HStack`s (`:157-180`). Slice labels are positioned by trig at
`0.35 × min(w,h)` (`:296-306`) in **white text over the slice fill** — over
`envelope #FFCC00` that is near-invisible. Slice percentage is `Int(...)` —
**truncated** (`:1531`) — while the legend shows `%.1f%%` (`:64`); the two disagree
by design (33% vs 33.3%) and sit side by side. `innerRadiusRatio: 0` (`:288`) =
solid pie, no donut.

**Average time in status** (`:1262-1314` / `:1316-1368`): per card/box, sum every
adjacent-pair interval `> 0` into a bucket keyed by the EARLIER record's status;
then push `now − lastRecord.timestamp` into the last status's bucket **only if
`0 < duration < 30 days`** (`:1296`, `:1350`). Mean = sum ÷ **number of interval
samples**, not number of cards (`:1308-1310`). So an open dwell inflates the mean,
and a card idle >30 days contributes nothing.

**Card lifecycle** (`:875-928`): for each card, for EVERY `"job box"` record find
the first later `"cleared"`; duration in days, **accepted only if `0 < days < 90`**
(`:900`). Chart plots `prefix(10)` (`:479`) as Swift Charts `BarMark` with a
blue→purple gradient and `AxisMarks(position:.leading)` (`:481-504`). **Overlapping
cycles are double counted** — the same "cleared" row can close several "job box"
starts for one card, because `subsequentRecords` is recomputed from the full sorted
list each iteration (`:889-894`).

**Job box timelines** (`:930-976`): only **adjacent** pairs count —
`packed→pickedUp` into `assignmentTimes`, `pickedUp→turnedIn` into
`completionTimes`, in hours, **accepted only if `0 < h < 168`** (`:949`, `:957`).
**A `Left Job` scan between pickup and turn-in destroys the completion pair.**
The process chart (`:619-647`) is the one chart with **explicit gridlines and
ticks** on X (`:634-640`).

**Photographer activity** (`:845-873`): metric is **DISTINCT box/card numbers**,
not scan count (`:862`, `:865`); skips empty names (`:857`); `prefix(5)` (`:871`).
**No Y-axis configured** (`:698-721`). Permanently empty in SD mode (§0.26).

**Photographer "Left Job" durations** (`:979-1097`): a run of `.leftJob` opens a
span. A **closed** span counts only if `hours >= 1` (`:1048`); an **open** span
(leftJob is the box's last record) increments `currentLeftJobBoxes` and adds
`now − start` **with no minimum filter at all** (`:1024-1036`). Mean = total ÷
transitions (`:1063`). **The headline "Average Time" therefore mixes completed and
still-open spans in one number** — not a like-for-like average. The
`else averageHours = totalLeftJobHours` branch (`:1066`) is unreachable, and the
`debugMode` disjunct (`:1085-1088`) is dead because the flag is never set true.

### States
| State | Present? |
|---|---|
| **Loading** | **ABSENT.** `isLoading` is set at `:1126, :1137, :1158` and **never read in `body`** — no spinner, no skeleton, no disabled controls. First paint shows all-zero cards |
| Empty | Partial — `"No data available"` `:137`, `:345`; `"No complete card cycles found"` `:548`; `"No 'Left Job' data available"` `:1406`. **ABSENT for Photographer Activity**, which is its permanent SD state |
| Error | Alert only. SD failure aborts everything (`:1157-1162`); job-box failure still computes SD stats (`:1147-1153`) |
| Offline | **No indicator.** SD silently comes from cache (`DatabaseManager+NFC.swift:185-192`); job boxes fail hard with `"Job box data not available offline"` (`:393-396`) |
| Stale | No last-updated stamp, no pull-to-refresh, no manual refresh |

Lifecycle: `.onAppear { loadData() }` (`:249-251`) — **fires on every appearance**
and re-pulls both tables whole; no guard, no `.task`, no cancellation.

## 1.6 `SearchView` (497 lines)

Reached from the rail's "Search" tab, or programmatically from a Statistics legend
tap. Rendered **bare** and declares **no `navigationTitle`** — the shell bar shows
an empty title with only the Home button.

### Controls
Segmented `Picker("Search Type")` — `"SD Cards"`/`"Job Boxes"` (`:82-96`), whose
`.onChange` clears the value, resets the field and wipes both result arrays ·
Segmented `Picker("Search Field")` — 4 segments ordered by
`searchFields.keys.sorted()`, giving `"Card/Box #"`, `"Photographer"`, `"School"`,
`"Status"` (`:48-53`, `:98-113`) · `TextField` (card-number field only),
`"Enter Box Number"`/`"Enter Card Number"`, `.numberPad` (`:115-119`) ·
`DropdownSearchField` ×3 — `"Select Photographer"`, `"Select School"`,
`"Select Status"` (`:120-149`) · `Button("Search")` orange `.title2`, loading
variant `ProgressView` + `"Searching..."` (`:151-172`) · **`.swipeActions`
destructive `Label("Delete", systemImage:"trash")`** on both list flavours
(`:197-204`, `:211-218`) · `.refreshable` (`:222-228`) ·
`ConfirmationDialogView` overlay `"Confirm Deletion"` / `"Delete"` / `"Cancel"`
(`:233`, config `:425-460`) · `.alert` `"Info"` / `"OK"` (`:235-239`) ·
`UIApplication.endEditing()` on Search tap (`:316`).

**No `.searchable`, no sort control, no export, no toolbar, no leading swipe, no
pagination.**

### Search coverage — the semantics differ per field
| Field | Predicate | Case |
|---|---|---|
| Card # (SD) | `.eq("card_number", value)` | exact string — `"0301"` ≠ `"301"`; **no partial or prefix match** |
| Box # (JB) | `.eq("box_number", value)` (`:379`) | exact |
| Photographer (SD) | `.eq("photographer", …)` on a **nonexistent column** | **always 0 results** (§0.26) |
| Photographer (JB) | `.eq("photographer", …)` — real column | exact, **case-SENSITIVE** |
| School | `.eq("school", …)` — the NAME string, not `school_id` | exact, case-sensitive |
| Status | **client-side**: fetch ALL org rows, group, take latest, compare lowercased (`:341-347`, `:387-393`) | case-insensitive; and it is a **"current status" search, not a history search** |

Status option lists are **hardcoded, not derived from data** (`:45-46`).
**`"Personal"` is offered in every SD picker and has ZERO live rows.** The same two
literals are re-declared in `ManualEntryView.swift:12-13` and
`JobBoxFormView.swift:35` — **three copies**, plus `ScanView`'s injected pair and a
sixth vocabulary in `StatusColors`.

Initial (unsearched) list = most recent 50, sorted client-side **after pulling
everything** (`:294`, `:307`).

### States
| State | Present? |
|---|---|
| Offline | **PRESENT and unique** — red banner, `wifi.slash`, `"Offline Mode"`, `"• Sync Pending"` (`:62-79`) |
| Loading | Only inside the Search button (`:152-162`). The initial fetch and `.refreshable` have none |
| **Empty** | **ABSENT.** An empty result renders a blank `List` plus a modal alert `"No records found."` (`:350-353`). The initial-fetch path shows nothing at all |
| Error | Alert titled **`"Info"`** — errors and successes share one alert with a non-error title (`:236`) |
| Delete failure | Same `"Info"` alert; the row is left in place (`:470-473`) |

Lifecycle (`:240-256`): `fetchInitialData()`, then if `initialStatus != nil` set
`isInitializingFromStatistics`, force job-box mode and the status field, then
**`DispatchQueue.main.asyncAfter(0.1)`** to clear the flag and search — a 0.1s
sleep used as a synchronisation primitive (`:251`). `fetchInitialData` calls
`listenForPhotographers` and `listenForSchoolsData` on **every appearance**, each
unsubscribing and re-subscribing a realtime channel. **No `.onDisappear`, no
teardown.**

## 1.7 `ManualEntryView` (675 lines)

Reached only from the rail's "Manual Entry" tab, in a nested `NavigationView`, with
`onCancel` springing back to `.scan`. Title `"Manual Job Box Entry"` /
`"Manual SD Card Entry"` `.inline` (`:255-256`).

Controls: segmented `Picker("Entry Type")` `"SD Card"`/`"Job Box"` (`:49-70`) whose
`.onChange` resets the number, forces `"Packed"` in JB mode, clears both
last-records and the session, and reloads schools · `TextField`
`"Enter 4-digit Box Number (3001+)"` / `"Enter 4-digit Card Number"` `.numberPad`
(`:75-88`), whose `.onChange` **auto-fetches the last record the instant
`count == 4`** · `Picker("Photographer")` (`:93-98`) · session row button
`"Select Session"` gated on a valid 4-digit number (`:104-138`) →
`NFCSessionSelectionView` sheet · **`SearchableSchoolPickerString`** — a sheet with
`.searchable(prompt:"Search schools...")`, an `arrow.clockwise` refresh toolbar item
and `"Done"` (`:168-174`) · `Picker("Status")` (`:178-195`) whose `.onChange`
forces school `"Iconik"` on `cleared` (SD) and `turned in` (JB) · two mutually
exclusive `Toggle`s `"Uploaded from Jason's house"` / `"Uploaded from Andy's house"`
gated on SD + status `uploaded` + a **hardcoded org id `"T6XeeaUNoOp8VJqq36wi"`**
(`:198-209`) · `Cancel` / `Submit` (`:221-249`, disabled unless the number is 4
digits) · toolbar refresh (`:257-269`) · `.refreshable` (`:271-273`) · `.alert`
`"Info"`/`"OK"` (`:274-278`) · **pickup-warning `.alert`** with dynamic title
`"Check This Pickup"`, destructive `"Pick Up Anyway"` / `"Save Without a Session"`,
cancel `"Go Back"` (`:279-291`).

Section headers: `"Job Box Information"`/`"Card Information"` `:74`,
`"Photographer"` `:92`, `"Session Assignment"` `:103`, `"Additional Information"`
`:162`. Body strings: `"Select Session"` `:109`,
`"Choose from available sessions in the next 2 weeks"` `:113`, `chevron.right`
`:133`, `"Loading schools..."` `:165`, `"Status"` `:178`,
`"Enter a valid 4-digit box/card number to load additional information."` `:213`.
Results: `"Please enter a valid 4-digit box/card number."` `:507`,
`"Please select a session for this job box"` `:514`,
`"User organization not found."` `:544, 630`, `"SD Card record saved"` `:562`,
`"Job Box record saved"` `:665`, `"Failed to save record: …"` `:567`,
`"Failed to save job box record: …"` `:670`.

**Business rules encoded here** (and duplicated elsewhere — see §1.14):
SD status auto-advance `:425-458` (last `"camera bag"` → `"Camera"`; last
`"personal"` → `"Cleared"`; else the 5-ring; `"cleared"` forces school `"Iconik"`);
JB auto-advance `:460-501` (4-ring; `turnedIn` forces `"Iconik"`; session
pre-select suppressed for `.turnedIn` and `packed`, `:481-486`); shiftUid
inheritance `:639-650`; pickup verification `:587-623` which **fails OPEN** on
offline or lookup error; session-required guard for brand-new boxes `:513-517`.

States: schools loading yes (`:165`, `:261`); **submit loading ABSENT** (Submit only
greys, `:246`); **session loading ABSENT** — the sheet shows its "no sessions" empty
state while the fetch is in flight; **photographer empty ABSENT**; session-load
failure is **print-only** (`:388`); **offline ABSENT** on this screen; **the form is
not cleared after a successful save** (`:561-565`, `:664-668`), so a second Submit
re-inserts the same values.

Lifecycle `.onAppear` (`:299-302`): `loadInitialData()` reads both caches, calls
`refreshSchoolsFromServer` **and** `listenForSchoolsData` (which itself fetches
first), plus `listenForPhotographers` — **three school round-trips plus a users
fetch per appearance**. No teardown.

## 1.8 `FormView` (220 lines) — the SD sheet

**Not** on the rail. A `.sheet` presented by `ScanView` after a successful SD read
(`ScanView.swift:181-223`); only call site. Title `"Enter Info"` (`:132`) — **but
the sheet content has no `NavigationView`, so the title has no bar to render into.**

Controls: `Picker("Photographer")` `:41-45` · `Picker("School")` — **a plain
`Picker`, not the searchable one Manual Entry uses** `:48-52` · `Picker("Status")`
over the injected `localStatuses` `:55-59` whose `.onChange` forces `"Iconik"` on
`cleared` `:61-65` · the two house Toggles, same hardcoded org gate `:68-79` ·
`Cancel` `:85-97` · `Submit` `:99-126`.

Literals: `"Card Information"` `:35` · `"Card Number: \(n)"` `:36` ·
`"Additional Information"` `:39` · `"Photographer"`/`"School"`/`"Status"`
`:41,48,55` · the two house toggles `:70,75` · `"Cancel"` `:89` · `"Submit"` `:99` ·
`"Enter Info"` `:132` · `"Submission failed. Please try again."` `:112` · `"OK"` `:176`.

States: loading **ABSENT locally** (the caller raises the global overlay,
`ScanView.swift:196`); empty **ABSENT** — an empty School picker if schools have
not arrived, where Manual Entry at least says `"Loading schools..."`; the alert at
`:172-180` is **titled `Text("")`** — empty on both branches, so the alert shows a
message with no heading; offline **ABSENT**.

## 1.9 `JobBoxFormView` (346 lines) — the job box sheet

A `.sheet` from `ScanView` (`:224-269`); only call site. Title `"Job Box Entry"`
`:152` — again **no enclosing `NavigationView`**.

Controls: `Picker("Photographer")` `:45-49` · **`Picker("Select Session")` rendered
only when `!availableSessions.isEmpty`** `:52-80`, with a `"None"` tag and an
`HStack/VStack` label; `.onChange` sets school, schoolId and forces `"Packed"` for a
new box `:69-79` · school is **read-only text when a session is selected**,
otherwise a plain `Picker` `:83-97` · `Picker("Status")` `:100-104` · `Cancel`
`:110-122` · `Submit` `:124-135` which routes through `checkPickupThenSubmit()`
when the status is `"Picked Up"` · `.alert` `"Error"`/`"OK"` `:159-165` ·
pickup-warning `.alert` `:166-178`.

Literals: `"Job Box Information"` `:39` · `"Box Number: \(n)"` `:40` · `"Details"`
`:43` · `"Select Session"` `:53` · `"None"` `:54` · `"School"` `:85, 92` ·
`"Status"` `:100` · `"Job Box Entry"` `:152` · `"Error"`/`"OK"` `:161-163` ·
`"Submission failed. Please try again."` `:242` · `"Go Back"` `:175`. Session time
format `"h:mm a"`, or `"MMM d, h:mm a"` when only a start exists, empty when neither
(`:335-346`).

Rules: `updateDefaults` `:314-333` — a new box deliberately gets
`selectedStatus = ""`. `updateAvailableSessions` `:291-312` — sorts by
`startDate ?? Date()`, pre-selects the box's current-trip session unless the last
record is `.turnedIn`, else auto-selects when exactly one session exists.
`effectiveTargetShiftUid` `:184-192` and `checkPickupThenSubmit` `:194-229` mirror
`ManualEntryView` exactly. `performSubmit` `:231-248` passes **only
`selectedSession?.id`** as `shiftUid` — the inheritance rule computed for the CHECK
is applied for the SAVE in `ScanView`, not here (`:181-183` asserts this).

States: submit loading **ABSENT locally**; **sessions loading ABSENT — while in
flight the session Picker is not rendered AT ALL** (`:52`) rather than shown
disabled, so the user cannot tell "still loading" from "no sessions", and this is
the control that links a box to a job; empty schools **ABSENT**; session-fetch
failure **print-only** `:309`; offline **ABSENT** (the pickup check silently
degrades to fail-open, `:209-211`).

## 1.10 `NFCSessionSelectionView` (166 lines)

Reached from **exactly one place**: `ManualEntryView.swift:292-298`.
**`JobBoxFormView` — the sheet `ScanView` actually presents — does NOT use it**; it
uses an inline `Picker` with a `"None"` tag (`JobBoxFormView.swift:53-68`). **Two
different session-choosing UIs over the same data.** Owns its own `NavigationView`
(`:24`).

Literals: title `"Select Session"` `:65` · `"Cancel"` `:67` · search prompt
`"Search sessions"` `:62` · empty-source `calendar.badge.checkmark` 60pt +
`"No available sessions in the next 2 weeks"` `:28-34` · empty-search
`magnifyingglass` 60pt + `"No sessions match your search"` +
`"Try adjusting your search terms"` `:40-50` · row time
`"\(startTime) - \(endTime)"` `:122` · `person.2.fill` `:132`.

**`.searchable` is attached to the `List`, not the `VStack`, so the search bar
DISAPPEARS in both empty states** (`:62` vs `:26-53`). Once a search yields nothing
you cannot edit the query — you must Cancel.

**Filter logic** (`:10-21`): OR across `schoolName` (case-insensitive), `date`
(**plain `contains` on the raw `"yyyy-MM-dd"` string**), joined photographer names,
and joined `sessionType`. **The row DISPLAYS a `.medium` date ("Jul 30, 2026",
`:82-91`) while the search matches the raw ISO string — typing "Jul" matches
nothing; you must type "07".**

Source window (`TimeTrackingService.swift:645-680`): published sessions, then
`status == "scheduled"` **and** today ≤ date ≤ today+14, sorted. The
"next 2 weeks" copy is accurate, but **the `status == "scheduled"` exclusion is
never surfaced**.

`Session.description` is **not a description field** — it returns `notes` if
present, else falls back to `position` (`Schedule/Session.swift:106-113`). So a
session with no notes shows **its type twice**: once in the blue pill, once in the
grey "notes" line.

States: loading **ABSENT** — the view receives a plain array, so during the
caller's fetch it shows "No available sessions in the next 2 weeks", **a lie during
load**; error **ABSENT** — `ManualEntryView.swift:386-388` swallows to `print`, so a
network failure is also reported as "no sessions". No lifecycle at all.

## 1.11 Sub-surfaces (all string-bearing, all reusable)

**`JobBoxNotification`** (109 lines) — the "Job Box Alert" banner, rendered only at
`ScanView.swift:136-139`. Orange→red gradient at 0.8, radius 12, white 0.2 stroke,
shadow `black 0.3/r10/y5` (`:66-85`). `exclamationmark.triangle.fill` yellow +
`"Job Box Alert"` (`:9-13`). **Singular** (`:20-34`):
`"Box #\(n) has been in 'Left Job' status for \(formatTime(diff))"` plus
`"School: \(school)"` when non-empty. **Plural** (`:35-63`):
`"\(count) job boxes have been in 'Left Job' status for over 12 hours"` — **a
hardcoded "12 hours" that is wrong whenever `ScanView.debugMode` is true**
(threshold 5 min) — then up to **3** rows `"• Box #\(n)"` + elapsed + indented
`"  \(school)"`, then `"...and \(count - 3) more"`. `formatTime` (`:88-109`):
`>24h` → `"\(d)d \(h)h"` or `"\(d) day"/"days"`; `>0h` → `"\(h)h \(m)m"` or
`"\(h) hour"/"hours"`; else `"\(m) min"`. **Boundary bug: the branch is
`hours > 24`, so exactly 24–24.99h renders "24 hours" not "1 day"** — and
`JobBoxBubbleView.formatTimeDifference` (`:68-76`) is a **second, different**
implementation with the same boundary. **No controls, no tap target, not
dismissible.**

**`ConfirmationDialogView` + `AlertConfiguration`** (`DeleteConfirmationAlert.swift:3`, `:14`)
— consumed only by `SearchView`. Hand-rolled modal: `Color.black.opacity(0.4)`
scrim, 300pt card, `systemBackground`, radius 12, `shadow(radius:10)`,
`.transition(.scale)` (`:19-75`). Optional secondary (grey, `minWidth:100`) and
primary (`isDestructive ? .red : .blue`). **All four labels come from the caller —
this file contains no user-facing string of its own.** **Dead control:** `:24-27` is
an `.onTapGesture { }` with a fully commented-out body — a scrim that visibly
accepts a tap and does nothing.

**`RecordBubbleView`** (64 lines) — SD history row, consumed only by
`SearchView.swift:208`. 10pt status `Circle()` tinted by `StatusColors`;
`systemGray6`, radius 12 (`:62-63`). `record.status` `.headline` in the status
colour; `formattedDate` `.medium` + `.short` from a **per-body `DateFormatter`**
(`:6-11`); `"School: \(school)"`; `"Photographer: \(photographer)"` — **empty for
every online-fetched record** (§0.26); and, only when status is `uploaded`,
**`"📍 Uploaded from Jason's house"` or `"📍 Uploaded from Andy's house"`**
(`:48-58`) — **two hardcoded personal names in shipped UI**, mutually exclusive via
`else if` so a record flagged for both shows only Jason.

**`JobBoxBubbleView`** (76 lines) — same shape with `isJobBox: true`.
`"School: \(record.school ?? "")"` — **renders the literal `"School: "` with nothing
after it when school is NULL**. When `.leftJob` and elapsed `> 43200`, an inline
`exclamationmark.triangle.fill` + `"Left for \(...)"` in orange (`:48-60`). **The
43200 constant is hardcoded a third time here** (`ScanView.swift:410` and
`JobBoxNotification.swift:36`'s "12 hours" are the others).

**`DropdownSearchField`** (31 lines) — **despite the name it contains no search
field**; it is a plain `Menu` over `[String]` (`:10-15`) with a label showing
`selectedText.isEmpty ? placeholder : selectedText` (`:18-19`) plus `chevron.down`,
inside a 5pt-radius grey stroke. **A long school list here has no filter of any
kind.**

**`ComingSoonView`** (`NFCContainerView.swift:175-198`) — **zero call sites
anywhere**, and it renders
`"This feature is being integrated from the NFC SD Tracker app"` (`:189`), an
internal note that would be visible to a photographer if anything ever routed to it.

**`ToolbarButton`** (`NFCContainerView.swift:126-160`) — the rail item, described
in §1.2.

## 1.12 `ManagerJobBoxTrackerView` (957 lines) — the manager screen

**Duplicate-title defect:** the shell supplies a nav bar, the view sets
`.navigationTitle("Job Box Tracker")` `.inline` (`:720-721`), AND the body's first
element is `Text("Job Box Tracker").font(.largeTitle).fontWeight(.bold)` (`:456-458`).
**The title renders twice.**

### Controls and literals
**Header** (`:455-466`): the duplicate title; `"\(viewModel.allJobBoxes.count) job boxes loaded"`
`.subheadline`/`.secondary` (`:461`) — counts **groups after filtering**, except in
card-number search mode where it counts raw rows (`:235`).

**Search bar** (`:469-490`): `magnifyingglass` (`:470`);
`TextField("Search schools, photographers or card #")` `RoundedBorderTextFieldStyle`
(`:473-474`); `.onChange` → **full network refetch, no debounce, per keystroke**
(`:475-477`); clear button `xmark.circle.fill` shown only when non-empty
(`:479-487`), **no accessibility label**.

**Primary filter pills** — horizontal `ScrollView` (`:493-546`). `JobBoxFilter` raw
values ARE the labels: `"All"`, `"Active"`, `"Stalled"`, `"Today"`, `"Completed"`
(`:48-54`). Selected `Color.blue` + white; unselected `Color.gray.opacity(0.2)` +
`.primary`; `cornerRadius(20)`, pad h12/v6 (`:501-505`). Plus `"Advanced"` toggle
(`line.horizontal.3.decrease.circle.fill`/`…circle`, `:510-526`) and `"Date Filter"`
toggle (`calendar`, `:528-542`).

**Advanced drawer** (`:549-578`), `Color.gray.opacity(0.05)`, `.transition(.opacity)`:
`Text("Status:")` (`:554`) and `JobBoxStatusFilter` pills — `"All Statuses"`,
`"Packed"`, `"Picked Up"`, `"Left Job"`, `"Turned In"` (`:65-70`). **The selected
pill here is `Color.green`, not blue (`:566`) — two selection colours for two pill
rows on one screen.**

**Date picker** (`:581-593`): `DatePicker("Filter by date", displayedComponents:.date)`,
`CompactDatePickerStyle()`, `.labelsHidden()` so the label never renders.
**`selectedDate` is never read by any query — see §1.14 T2.**

**Sort row** (`:596-635`): `Text("Sort by:")`; `Picker` `MenuPickerStyle` over
`JobBoxSort` raw values `"Newest First"`, `"Oldest First"`, `"School Name"`,
`"Photographer"`, `"Job Box Number"`, `"Status"` (`:56-63`); settings `gear` button
(`:613-621`) and refresh `arrow.clockwise` button (`:624-632`), both size 14,
`Color.gray.opacity(0.2)`, radius 8, **both with no label and no a11y label**.

**Row** (`:751-810`): line 1 `schoolName` `.headline` + `formatDate` `.medium`
(`:755`, `:761`) — **a `DateFormatter` constructed per call** (`:431-435`); line 2
`Label(photographerName, systemImage:"person.fill")` (`:768`) then a `"Box \(n)"`
`.caption` pill, `Color.gray.opacity(0.2)`, radius 10 (`:774-788`) — the
`"Card \(n)"` variant is unreachable (§1.14 T4); line 3 the converted meter plus
either `Label(timeSinceUpdate, systemImage:"exclamationmark.triangle")` `.orange`
when stalled or `"Updated \(timeSinceUpdate)"` `.secondary` (`:798-806`).
**`timeSinceUpdate` allocates a `RelativeDateTimeFormatter` per access** (`:41-45`)
— the one relative formatter NOT hoisted when the meter's was
(`JobBoxProgressMeter.swift:86-90`) — and it is called twice per row.
Row background (`:813-823`): stalled → `orange 10%`; else packed `blue 5%`,
pickedUp `purple 5%`, leftJob `orange 5%`, **default (comment says "Must be
.turnedIn") `green 5%`**.

**Swipe actions** (`:677-693`): `Label("Edit", systemImage:"pencil")` `.blue`;
`Label("Flag", systemImage:"flag")` `.orange`. Trailing only.
**Context menu** (`:694-712`): `"Edit Status"`, `"Flag for Attention"`, `Divider()`,
`"Last Updated: \(timeSinceUpdate)"`.
**Edit sheet** (`:849-886`): 5 detail rows, 2 status rows, `Section(header: Text("Update Status"))`
with 4 transition buttons + checkmark.
**Flag sheet** (`:899-942`): 6 detail rows, a `TextEditor`, an orange CTA — **all of
it dead (§0.6).**
**Loading** (`:646-651`): `ProgressView("Loading job boxes...")`.
**Empty** (`:652-671`): `"No job boxes found"` `.headline`/`.secondary` + a blue
`"Refresh"` button.
**Error** (`:638-643`): bare red `Text(errorMessage)` above the list. Strings:
`"Organization ID not set"` `:130`, `"Error loading job boxes: …"` `:180`,
`"Error updating job box: …"` `:397`, `"Error flagging job box: …"` `:424`.

### Filter / sort pipeline, in execution order
1. **Server, hardcoded 30-day window** (`:144`, `:171`) — never surfaced (§0.23).
2. **Server, org scope** (`:161`, `:170`), backed by RLS `job_boxes_org_access`.
3. **Server "Today" special case** (`:154-165`) — **but only when
   `!isSearchingByCardNumber`** (`:154`); a numeric search silently reverts Today to
   the 30-day window.
4. **Client search** (`:290-309`) — case-insensitive `contains` over school /
   photographer / boxNumber / cardNumber.
5. **Card-number-search short-circuit** (`:234-238`) — returns sorted **raw rows**,
   skipping grouping, status filter, stalled filter and active/completed entirely.
   **Typing `3028` shows every scan row for that box; typing `Lincoln` shows one row
   per box. Two different list semantics behind one text field, with no indicator.**
6. **Grouping** (`:241-244`) on `cardNumber.isEmpty ? jobboxNumber : cardNumber`;
   since `cardNumber` is hardcoded `""` (`:196`) the key is **always `box_number`**.
7. **Latest-per-group** (`:253`); full-log siblings re-attached from the
   **unfiltered** set (`:256`) — the fix for the search-filtered-history bug found
   during the meter slice.
8. **Status filter applied AFTER collapse** (`:263-267`), so it means "currently at
   status X", not "ever at X".
9. **Stalled filter** (`:270-272`) → `isStalled` (`:34-38`).
10. **Active / Completed** (`:275-281`).
11. **Sort** (`:312-332`); `.status` uses `statusPriority` packed 0 / pickedUp 1 /
    leftJob 2 / **everything else 3** (`:335-340`).

**Default first paint:** `selectedFilter = .active` (`:97`), `.newestFirst` (`:98`),
`.all` status (`:99`) — the screen opens **already hiding every turned-in box**,
with the "All" pill visibly unselected.

### States
| State | Present? |
|---|---|
| Loading / Empty / Error | Yes (`:646`, `:652`, `:638`) |
| **Offline** | **ABSENT** — the view never consults `OfflineDataManager.isOnline`; offline surfaces as a raw `URLError` string in red |
| **Empty-because-30-day-window** | **ABSENT** — indistinguishable from "no boxes exist" |
| **Empty-because-org-id-missing** | **ABSENT and misleading** — `setOrganizationID` guards `if !orgID.isEmpty` (`:121`) and returns silently, so `errorMessage` at `:130` is unreachable from `onAppear` and the screen says "No job boxes found" |
| Error + empty together | Unhandled — both render at once |
| **Error retry** | **ABSENT** — no retry affordance; the error clears only at the start of the next load (`:136`) |
| **Success confirmation** after a status edit or a flag | **ABSENT** — no toast, no haptic; the sheet dismisses immediately (`:872`, `:919`) |
| Realtime freshness | **ABSENT** — see below |

Lifecycle: `.onAppear` refetches on **every** appearance including return from a
sheet (`:745-747`). `.refreshable` (`:715-717`) is given a **synchronous** body that
fires a detached `Task` (`:146`), so the spinner retracts before data arrives.
**No realtime subscription on this screen** — `JobBoxService.listenForJobBoxes`
exists (`JobBoxStatus.swift:180-250`) but its only caller is
`Schedule/ShiftDetailView.swift:990`. **No `onDisappear`, no task cancellation** —
in-flight Tasks from rapid typing are never cancelled and the last to complete
wins.

**The tracker does not use `JobBoxService` at all** — it holds its own
`SupabaseClient` (`:113`) and issues raw queries. **Two query surfaces against one
table with different bounding rules.**

## 1.13 `JobBoxSettingsView` (217 lines) — sheet

Reached **only** from the tracker's unlabelled gear (`:732-744`); the sheet supplies
the `NavigationView`, the view supplies `.navigationTitle("Job Box Settings")`
(`:187`). No feature id, no theme.

`Form` with two sections. **Section 1**, header
`Text("Stalled Time Thresholds").font(.headline)` (`:102`):

| Block | Label | Slider | Readout | Caption |
|---|---|---|---|---|
| `:103-121` | `"Packed Status"` | `24...240, step 24` | `"\(Int(h/24)) days"`, `.frame(width:60)` | `"Job boxes in 'Packed' status will be marked as stalled after this time."` |
| `:123-141` | `"Picked Up Status"` | `24...240, step 24` | `"\(Int(h/24)) days"` | same sentence for 'Picked Up' |
| `:143-161` | `"Left Job Status"` | **`0.5...48, step 0.5`** | `"%.1f hrs"` | same sentence for 'Left Job' |

Each slider's `.onChange` calls `updateSettings()` → `:191-198`, which writes the
manager **and** `saveSettings()` to `UserDefaults` **on every intermediate drag
value**. **There is no Save and no Cancel.**

**Section 2** (`:164-185`): centred red `"Reset to Default Values"` (`:170`) →
`Alert(title:"Reset Settings", message:"Are you sure you want to reset all stalled time thresholds to default values?", primaryButton:.destructive("Reset"), secondaryButton:.cancel())` (`:176-183`).

**Persistence:** `JobBoxSettingsManager.shared` (`:18-79`), three `UserDefaults`
keys (`:24-26`). **Device-local, never synced** — two managers on two iPads see
different stalled sets from identical data. First-run detection is "all three are
0" (`:37`), so a user who deliberately sets all three to zero is re-defaulted next
launch. `getStalledThreshold` (`:59-72`): `.turnedIn → .infinity`,
**`.unknown → 3 * 3600` hardcoded with no UI**. Consumed at exactly one site
(`ManagerJobBoxTrackerView.swift:35`), read **directly rather than observed** — the
tracker holds no `@ObservedObject` on the manager, so `@Published stalledTimings`
drives no re-render; the list only reflects a change when "Done" fires
`loadJobBoxes()` (`:739`).

States: loading/empty/error/offline all **N/A or ABSENT** by construction, but
**there is no indication anywhere that these settings are device-local**, which is
the real information gap. **No unsaved-changes state and no Cancel** — every drag
tick commits, and Reset is the only undo.

## 1.14 The status model — one vocabulary, three colour maps

Canonical enum `Manager Features/JobBoxStatus.swift:13-19`; raw values are the exact
stored `job_boxes.status` text. **Live distribution (verified): Packed 674, Picked
Up 160, Turned In 159, Left Job 66; total 1,059; zero rows outside the four.**

| Status | Stage label | Meter tint | Meter icon | Row bg | `StatusColors` | Sort pri | Stall threshold |
|---|---|---|---|---|---|---|---|
| `.packed` `"Packed"` | `Packed` | `#7A8794` slate | `shippingbox.fill` | blue 5% | **`#007AFF` blue** | 0 | 48h default |
| `.pickedUp` `"Picked Up"` | `Picked up` | `#0B8BA8` teal | `hand.raised.fill` | purple 5% | **`#34C759` green** | 1 | 96h default |
| `.leftJob` `"Left Job"` | `Left job` | `#F09A2B` amber | `figure.walk.departure` | orange 5% | `#FF9500` orange | 2 | **192h default, slider max 48** (§0.15) |
| `.turnedIn` `"Turned In"` | `Turned in` | `#31A15D` green | `checkmark` | green 5% | `#8E8E93` grey | 3 | `.infinity` |
| `.unknown` `"Unknown"` | *(row DROPPED)* | fallback slate | fallback `shippingbox` | **green 5%**, via the default arm | `.gray` | 3 | 3h hardcoded |

**`.unknown` handling is self-contradictory:** the row background paints it green
(turned-in), `statusPriority` sorts it with turned-in, it gets a 3h stall
threshold, **no `JobBoxStatusFilter` case can isolate it** (`:65-70`), and the meter
**drops the row entirely** (`JobBoxProgressMeter.swift:104`) so the headline reads
`"Not scanned"` (`JobBoxProgressRules.swift:199`). One row: green background,
"Not scanned" text. No live rows trigger it today — latent.

**The SD-card vocabulary is separate and larger** (`StatusColors.swift:8-16`):
`job box #FF9500`, `camera #34C759`, `envelope #FFCC00`, `uploaded #007AFF`,
`cleared #8E8E93`, `camera bag #AF52DE`, `personal #5856D6`. Live counts: Job Box
1791, Cleared 944, Uploaded 921, Camera 272, Envelope 232, Camera Bag 8, **Personal
0** — offered in every picker, never used. Unknown → `.gray` / `#8E8E93`
(`:31-33`, `:60-62`).

`STATUS_COLORS_DOCUMENTATION.md:4` presents these as the standard "across all
Iconik platforms (iOS and Web)". **A redesign that re-tokenises them to AURA
breaks a stated cross-platform contract** — that is an operator decision, and the
decision must also settle whether `StatusColors` is retired or becomes
authoritative (§0.21).

**State machine.** `job_boxes` is append-only; the manager's four transition buttons
INSERT a new row (`ManagerJobBoxTrackerView.swift:348-401`) with `id` (fresh
lowercase UUID), `status`, `photographer` = `UserDefaults["userFirstName"] ?? "Manager"`
(`:361`), `timestamp` = now, `organization_id`, plus conditional `box_number`,
`shift_uid`, `school`, `school_id`, `user_id`. Rationale for insert-not-update at
`:351-360` — an update falsified the scan moment and skipped the crew push trigger.
**No transition validation at all** (§0.22).

**`JobBoxPickupRules` warning copy** (owned by an in-scope file, presented by NFC
screens): title `"Check This Pickup"` (`:29`);
`.wrongBox` `"This is box {scanned}, but box {packed} was packed for {school}. Make sure you have the right box."` (`:34`);
`.nothingPacked` `"No packed box is on record for {school}. Make sure you have the right box."` (`:36`);
`.noJobLink` `"This pickup isn't linked to a session, so the job's tracker won't show it.{ The box was last at {lastSchool}.} Go back and select a session, or save without one."` (`:38-39`);
confirm labels `"Save Without a Session"` for `.noJobLink` else `"Pick Up Anyway"` (`:44-48`).
Fail-open: `packedLookupFailed → nil` (`:104`); routine unlinked same-school pack is
silent (`:96-101`).

**Shipped meter strings** (freeze): `"Not scanned"` (`ProgressRules.swift:199`),
`"{list} never scanned"` (`:211-221`), `"no scans on this box"`
(`ProgressMeter.swift:80`), `"{who} · {when}"` (`:82`), `"N of 4 stages scanned"`
(`:187`), `"1 other box was scanned for this job"` / `"N other boxes…"` (`:233-235`).

## 1.15 What the data layer carries and its limits

All NFC screens go through `Services/DatabaseManager+NFC.swift` (817 lines).

| Call | Query | Limit / order |
|---|---|---|
| `fetchRecords` `:98-200` | `records` eq org + optional eq field | **NO `.limit()`, NO `.order()`** |
| `fetchJobBoxRecords` `:331-398` | `job_boxes` eq org + optional eq field | **NO `.limit()`, NO `.order()`**; **offline THROWS `"Job box data not available offline"` — there is no job-box cache**, unlike SD cards (`:388-392`) |
| `saveRecord` `:28-95` | `records` insert | `photographer` discarded online (§0.26); `uploaded_from_*` written only when status is `uploaded` (`:56-64`) |
| `saveJobBoxRecord` `:238-328` | `job_boxes` insert, then a best-effort `sessions` update setting `has_job_box_assigned` / `job_box_record_id` (`:287-291`) | **that update's failure is swallowed with a `print` and the save still reports success** (`:294`) |
| `deleteRecord` / `deleteJobBoxRecord` `:662-728` | `.delete().eq("id",…)` — **no org predicate in the client**; RLS is the guard | |
| `listenForPhotographers` `:401-435` | `users` eq org, `is_active = true`, cached to `UserDefaults["photographerNames"]` | realtime channel `photographers_<org>` |
| `listenForSchoolsData` / `refreshSchoolsFromServer` `:474-517` | `schools` eq org, order by name, cached to `UserDefaults["nfcSchools"]` | change-suppressed by `hasSchoolsDataChanged` `:628` |
| `getHighestBoxNumber` `:768-801` | max parsed `box_number` for the org | **returns 3000 when the org has no boxes** so the suggestion becomes 3001 |
| `JobBoxService.fetchLatestPackedRecord` | `JobBoxStatus.swift:155-177` | **the ONE limited query** — `.limit(1)` plus a 5s `withThrowingTaskGroup` timeout |

**Live payload:** `records` = 4,168 rows, **4,166 of them on one org**; `job_boxes`
= 1,059. Every Statistics visit pulls **both tables whole**; every status Search
pulls all 4,166 too.

**Type mismatch that happens to work:** `uploaded_from_*` are `boolean` columns;
`RecordDTO` decodes `Bool?` and maps to `"Yes"`/`nil` (`:120-121`, `:149-150`),
while `saveRecord` INSERTS the **string** `"Yes"` (`:58`). Postgres accepts `'Yes'`
as boolean true, so it round-trips — verified live: 586 non-null
`uploaded_from_andys_house`, 27 `uploaded_from_jasons_house`.

**`JobBox` model** (`JobBoxStatus.swift:22-75`) — 10 stored properties matching the
live table 1:1 (verified; no extras, no ghosts). `timestampDate` returns
`.distantPast` on nil, **deliberately** (`:57-61`) — an undated row must lose the
latest-scan comparison; a prior `Date()` substitution made the winner random
(`:29-35`). Tolerant `decodeIfPresent` throughout because live NULLs are common:
**336 of 1,059 rows have NULL/empty `photographer`**; 0 NULL `box_number`, 0 NULL
`school`, 0 NULL `timestamp`. `JobBoxStatus` has **no `CaseIterable` of its own** —
it is bolted on from the view file (`ManagerJobBoxTrackerView.swift:952-957`) and
excludes `.unknown`.

**Dead service methods** (zero call sites): `JobBoxService.generateCustomShiftID`
(`:135-147`), `debugQueryAllJobBoxes` (`:272-291`) and
`debugQueryJobBoxesByPartialShiftID` (`:294-313`) — the latter two also **have no
org filter** and swallow errors into `completion([])`, so an error presents as
empty. Plus `DatabaseManager.debugPrintJobBoxDocuments` (`:729-767`).

## 1.16 NFC hardware — what cannot be verified without a device

CoreNFC surface: `NFCNDEFReaderSession.readingAvailable`
(`NFCReaderCoordinator.swift:11`) — **the only availability check in the entire
app**; `NFCNDEFReaderSession(delegate:queue:invalidateAfterFirstRead: false)`
(`:18`, deliberate per `:16-17`); `didInvalidateWithError` swallowing
`readerSessionInvalidationErrorFirstNDEFTagRead` (`:24-26`); `didDetectNDEFs`
(`:33-108`). Writer: `NFCTagReaderSession(pollingOption: .iso14443)`
(`NFCWriterCoordinator.swift:14`) — **ISO14443 only, so ISO15693 and FeliCa tags
are never polled** even though `getNDEFTag` has cases for them (`:61-64`);
`didBecomeActive` is an **empty function body** (`:19-20`); multi-tag rejection
(`:30-34`); `queryNDEFStatus` (`:71`) whose returned **`capacity` is discarded**, so
an over-long card number is not pre-checked; `writeNDEF` (`:92`).

**System-sheet strings (not SwiftUI — easy to lose in a redesign):**
`"Hold your iPhone near the NFC tag."` (`NFCReaderCoordinator.swift:19`);
`"Hold your iPhone near the NFC tag to write."` (`NFCWriterCoordinator.swift:15`);
and the writer's in-sheet status copy `"More than one tag detected. Please try again."`
(`:31`), `"Unable to connect to tag."` (`:40`), `"Tag is not NDEF-compliant."`
(`:47`, `:83`), `"Unable to query tag status."` (`:73`), `"Tag is read-only."`
(`:80`), `"No message to write."` (`:87`), `"Write failed."` (`:94`),
`"Write successful!"` (`:97`), `"Unsupported NDEF status."` (`:105`). Plus the
Info.plist purpose string
`"This app uses NFC to scan SD cards and job boxes for tracking purposes."`
(`project.pbxproj:486`, `:533`).

**Reader parse contract** (`:33-108`) — the redesign must not change the tag format:
exactly **one** NDEF message with **exactly one** record (`:34`), else
`"Unexpected tag format. Please scan a valid tag."`;
`languageCodeLength = Int(statusByte & 0x3F)` (`:64-65`) — **the UTF-16 bit (0x80)
is masked away and text is always decoded as UTF-8** (`:80`); guards
`"Tag payload is empty."` (`:57`), `"Tag payload is too short."` (`:69`),
`"Failed to decode tag text."` (`:102`), `"No card number found on tag."` (`:84`).

**UNVERIFIABLE IN A SIMULATOR — each needs a physical device and a physical tag:**
1. **That `NFCNDEFReaderSession` starts at all under the current entitlement.**
   `Iconik Employee.entitlements` declares
   `com.apple.developer.nfc.readersession.formats = ["TAG"]` only, not `NDEF`, while
   the reader uses `NFCNDEFReaderSession`. **This is the single highest-value device
   check** and is stated as a flag, not a claim.
2. The `invalidateAfterFirstRead: false` + manual-invalidate dismissal timing.
3. Every writer branch: read-only tag, non-NDEF tag, insufficient capacity,
   multi-tag collision, mid-write disconnect.
4. That an ISO15693/FeliCa tag is unreachable for writing despite `getNDEFTag`
   supporting it.
5. **Suspected and unverified: the second write in a row saves no record.**
   `isWritingSuccessful` is never reset to `false` by the view, and `.onChange` will
   not re-fire until the coordinator sets it false — which happens only on an
   invalidation error (`NFCWriterCoordinator.swift:25`).
6. Whether the toast is clipped by the floating bar on the Scan screen (§0.27 —
   though the arithmetic now says ScanView is the *protected* site).
7. Behaviour when NFC is present but temporarily unavailable (e.g. during a call) —
   **the writer has no availability guard at all** (`:12-17`), unlike the reader.

**Testable without hardware:** NDEF payload construction
(`WriteNFCView.swift:122-151`), number-range validation (`:103-120`), the suggestion
arithmetic (`:209-271`), both status rings (`ScanView.swift:628-638`, `:682-689`),
the 3001 routing rule (`:151`), the left-job filter (`:346-431`), and all of
`JobBoxPickupRules`, which already has a harness.

## 1.17 Device-conditional layout

**`NFC/`, `JobBox/` and `Manager Features/` contain ZERO device conditionals** —
grep for `isIPad|horizontalSizeClass|userInterfaceIdiom|UIDevice` returns nothing in
any of the three. **There is no unseen second screen in AMB.11.**

The device logic that governs the feature lives entirely outside it and is
inconsistent (§0.18, §0.19). Consequences the redesign must handle:
- The tracker's sort row and both pill `ScrollView`s stretch edge-to-edge on iPad
  with no max width and no column layout.
- `statusMeterView` caps the meter at `maxWidth: 116` unconditionally (`:833`) —
  the same 116pt on a 402pt iPhone and a 1024pt iPad.
- All three tracker sheets (`:722-744`) use `NavigationView` with no
  `.presentationDetents` and no iPad sizing.
- The NFC rail is 60pt everywhere; the scan disc 200pt everywhere.

## 1.18 Dead / suspicious controls — AMB.11

| # | Sev | Finding | file:line |
|---|---|---|---|
| N1 | **CRITICAL** | Flag feature writes to three columns that do not exist; swipe action, context menu and the whole sheet are a fake affordance | `ManagerJobBoxTrackerView.swift:404-428`, `:686-692`, `:702-707`, `:899-942` |
| N2 | **HIGH** | `initialFeature` deep-link parameter — no caller ever supplies it, so there is no way to enter the container on any tab but Scan | `NFCContainerView.swift:8`, `:111-115`; sole construction `MainEmployeeView.swift:963` |
| N3 | **HIGH** | `ComingSoonView` — zero call sites, ships an internal note about "the NFC SD Tracker app" | `NFCContainerView.swift:175-198` |
| N4 | **HIGH** | `ScanView` never calls `JobBoxPickupRules.pickupWarning` — the guard exists only on the other two paths | `ScanView.swift:549` vs `JobBoxFormView.swift:214`, `ManualEntryView.swift:607` |
| N5 | **HIGH** | `NFCWriterCoordinator.beginWriting` has **no availability guard**, unlike the reader | `NFCWriterCoordinator.swift:12-17` vs `NFCReaderCoordinator.swift:11` |
| N6 | **HIGH (unverified)** | Entitlement declares only `TAG`, not `NDEF`, while `NFCNDEFReaderSession` is used | `Iconik Employee.entitlements`; `NFCReaderCoordinator.swift:18` |
| N7 | **HIGH** | SD `photographer` is unwritable, unreadable, unsearchable and uncharted — four controls attached to a nonexistent column | §0.26 |
| N8 | **HIGH** | Session-assignment write-back failure swallowed with `print`, save still reports success | `DatabaseManager+NFC.swift:291-296` |
| N9 | **HIGH** | `checkForLeftJobBoxes()` fetches EVERY job box row in the org, unpaginated, and re-runs on **every** realtime change | `ScanView.swift:362`, re-entry `:326` |
| N10 | **HIGH** | `StatisticsView.isLoading` written, never read — **no loading state exists**; first paint shows all-zero cards | `:12`, `:1126`, `:1137`, `:1158` |
| N11 | **HIGH** | `findTappedStatus(at:in:)` — 88 lines of donut hit-testing, **zero call sites**, and its comment references a donut this view does not draw | `StatisticsView.swift:756-829` |
| N12 | **HIGH** | `SearchView` has **no empty state** — a blank `List` plus a modal alert is the empty UI | `:191-221`, `:350-353` |
| N13 | MED | `FormView`'s `if alertMessage == "Scan saved"` branch returns `Alert(title:message:)` with **no `dismissButton`**. **Corrected during verification: this is NOT undismissable** — SwiftUI supplies a default OK for the two-parameter initializer. The real defect is that this branch **skips the `isSubmitting = false` reset** the else-branch performs (`:177`), so Submit would stay permanently disabled. The branch is **currently unreachable** — grep proves `"Scan saved"` is never assigned anywhere, only compared here — so it is a dormant trap wired to a string that no longer exists, not a live bug | `FormView.swift:172-180` |
| N14 | **HIGH** | `JobBoxFormView`'s session Picker **vanishes entirely** while loading or when empty — the user cannot tell "still loading" from "no sessions", on the control that links a box to a job | `:52` |
| N15 | **HIGH** | Date Filter is a fake control — `selectedDate` is written by the picker and read by nothing | `ManagerJobBoxTrackerView.swift:528-542`, `:581-593`, `:104-105` |
| N16 | **HIGH** | `leftJob` default 192h is outside its own slider's `0.5...48` range | `JobBoxSettingsView.swift:13` vs `:148` |
| N17 | **HIGH** | Card-number branch structurally unreachable — `cardNumber` hardcoded `""` kills a row pill, two sheet rows, both grouping keys and both search legs | `ManagerJobBoxTrackerView.swift:196`, `:774-780`, `:855-857`, `:904-906` |
| N18 | **MED** | Fake affordance: `ConfirmationDialogView`'s scrim has an `.onTapGesture { }` with a commented-out body | `DeleteConfirmationAlert.swift:24-27` |
| N19 | **MED** | ~150 lines of `#available(iOS 16.0, *)` else-branches are unreachable at a 16.6 deployment target, including a `"Chart requires iOS 16+"` string a user can never see | `StatisticsView.swift:264`, `:316-340`, `:375-400`, `:505-534`, `:610`, `:649-679`, `:722-744` |
| N20 | **MED** | `labelPosition`/`startAngle`/`endAngle` chain is dead; `startAngle` also divides by `total` with no zero guard | `StatisticsView.swift:1483-1522` |
| N21 | **MED** | `extension CGRect { var midPoint }` — zero call sites app-wide | `StatisticsView.swift:1473-1477` |
| N22 | **MED** | ~20 `print("DEBUG:")` inside the hot loop — per photographer, per box, per transition, on every mode/timeframe switch | `StatisticsView.swift:980-1096`, `:816-827` |
| N23 | **MED** | Realtime `for await` Task never cancelled — `remove()` only unsubscribes the channel | `ScanView.swift:320-339`; `SupabaseRealtimeWrapper.swift:7-17` |
| N24 | **MED** | Listeners re-subscribed on every `onAppear` with no teardown, on four screens | `SearchView.swift:268`, `:277`; `ManualEntryView.swift:364`, `:372`; `FormView.swift:145`, `:159`; `JobBoxFormView.swift:265`, `:280` |
| N25 | **MED** | Empty org id in `fetchLastRecord`/`fetchLastJobBoxRecord` returns with **no** user-facing message | `ScanView.swift:607-610`, `:664-668` |
| N26 | **MED** | Both `ScanView` sheet bodies are `if let` with no `else` → a blank sheet is reachable | `:188`, `:233-234` |
| N27 | **MED** | Left-job "12 hours" hardcoded in banner copy while the threshold is a variable; 43200 duplicated in three files | `JobBoxNotification.swift:36` vs `ScanView.swift:410`; `JobBoxBubbleView.swift:50` |
| N28 | **MED** | Session search matches the raw `yyyy-MM-dd` while the row displays `.medium` — typing "Jul" finds nothing | `NFCSessionSelectionView.swift:16` vs `:82-91` |
| N29 | **MED** | `.searchable` on the `List` vanishes in the no-results state — a failed query cannot be edited | `NFCSessionSelectionView.swift:62` vs `:38-53` |
| N30 | **MED** | "No available sessions in the next 2 weeks" doubles as the LOADING and the ERROR state | `:26-35`; error swallowed `ManualEntryView.swift:386-388` |
| N31 | **MED** | SD suggestion pins at 2000 forever via `max(1001, min(2000, …))`, pre-filling a duplicate | `WriteNFCView.swift:244` |
| N32 | **MED** | Alert dismissal branches on `alertMessage.contains("successfully")` | `WriteNFCView.swift:96-98` |
| N33 | **MED** | Hardcoded org id `"T6XeeaUNoOp8VJqq36wi"` gating the two house Toggles, in two files | `ManualEntryView.swift:199`, `FormView.swift:69` |
| N34 | **MED** | `refreshSchoolsAsync` busy-waits — `while isRefreshing { sleep(0.1) }`, spins forever if the completion never fires, and `try?` swallows cancellation | `ManualEntryView.swift:325-333` |
| N35 | **MED** | No form reset after a successful save — a second Submit re-inserts the same values | `ManualEntryView.swift:561-565`, `:664-668` |
| N36 | **MED** | `FormView` and `JobBoxFormView` set `navigationTitle` with no enclosing nav container — the titles never display | `FormView.swift:132`, `JobBoxFormView.swift:152` |
| N37 | **MED** | `FormView`'s alert is titled `Text("")` on both branches; `alertMessage` can only ever hold one generic fallback | `:172-180`, `:111-113` |
| N38 | **MED** | Plain school `Picker` in both sheets while the rest of the app uses `SearchableSchoolPicker` — unusable at real school counts | `FormView.swift:48-52`, `JobBoxFormView.swift:92-96` |
| N39 | **MED** | `updateAvailableSessions` re-fetches ALL org sessions on every `localPhotographer` change, and the result is not filtered by photographer at all | `JobBoxFormView.swift:156-158`, `:294` |
| N40 | **MED** | Status-search pulls the whole 4,166-row table client-side | `SearchView.swift:337`, `:383` |
| N41 | **MED** | `initialStatus` applied via a 0.1s timer, with a flag existing solely to suppress the `.onChange` cascade it triggers | `SearchView.swift:251-254` |
| N42 | **MED** | Per-body `DateFormatter`/`RelativeDateTimeFormatter` allocations in list rows | `RecordBubbleView.swift:6-11`, `JobBoxBubbleView.swift:6-11`, `NFCSessionSelectionView.swift:79-92`, `ManagerJobBoxTrackerView.swift:41-45`, `:431-435`, `JobBoxFormView.swift:335-346` |
| N43 | **MED** | `ManagerJobBoxViewModel` is not `@MainActor`; three fields mutated with no actor hop (latent — all current callers happen to be on main) | `:135-136`, `:139-140` |
| N44 | **MED** | `.refreshable` given a non-async body — the spinner retracts before data arrives | `ManagerJobBoxTrackerView.swift:715-717` |
| N45 | **MED** | Every icon-only control lacks an accessibility label (clear-search, gear, refresh) — contrast the meter, which has one | `:480-486`, `:613-621`, `:624-632` |
| N46 | **MED** | Overlapping-cycle double count — one "cleared" row can close several "job box" starts for one card | `StatisticsView.swift:889-894` |
| N47 | **MED** | `SearchView` deletes the row from `searchResults` on success with no re-search, so the "n cards in X status" count goes stale | `:467-469` |
| N48 | LOW | Unused `@State`: `isSaving`, `jobBoxesLoaded` (written 4×, read 0×), `colorScheme`, `lastTapLocation`, `debugMode`, `showDeleteConfirmation`, `recordToDelete`/`jobBoxRecordToDelete` (assigned then never read), `position: "Unknown"` | `ScanView.swift:12`, `:32`, `:46`; `StatisticsView.swift:43`, `:46`; `SearchView.swift:22-24`; `ManagerJobBoxTrackerView.swift:10`, `:207` |
| N49 | LOW | `StatusColors.hexColor(for:isJobBox:)` and both hex dictionaries — zero call sites | `StatusColors.swift:38-64` |
| N50 | LOW | `extension Color { var rgbComponents }` returns hardcoded `(0,0,0)`; its own comment says "placeholder … dummy values"; zero call sites but **app-wide scope** | `StatusColors.swift:68-74` |
| N51 | LOW | `formatTime` boundary `hours > 24` renders exactly 24h as "24 hours" not "1 day", in **two** separate implementations | `JobBoxNotification.swift:92`, `JobBoxBubbleView.swift:70` |
| N52 | LOW | Same NFC error shown twice at once — inline box AND toast | `ScanView.swift:122-133`, `:279-293` |
| N53 | LOW | SD status-ring logic duplicated verbatim between `ManualEntryView.updateSDCardDefaults` and `FormView.updateDefaults` | `:425-458` vs `FormView.swift:183-220` |
| N54 | LOW | Two selection colours for two adjacent pill rows (blue / green) | `ManagerJobBoxTrackerView.swift:503`, `:566` |
| N55 | LOW | `extension JobBoxStatus: CaseIterable` bolted onto a model at the bottom of a 957-line view file | `:952-957` |
| N56 | LOW | Legend `%.1f%%` vs pie `Int(%)` — two roundings of one number, side by side | `StatisticsView.swift:64` vs `:1531` |
| N57 | LOW | White slice labels over `envelope #FFCC00` | `StatisticsView.swift:302` |
| N58 | LOW | Four force unwraps in the duplicated time-frame filters | `StatisticsView.swift:1176`, `:1181`, `:1199`, `:1204` |
| N59 | LOW | Error alert titled `"Info"` — errors and successes share one non-error title, on three screens | `SearchView.swift:236`, `ManualEntryView.swift:275`, `ScanView.swift:273` |
| N60 | LOW | Two `Toggle`s, one Picker label and one DatePicker label whose strings never render (`.labelsHidden()`, `MenuPickerStyle` in an `HStack`, `Picker` label built from a dropped `HStack{VStack}`) | `ManagerJobBoxTrackerView.swift:582-588`, `:600`; `JobBoxFormView.swift:56-66` |
| N61 | LOW | `selectedStatus = isJobBoxMode ? "" : ""` — a ternary whose branches are identical | `ManualEntryView.swift:86` |
| N62 | LOW | `onCancel` optional with an unreachable `dismiss()` fallback | `ManualEntryView.swift:223-227` |
| N63 | LOW | Two near-identical delete paths and two `confirmDelete…` differing only in type | `SearchView.swift:425-490` |
| N64 | LOW | `filterRecordsByTimeFrame`/`filterJobBoxRecordsByTimeFrame` and `calculateAverageTimeInStatus`/`calculateJobBoxAverageTimeInStatus` are line-for-line duplicates — four copies of two algorithms | `StatisticsView.swift:1166/1189`, `:1262/1316` |

**Coupling to hook-protected Sports files: NONE.** Grep for `CapturaSportsView`,
`CapturaSportsRosterView_iPhone`, `RosterEntryService`, `LockManager` across `NFC/`,
`JobBox/` and `Manager Features/` returns zero hits. No shared service, model or
lock. **The only adjacency is structural and one-way:** `isSelfNavFeature` /
`featureContainer` treat Sports differently by device (`MainEmployeeView.swift:771-777`),
and a redesign of the NFC container's nav ownership touches that same function.
**That shared function is the boundary; nothing else is shared.**

---

# PART TWO — AMB.12: the tail

Settings (14 files, 3,269), Manager Features (8 files, 2,682), Training (6 files,
864), plus the allowlist-assigned and plan-orphaned surfaces AMB.12 inherits by
default: the time-tracking surface (10 screens, 2,662), `AllFeaturesView`,
`LoadingOverlay`, `AddressAutocompleteField`. All read completely.

## 2.0 What AMB.12 has already been told to carry

Recorded so the phase does not rediscover them mid-build:

- **`ManagerMileageView` is deferred to AMB.12 by operator ruling**
  (`scripts/check_card_drift.py:118-121`), unconverted with a clean sweep behind
  it. Its capabilities are inventoried in `AMB_BATCH3_PARITY.md:149-166` and are
  not repeated here. AMB.9 named but did not change: its **own 2/25/2024 period
  anchor** (disagreeing with the employee screen's org-configured periods) and its
  **four hand-rolled currency spellings** — `Formatters.currency` is the one
  spelling.
- **"Manage Kits" implies a tap it does not have** (`AdminKitTemplatesView`),
  carried in from AMB.3's smoke. **Operator decision: leave it, note it.** When this
  phase restyles the screen the cheap fix is a footer stating templates are managed
  in the web app. Making kits tappable is a FEATURE and belongs to its own phase.
- **AMB.9's reasoned won't-fixes that land here:** promoting chips, failure cards
  and loading states into the design system, and the route enum round-trip — both
  named as "AMB.12's consolidation".
- **The lab dies here.** `DesignLab/` (8 files) plus exactly three live references,
  all in `MainEmployeeView.swift`: the `HomeDestination.designLab` case (`:43-44`,
  id arm `:53`), the push switch arm (`:903-908`) and the menu Button (`:1047-1050`).
  `LabPalette.swift` has **zero references outside `DesignLab/`** (verified). **No
  Xcode project edit is needed** — the target uses `PBXFileSystemSynchronizedRootGroup`
  (`project.pbxproj:49-65`) and the pbxproj contains zero occurrences of `DesignLab`.
  Nine production comments reference mockup files, **all nine of which already point
  at deleted files** (`BottomTabBar.swift:8`, `DashboardChrome.swift:13`,
  `TasksView.swift:9`, `TaskDetailView.swift:8`, `MileageKit.swift:6`,
  `EquipmentAmbientRows.swift:7`, `RoutePlannerKit.swift:6`, `EquipmentView.swift:9`,
  `ReportSchoolLink.swift:4`).

## 2.1 Settings (14 files, 3,269 lines, 13 View structs)

**The entire tree hangs off ONE hamburger item.** `MainEmployeeView.swift:1041`
→ `.ambientPush(item:)` `:899` → `case .settings: SettingsView()` `:902`. There is
**no `FeatureItem` for settings, account, school info or profile photo** — Settings
cannot be pinned to the tab bar, cannot appear in All Features, and **has no
FeatureTheme colour** (no `"settings"` case in `DesignTokens.swift:34-75`; falls to
`default: .gray`).

| Screen | Reached from | Nav ownership |
|---|---|---|
| `SettingsView` | home profile hamburger → "Settings" | pushed into home's `NavigationView` |
| `EmployeeInfoView` | Settings → Account | push |
| `PTOBalanceView` | Settings → Account **and** My Time Off (`MyTimeOffRequestsView.swift:162`) | push; **insets itself** |
| `ProfilePhotoView` | Settings → Account | push |
| `SchoolInfoListView` | Settings → Preferences | push |
| `SchoolDetailView` | School Info row | push |
| `AddSchoolView` | School Info toolbar `+` or empty-state button | **sheet**, own `NavigationView` (`:37`) |
| `DailyReportDetailView` (declared `SchoolDetailView.swift:421`) | School Detail → a report row | push |
| `MetricsDashboardView` | Settings → Diagnostics | push |
| `TabBarConfigurationView` (declared in `BottomTabBar.swift:572`) | Settings → Preferences | push |
| `SignInView` | `RootView.swift:19` when not signed in | **self-nav** (own `NavigationView` `:26`, `StackNavigationViewStyle` `:85`) |
| `CreateAccountView` | `NavigationLink` on Sign In (`SignInView.swift:69`) | push inside SignIn's container; **no container of its own**, so its `Cancel` (`:36-38`) is a *second* dismissal beside the system back button |
| `ForgotPasswordView` | **sheet** from Sign In (`SignInView.swift:86-90`, wrapped by the presenter) | sheet |
| `ResetPasswordView` | **sheet from `RootView` itself** (`:84-86`), driven by deep link | sheet, own `NavigationView` (`:15`) |

**`ResetPasswordView` is attached to `RootView`'s `Group`, so it can present over
the launch spinner, over SignIn, or over MainEmployeeView.**

### 2.1.1 `SettingsView` (199)

Sections and every literal:

| Section | Row | Strings | Symbol |
|---|---|---|---|
| `"Account"` `:22` | Account Info `:23-25` | "Account Info" | `person.crop.circle` |
| | PTO Balance `:27-29` | "PTO Balance" | `clock.fill` |
| | Upload Profile Photo `:31-33` | "Upload Profile Photo" | `photo` |
| `"Preferences"` `:36` | School Info `:37-39` | "School Info" | `building.2` |
| | Quick Access Tab Bar `:41-46` | "Quick Access Tab Bar" | `square.grid.2x2` |
| `"Device Name"` `:56` | TextField `:50` | placeholder **"e.g. Kiosk, Poser, Camera 2"**; footer `:58` "Shown to other devices on the local network. Use this to tell iPads apart in the disconnect warning and the device list. Leave blank to use the iPad's system name. Reconnect on the Sync sheet (or restart the app) for a name change to take effect." | — |
| `"Sync & Cache"` `:112` | Status `:63-67` | "Status" + "Resyncing…"/"Downloading…"/"Uploading…"/"Offline"/"Synced"/"Not synced" (`:185-192`) | `arrow.down.circle.fill`/`arrow.up.circle.fill`/`wifi.exclamationmark`/`checkmark.circle.fill` `:172-177`, blue/orange/green `:179-183` |
| | Last Error `:71-84` | "Last Error" + raw `lastSyncError`, `.textSelection(.enabled)` | `exclamationmark.triangle.fill` |
| | Last Synced `:86-94` | "Last Synced" + `Text(date, style:.relative)` | `clock` |
| | Resync `:96-110` | "Resync Local Data"; disabled when `isResyncing \|\| !isConnected` | `arrow.triangle.2.circlepath` |
| | footer `:114-118` | offline: "Resync is disabled while offline. Connect to Wi-Fi first — clearing the local cache without a connection would leave the device with no data." / online: "Use only when this device is missing data that you can see on other devices." | — |
| `"Diagnostics"` `:127` | Metrics `:122-125` | "Metrics"; footer `:129` "Live counters, gauges, and latency histograms for this iPad's sync activity. Useful for support to diagnose connection or command issues." | `chart.bar.xaxis` |
| (unlabelled) `:132` | Logout `:133` | **"Logout" — no destructive role, no confirmation** | — |

Alerts: `"Resync Local Data?"` `:146` — "Cancel" / destructive "Clear & Resync";
body `:160` "Deletes all cached galleries, subjects, and images on this device,
then re-downloads them. Any pending uploads (roster edits, captures, image numbers)
that haven't reached the server will be lost. Stay on Wi-Fi until status returns to
Synced." And `"Resync Failed"` `:162-169`, single "OK".

Nav title `"Settings"` `:145`, `InsetGroupedListStyle` `:144`. **No lifecycle at
all** — no `.onAppear`, no `.task`, no `.refreshable`.

**States:** loading is inline only (a `ProgressView` inside the Resync row, `:103`).
Error: the sync-error row plus the resync alert. **Offline is present and
well-handled** — status text, disabled button, alternate footer. This is the only
Settings screen that knows the device can be offline.

### 2.1.2 The rest of Settings — capabilities in brief

**`EmployeeInfoView` (325)** — `Form`, title `"Account Info"` `.inline`, trailing
**"Edit"/"Save"** (`:171-185`). View-mode rows via `infoRow`, edit-mode via
`editableField`. Sections: `"Personal Information"` (First Name, Last Name, Display
Name, Email, Phone; Email `.emailAddress` + `.none` autocap, Phone `.phonePad`),
`"Address"` (`AddressAutocompleteField` + draggable `AddressMapView` in edit;
**"Show Map"/"Hide Map"** button + a read-only map with `.allowsHitTesting(false)`
in view mode), `"Professional Information"` (Position, Bio via a hand-labelled
`TextEditor`, **"Role"**), `"Organization"` (**"Organization ID"** raw uuid,
conditional **"Mileage Rate"** `"$%.2f/mile"`). Empty-value fallback **"Not set"**
in `.orange` (`:191-192`). Alert `"Profile Update"` / "OK" with
"Profile updated successfully" `:278`, "Failed to update profile: …" `:295`, "No
authenticated user found" `:248`. Saving overlay `ProgressView("Saving...")` `:161`,
form `.disabled(isSaving)`. **One allowlist card.**

**`ProfilePhotoView` (133)** — `Text("Profile Photo")` headline `:21`; **the screen
sets no `navigationTitle`**, so it inherits a blank bar and prints its own title in
the content. `SupabaseAvatarView(size:120)` or a grey `person.crop.circle`.
**"Select New Photo"** → `ImagePicker` sheet; conditional **"Ready to upload new
image."** + **"Upload Profile Photo"**; `ProgressView("Uploading...")`; inline red
`"Error: …"` and green `successMessage`. Messages: **"No authenticated user. Please
sign in."** `:77`, **"Could not compress image."** `:83`, **"Profile photo
updated!"** `:123`. **No alerts, no toolbar, no cancel, no delete-photo, no crop.**

**`SchoolInfoListView` (176)** — title `"School Info"`, toolbar
`Label("Add School", systemImage:"plus")`. Empty state **"No schools found"** +
**"Add Your First School"** (`plus.circle.fill`, blue capsule). Loading
`ProgressView("Loading schools...")`. Rows: name headline, address subheadline, and
either `"Mileage: %.1f miles"` blue or **`"Mileage: --"`** grey. `.refreshable`.
Alert `"Error"`/"OK". Guard **"No organization ID found. Please sign in again."**
**No search, no filter, no grouping**; sort is alphabetical, done in the service.

**`SchoolDetailView` (594)** — `Form`, title **"School Detail"** (not the school's
name). Sections `"School Info"` (name + address `TextField`s, conditional
**"Coordinates"** row, **"View on Map"** button, inline 200pt `Map` with a red
`mappin.circle.fill`), **`"Season Mileage (Jul 15 - Jun 1)"`** +
`"Total Miles Driven: %.1f miles"`, `"Daily Job Reports (Current Season)"` (empty:
**"No reports found for this season."**; rows `Text(date, style:.date)` +
`"Mileage: %.1f miles • \(photographerName)"`, each a link to
`DailyReportDetailView`), `"Location Photos"` (empty: **"No photos attached."**;
horizontal 100×100 `AsyncImage` scroller with a label caption and a **red `trash`
button with no confirmation**; `TextField("Enter photo label")`; **"Add Photo"** →
`ImagePicker`; **"Upload New Photo"**), then **"Save Changes"** and inline
red/green messages. Messages: **"School not found"**, **"School info updated!"**,
**"Photo deleted."**, **"New photo uploaded."**. **Three allowlist cards.**

**`DailyReportDetailView`** (`SchoolDetailView.swift:421-593`) — title
**"Report Details"** `.inline`. `ProgressView("Loading Report...")`; **"No data
found."**; header `Text(date, style:.date)` largeTitle + **"Photographer: …"** +
**"School: …"** (fallback "Unknown"). Conditional rows **"Mileage:"** `"%.1f miles"`,
**"Job Notes:"**, **"Job Descriptions:"**, **"Extra Items:"**, **"Cards Scanned:"**,
**"Job Box/Camera Cards:"**, **"Sports Background Shot:"**, then **"Attached
Photos:"**. **Read-only — no edit, no delete, no share, no toolbar.**

**`AddSchoolView` (230)** — sheet, own `NavigationView`, title **"Add New School"**,
toolbar **"Cancel"**. `"School Information"`: `TextField("School Name")`,
`TextField("School Address")` driving `AddressCompleter`, a suggestion list capped
at `min(count*60, 200)`pt, **"Verify Address"** (disabled when empty). `"Confirm
Location"` (only after a successful geocode): **"Drag the pin to adjust the exact
location"**, a 300pt map, **"Coordinates:"** `"%.6f, %.6f"`, conditional **"Dragging
pin..."**. Then **"Save School"** / `ProgressView`, disabled on
`isSubmitting || !isMapView || schoolName.isEmpty`. Messages: **"Please enter a
school address."**, **"Address not found: …"**, **"Could not determine location from
address."**, **"Please enter a school name."**, **"No organization ID found. Please
sign in again."**, **"School added successfully!"**, **"Error saving school: …"**.

**`PTOBalanceView` (320) — ALREADY CONVERTED (AMB.8), do not redesign.**
`AmbientBackdrop(tint: TimeOffStyle.requests, intensity: 0.7)` `:59`,
`.ambientNoBounceWhenShort()` `:78`, `.tabBarClearance()` via `PTOBalanceClearance`
`:80`/`:315-319`. Loading **"Loading PTO information..."**; error
**"Couldn't load your balance"** + **"Retry"** (`arrow.clockwise`) — **the only
Retry affordance in the whole Settings tree**; hero `"%.1f"` 44pt + **"hours
available"**; `"Breakdown"` rows **"Total Balance"**, **"Pending Requests"** (only
if >0), **"Available to Use"**, **"Banking Balance"** (only if >0);
`"Year to date"` stat tile **"Total accrued (hours)"** plus the caption **"Hours
used this year are not tracked on this device — the figure the app stored was never
written to the database. Payroll has the authoritative number."**;
`"Accrual policy"` (only when enabled) **"Accrual Rate"**, **"Maximum Balance"**,
**"Rollover Policy"** + **"Accrual counts business days only, Monday to Friday, at 8
hours a day."**; `"Projection"` **"Calculate balance for"** + `DatePicker` +
**"Projected total balance"** + conditional **"You will accrue %.1f more hours by
this date."**

**`MetricsDashboardView` (196) + `FocalPointMetrics` (251)** — nav title
**"Metrics"**. Sections **"Counters"**, **"Gauges"**, **"Histograms"**,
**"Timestamps"**, **"Export"**; empty rows **"No counter samples yet"** etc.;
quantile labels **"p50" "p95" "p99" "max"**; `"count: N"`; label pills rendered
`key=value` sorted; **"Export Today's Metrics"** (`square.and.arrow.up`). Every
section `.sorted { $0.name < $1.name }`.

**What it actually computes — PROVED, and it is NOT fake.** `FocalPointMetrics` is a
local in-process instrument for **this iPad's sync bus only** — four kinds
(counter/gauge/histogram/timestamp, `:24-29`), emitted from `FocalPointSyncClient`
(sync commands, acks, disconnects, HTTP thumbnail/image fetches, per the header
`:15-19`). Every emission appends to a `@Published` ring buffer capped at **5000**
(`:120-129`) and to a daily `Documents/metrics/metrics-{YYYY-MM-DD}.jsonl` on a
serial queue (`:138-156`); day boundary is **UTC** (`:76`). **The dashboard's numbers
come from the in-memory ring only** (`:194-250`) — counters are cumulative "since the
module loaded", gauges/timestamps last-value-wins, histograms p50/p95/p99/min/max
over whatever samples survive. **Nothing about jobs, mileage, schools or payroll.**
Contrast batch 3's Stats weather table: there is no fabricated data here.

### 2.1.3 Auth — exact calls, exact strings

| Screen | Call | SDK |
|---|---|---|
| `SignInView.signIn()` `:100` | `authService.signIn(email:password:)` | `supabase.auth.signIn` — `SupabaseAuthService.swift:147-150` |
| then `:112` | **an inline `.from("users").select().eq("id").single()` written in the view**, with a locally-declared `struct UserProfile` `:129-138`; then `PermissionsService.shared.load(roleId:)` `:166` | — |
| `CreateAccountView.createAccount()` `:163` | `authService.signUp(email:password:)` | `supabase.auth.signUp` `:169-173` |
| then `:206-209` | **inline `.from("users").insert(NewUserProfile)` from the view** | — |
| `PasswordResetViewModel.requestPasswordReset()` `:66` | `authService.resetPassword(email:redirectTo:)` | `resetPasswordForEmail` `:274-277` |
| `…handleDeepLink(url:)` `:87` | `authService.handleOAuthCallback(url:)` | `supabase.auth.session(from:)` `:308` |
| `…updatePassword()` `:107-108` | `updatePassword` then `signOut` | `auth.update(user:UserAttributes(password:))` `:291`; sign-out purges local PII `:195+` |

**Sign In:** title **"Sign In"**; placeholders **"Email"**, **"Password"**;
**"Forgot password?"**; button **"Sign In"** (grey while loading);
**"Don't have an account? Create one."**; error **"Failed to get user ID"**; all
other errors via `error.userFacingMessage` `:115`. **This is the only auth screen
that routes errors through `UserFacing`.** The reachable mapped set
(`Utilities/UserFacingError.swift:11-53`): "You appear to be offline. Check your
connection and try again." · "The server took too long to respond. Please try
again." · "Can't reach the server right now. Please try again in a moment." ·
"Network problem. Please check your connection and try again." · "That already
exists." · "You don't have permission to do that." · "Your session expired. Please
sign in again." · "Something went wrong reading data from the server." · "Something
went wrong. Please try again."

**Create Account:** **"Cancel"**, title **"Create Account"**, placeholders
**"Organization ID"**, **"First Name"**, **"Last Name"**, **"Email"**,
**"Password"**, **"Confirm Password"**, button **"Create Account"** (green);
validation **"Please fill in all fields."**, **"Passwords do not match."**,
**"Please select a valid address from the suggestions."**; **"Failed to get user ID
after signup"**; success **"Account created successfully. Please sign in."**
**Errors here are raw `error.localizedDescription` (`:219`)** — a duplicate-key or
RLS violation prints Postgrest text on screen.

**Forgot Password:** title **"Reset Password"** `.large`; **"Enter your email
address and we'll send you a link to reset your password."**; **"Email"**;
**"Send Reset Link"**; success view `envelope.circle.fill` green 60pt +
**"Check Your Email"** + **"If an account exists with \(email), you will receive a
password reset link shortly."** + **"Click the link in the email to reset your
password."** + **"Back to Sign In"**.

**Reset Password:** title **"Set New Password"** `.large`; **"Cancel"**;
**"Enter your new password below."**; **"New Password"**, **"Confirm Password"**;
**password rules shown as a live checklist** — **"At least 6 characters"** and
**"Passwords match"**; **"Update Password"**; success `checkmark.circle.fill` green
60pt + **"Password Updated"** + **"Your password has been successfully updated. You
can now sign in with your new password."** + **"Sign In"**.
`.interactiveDismissDisabled(viewModel.isLoading)` `:39`.
ViewModel messages: **"Password must be at least 6 characters long"**,
**"Passwords do not match"**, **"If an account exists with this email, you will
receive a password reset link."**, **"Invalid or expired password reset link. Please
request a new one."**, **"Failed to update password. Please try again."**

**Deep link — verified end to end.** Scheme `iconik` IS registered
(`Iconik-Employee-Info.plist:31-39`). `redirectURL = URL(string:"iconik://reset-password")!`
— **force-unwrapped** (`PasswordResetViewModel.swift:28`). `.onOpenURL`
(`Iconik_EmployeeApp.swift:52-53`) filters on `scheme == "iconik" && host == "reset-password"`
(`:63`) and dispatches to the app-level VM (`:20`, `:65`); the VM re-checks the same
predicate (`:80`), calls `handleOAuthCallback` (`:87`), sets
`showingResetPassword = true` (`:88`).

### 2.1.4 Settings states — the parity risk register

- **Offline is absent from 13 of 14 files.** Only `SettingsView` knows.
- **Exactly ONE retry affordance exists in the whole tree** —
  `PTOBalanceView.swift:109-117`. Every other error is a dead-end alert or inline
  red text.
- **Loading is absent** from `SchoolDetailView` (the form renders with empty
  name/address and 0.0 miles until data lands), `EmployeeInfoView` (a silent
  background refresh), `ProfilePhotoView` (no initial load) and `AddSchoolView` (the
  geocode has no indicator).
- **Search, filter, sort and grouping are entirely absent from all 14 files.** The
  only sorts are the metrics dashboard's `.sorted` and a re-sort-per-render at
  `SchoolDetailView.swift:84`.

### 2.1.5 `IOS_PASSWORD_RESET_FLOW.md` drift — the doc is wrong in four places

| Doc claim | Code | Verdict |
|---|---|---|
| ForgotPassword has an error state (`:69`) | `requestPasswordReset` **always sets `emailSent = true`** on both branches (`PasswordResetViewModel.swift:67`, `:72`), so the success view replaces the form and the error set at `:70` is rendered by a view no longer on screen | **DRIFT — the error state is unreachable and `self.error` there is dead** |
| ResetPassword has a "Back to Login" link (`:80`) | Toolbar is **"Cancel"** (`:32`); "Sign In" exists only in the success view (`:132`) | DRIFT (label + placement) |
| ResetPassword has "Checking (verifying recovery token)" and "Invalid/Expired link" states (`:84-86`) | **Neither exists.** Verification happens before the sheet is presented; on failure `showingResetPassword` is never set, so **the sheet never appears and the user is shown nothing at all** | **DRIFT — HIGH, silent failure (§0.11)** |
| Deep link parses the fragment and checks `params["type"] == "recovery"` (`:120-139`) | No fragment parsing, no `type` check — only scheme/host, then `session(from:)` | DRIFT (harmless; the SDK does it) |
| Error table (`:239-247`) lists "Please enter a valid email address", "No account found with this email", "Too many attempts. Please try again later.", "Unable to connect. Please check your internet connection." | **None of these four strings exist.** Invalid email is handled by *disabling* the button with no message; rate-limit and network errors collapse into the generic enumeration-safe message | **DRIFT — 4 of 7 documented messages absent** |
| Password rules min 6 + match; sign out after change | identical | matches |

### 2.1.6 Settings dead / suspicious

| # | Sev | Finding | file:line |
|---|---|---|---|
| G1 | **CRITICAL** | Sign-in proceeds on profile-fetch failure with empty org id, defaulted role and no permissions loaded | `SignInView.swift:168-175` |
| G2 | **CRITICAL** | Client-supplied `organization_id` + `role: "employee"` on the users insert, unvalidated | `CreateAccountView.swift:193`, `:202`, `:206-209` |
| G3 | **HIGH** | A bad reset link produces no UI at all | `PasswordResetViewModel.swift:88-91` |
| G4 | **HIGH** | Orphaned auth user on partial signup — retrying hits "already exists" forever | `CreateAccountView.swift:163` vs `:206-209` |
| G5 | **HIGH** | `refreshCurrentUserProfile()` fires AFTER `loadUserData()` and nothing re-runs the seed, so Edit can save **stale** values over fresh server data | `EmployeeInfoView.swift:143-149`, seed `:209-244` |
| G6 | **HIGH** | Email is editable and written to `users.email` but **Supabase Auth's email is never changed** — the two diverge and sign-in still needs the old address | `:59`, `:260` vs `SupabaseAuthService.swift:41-43` |
| G7 | **HIGH** | `loadMileageForSchool`/`loadDailyReportsForSchool` key off `name`, the **live editable `@State`** — typing in the School Name field re-queries the half-typed name | `SchoolDetailView.swift:250-255`, `:275-280`, field `:43` |
| G8 | **HIGH** | Rename orphans every report joined by `school_or_destination`; no warning, no migration | `:326-330`; join `DailyJobReportService.swift:680` |
| G9 | **HIGH** | `deletePhoto` removes from local state FIRST, then writes — on failure the photo is gone from the UI and still in the DB, with no restore | `:342-357` |
| G10 | **HIGH** | Signed URL with a **1-year expiry persisted into the database** | `:383-385`, stored `:396-397` |
| G11 | **HIGH** | Read-only PTO screen CREATES a DB row on open | `PTOBalanceView.swift:286`; `PTOService.swift:53`, `:92` |
| G12 | **HIGH** | "Total accrued (hours)" = `balance + banking + used`, but **nothing maintains `used`** — the tile under-reports lifetime accrual by exactly the hours ever used, while labelled authoritatively | `PTOBalanceView.swift:184`; `PTOBalance.swift:104-106`; `PTOService.swift:278-296` |
| G13 | **HIGH** | `exportURL()` returns today's path **whether or not the file exists** — Export on a quiet day hands the share sheet a non-existent URL with no message | `FocalPointMetrics.swift:188-190`; `MetricsDashboardView.swift:161` |
| G14 | **HIGH** | `listFiles()` has **zero call sites** — the multi-day picker its own doc comment promises does not exist; only today's file is ever shareable | `FocalPointMetrics.swift:161-174` |
| G15 | **HIGH** | No tab-bar clearance on SettingsView or any of its pushes except PTOBalanceView — **the Logout button sits under the floating bar** | absent; cf. `PTOBalanceView.swift:315-319` |
| G16 | **HIGH** | `@StateObject mainViewModel = MainEmployeeViewModel()` — a whole second copy of the app's main view model, constructed on every Settings open, solely to hand to `TabBarConfigurationView` | `SettingsView.swift:5`, `:43` |
| G17 | **HIGH** | N+1 query fan-out: one `daily_job_reports` query per school | `SchoolInfoListView.swift:108-110`, `:122-154` |
| G18 | **HIGH** | Save is gated on `isMapView` with **no message saying why** — a user who types an address and never taps "Verify Address" sees a permanently grey Save | `AddSchoolView.swift:118`, `:174` |
| G19 | **HIGH** | Four summarize reducers run inside `body` — four full passes over up to 5000 entries per re-render, and the view re-renders on every emission | `MetricsDashboardView.swift:25`, `:54`, `:83`, `:119` |
| G20 | MED | Logout swallows its error to `print`; no confirmation and no destructive role, while the less-destructive Resync has both | `SettingsView.swift:133`, `:136-139` |
| G21 | MED | Device Name writes `@AppStorage` per keystroke while its own footer admits it needs a reconnect to take effect | `:18`, `:50`, `:58` |
| G22 | MED | Entering Edit removes Role, Organization ID and Mileage Rate with no substitute | `EmployeeInfoView.swift:128`, `:133-138` |
| G23 | MED | `city`/`state`/`zipCode` are saved but have **no field in either mode** — only the autocomplete can set them, so a free-form address leaves them stale | `:23-25`, `:266-268` |
| G24 | MED | The `[String:Any]` → `AnyJSON` conversion **silently drops any value it cannot map** — a field vanishes from the update with no error | `UserProfileService.swift:304-305`, `:316-334` |
| G25 | MED | Inline Supabase query in `SchoolInfoListView` with a locally-declared `struct MileageRecord`, duplicating `getMileageForSchool` which already exists | `:129-145` vs `DailyJobReportService.swift:695-698` |
| G26 | MED | Two different date formats for the same comparison — `ISO8601Format()` (full timestamp) here vs `.withFullDate` in the service | `:140-141` vs `:669-673` |
| G27 | MED | `SchoolService.getSchools` never filters `is_active` — deactivated schools listed | `Services/SchoolService.swift:39-51` |
| G28 | MED | Season window **Jul 15 → Jun 1** hardcoded and duplicated verbatim in two files, with two force-unwrapped `calendar.date(...)!` | `SchoolInfoListView.swift:156-175`, `SchoolDetailView.swift:304-321` |
| G29 | MED | `coordinates` is displayed and mapped but **can never be edited**, and `updateSchool` is called without it — a mis-geocoded school is unfixable | `SchoolDetailView.swift:46-53`, `:326-330` |
| G30 | MED | Photo delete has no confirmation, and the **storage object is never deleted** — orphan files accumulate | `:131-136`, `:342-357` |
| G31 | MED | Save has no in-flight disable and no validation — empty name saves, repeated taps issue repeated UPDATEs | `:181-183`, `:323-340` |
| G32 | MED | Three competing address autocompletes in one directory: `AddressCompleter` (MapKit), `GooglePlacesService`, `AddressAutocompleteField` | `AddSchoolView.swift:20` vs `CreateAccountView.swift:26` vs `EmployeeInfoView.swift:73` |
| G33 | MED | `city`/`state`/`zip` never captured by AddSchool though `createSchool` accepts them | `:199-204` |
| G34 | MED | `getPublicURL` on `user-photos` stored as the profile URL, while the display component exists for **signed**-URL support; path is fixed with `upsert: true`, so **the URL never changes and a replaced photo can serve from cache indefinitely** | `ProfilePhotoView.swift:94`, `:104`, `:108-118` |
| G35 | MED | No photo-library permission check — a denied user gets an empty picker | `:41`; `Misc Features/ImagePicker.swift:11-16` |
| G36 | MED | CreateAccount shows **no password rules and enforces no minimum** client-side, while ResetPassword shows a 6-char checklist | `:127-155` vs `ResetPasswordView.swift:68-85` |
| G37 | MED | `@StateObject placesService` declared, never referenced | `CreateAccountView.swift:26` |
| G38 | MED | `accountCreated` shows a green message and **never navigates**; the form stays filled with the password | `:115-119` |
| G39 | MED | `SignInView` writes 7 `@AppStorage` keys but **not** `userEmail`, `userDisplayName`, `userPhotoURL`, `userPhone` — the home toolbar avatar can be blank on first sign-in | `:151-157` |
| G40 | MED | Inline `struct UserProfile` in the view duplicates the real model and selects `coordinates`, a school-only column | `SignInView.swift:129-138` |
| G41 | MED | `signIn` mutates `@Published` from a non-isolated `Task` — `SupabaseAuthService` has no `@MainActor` | `SupabaseAuthService.swift:153-154`, `:175-176` |
| G42 | MED | Metrics bucket keys built from `String(describing:)` of a **`Dictionary`**, whose ordering is not guaranteed — two emissions with the same labels can land in different buckets | `FocalPointMetrics.swift:197`, `:208`, `:217`, `:246` |
| G43 | MED | Counter footer claims "since the module loaded" but the buffer **rolls over at 5000** and silently drops the oldest | `:126-128` vs `MetricsDashboardView.swift:48` |
| G44 | MED | No metrics-file retention or pruning — a jsonl per day forever under Documents | `:138-156` |
| G45 | MED | `PTOSettings` decoded with **camelCase** keys inside a `pto_settings` JSONB, against a snake_case codebase — if the web app writes snake_case every org silently gets `defaultSettings (enabled:false)` and the Accrual Policy card never appears. **Flagged for live verification** | `PTOService.swift:364-369`; `PTOSettings.swift:34-56` |
| G46 | MED | Projection is called with `pendingRequests: []`, ignoring every filed request, and is clamped to `maxAccrual: 240` even for a non-accrual org | `PTOBalanceView.swift:305-308`; `PTOService.swift:174` |
| G47 | MED | `PTOService` caches, so Retry and re-entry can both return the same stale balance with no round-trip | `PTOService.swift:56-62` |
| G48 | LOW | `struct MapPin` at file scope **shadows SwiftUI's own `MapPin`**; `struct Report` at file scope with a generic name | `SchoolDetailView.swift:416-419`, `:6-11` |
| G49 | LOW | `successMessage`/`errorMessage` never clear each other; both can show at once, on three screens | `SchoolDetailView.swift:186-193`; `ProfilePhotoView.swift:64-67`; `FlagUserView.swift:136-159` |
| G50 | LOW | `resetResetPasswordFlow()` — zero call sites; `showingForgotPassword` `@Published` never read; `isValidCoordinates` duplicated verbatim in two files; force-unwrapped reset URL; deprecated `presentationMode`/`.navigationBarItems`/`.autocapitalization`; hardcoded San Francisco default centre repeated 3× | `PasswordResetViewModel.swift:138-143`, `:20`, `:28`; `CreateAccountView.swift:226-238` vs `EmployeeInfoView.swift:303-315`; `AddSchoolView.swift:11-15`, `:31` |

## 2.2 Manager Features — flagging and employee detail

| Screen | Feature id | Registration | Dispatch | Container | Theme |
|---|---|---|---|---|---|
| `FlagUserView` | `flagUser` | `MainEmployeeView.swift:577` + `AllFeaturesView.swift:18` | `:994-995` | **shell-wrapped** | **`#C62A2F`** (`DesignTokens.swift:38`) — note this sits in the **Planning** family beside `schedule`, not in Manager tools |
| `UnflagUserView` | `unflagUser` | `:578`, `AllFeaturesView.swift:19` | `:996-997` | **self-nav** (`:767`); owns `NavigationView` `:25`, applies `.homeToolbarItem()` `:88` and `.tabBarClearance()` `:92` itself | **`#5F8A6E`** (`:71`) |
| `FlaggedStatusView` | — | **none** | **none** | — | none — **DEAD (§0.7)** |
| `ManagerEmployeeDetailView` | — | not a feature | pushed from `ManagerMileageView.swift:382-389` | inherits ManagerMileage's shell nav; **applies no `.tabBarClearance()`** | inherits `managerMileage` |

**`FlagUserView` (194)** — plain `VStack`, no scroll, no form. Controls: a `Menu`
dropdown with `chevron.down` (`:59-79`), hidden entirely when the list is empty;
`TextField` flag note (`:82-84`); `Button("Flag User")` (`:86-89`), **never
disabled**. **Both the field and the button render regardless of permission**
(`:82-89` sit outside the `if !hasPermission` block ending at `:80`) — a denied user
gets a fully live-looking form that always errors.
Literals: **"Flag a Photographer"** `:37`, **"Access Denied"** `:45`, **"Only
administrators and managers can flag users."** `:48`, **"Loading users..."** `:54`,
**"Select a photographer"** `:68`, **"Enter a note for flagging"** `:82`,
**"Flag User"** `:86`/`:107`, **"You don't have permission to flag users."** `:138`,
**"Please select a user to flag."** `:143`, **"Please enter a flag note."** `:147`,
**"You appear to be signed out. Sign in again before flagging."** `:156`,
**"\(name) flagged successfully."** `:185`. Icons `exclamationmark.triangle.fill`,
`chevron.down`.
Filter: self excluded (`:120`), sorted case-insensitively by `firstName` (`:123`).
**`getTeamMembers` returns every row including `is_active == false`** — the
`isActive` filter exists only in `getPhotographers` (`TeamService.swift:139`), which
this screen does not call. Only `firstName` is carried into the model (`:121`), so
two people named "Chris" are indistinguishable.
States: **"Loading users..." is simultaneously the loading state, the empty state
and the failed state** — and `.onAppear` is attached to that `Text` (`:55`), so on a
load failure it persists forever and cannot re-fire.

**`UnflagUserView` (165)** — self-nav, title **"Unflag Users"**. `List` rows with a
blue **"Unflag"** button (`:76-81`). **No search, no sort, no filter, no swipe, no
confirmation — unflag is one tap and irreversible from this screen.**
Literals: **"Access Denied"**, **"Only administrators and managers can unflag
users."**, **"No Flagged Users"**, **"All users are currently in good standing"**,
**"Flag Note: \(note)"**, **"Unflag"**, **"You don't have permission to unflag
users."**, **"\(name) has been unflagged."**
**Sorted by `fullName` but displays `firstName`** (`:114` vs `TeamService.swift:154`)
— apparent-random ordering when first names repeat.
**No loading state at all**, so the green all-clear renders during the fetch
(§0.29). The permission guard now also gates the fetch (`:99-100`), closed at FLG.1.

**`ManagerEmployeeDetailView` (258)** — **zero controls.** Thumbnails, the `+N`
overflow tile and the photo-count chip are all non-interactive (`:188-224`), and
photos beyond the 5th are unreachable. The only interactive element is the system
Back button. Nav bar deliberately empty (`.navigationBarTitle("", .inline)` `:230`)
with the name as 40pt body text (`:126-127`).
Literals: `"Period: \(range)"`, **"Total Miles This Period:"**, `"%.1f"`,
`"Personal %.1f · Company %.1f mi"`, per-row medium date, school name,
`"%.1f miles"`, an orange **"Company"** chip, a `photo.fill` count chip,
`"+\(count - 5)"`, alert **"Error"**/**"OK"**, **"Error loading records: …"**,
**"User organization not found"**, fallbacks **"Unknown"** / **"personal"**.
Window is a fixed 14 days (`:60`); rows date-descending; the split row is hidden
when company mileage is 0. **No loading, no empty, no offline** — a blank list with
`0.0` is all three.

### 2.2.1 The flagging system end to end

| Question | Answer |
|---|---|
| Who can flag | `Permissions.has("users", level:.edit)`, checked three times (list `AllFeaturesView.swift:95`, view `FlagUserView.swift:31-33`, action `:136-139`). Server-side the `flag_user` function checks permission, org and self-target itself (`TeamService.swift:167-186`) — **the app-side check is convenience, not the boundary** |
| Write path | RPC `flag_user(p_user_id, p_note)` (`:187-201`). The direct table UPDATE was removed at FLG.2 because RLS matched only org admins and a zero-row PostgREST UPDATE returns 200 — **flagging appeared to work and did nothing** (`:169-173`) |
| Push | DB trigger `trg_user_flagged_notification`, note truncated to 300 chars (`FlagUserView.swift:168-183`). No app-side send |
| What the employee sees | **Two renderings, both in `MainEmployeeView`, deliberately** (comment `:1131-1136`): a bottom-anchored **dismissible banner** — `flag.fill` red, title `"Flag note"` or `"Flag note from \(name)"`, body = the note, `xmark.circle.fill` with a11y label `"Dismiss flag note"` (`:1137-1174`, gated `:656`) — and a **non-dismissible inline `AmbientNoteCard`** in the home scroll (`:798-808`). **Plus the entire home background turns red** — `AmbientBackdrop(tint: isFlagged ? .red : brand, intensity: isFlagged ? 1 : 0.9)` (`:793-796`) |
| Staying live | Realtime channel `user_flag_<uid>` on `users` filtered to the signed-in id (`:1290-1309`); each change re-runs `loadFlagStatusFromSupabase` (`:1313-1354`), which also resolves the flagger's first name (`:1356-1377`) and opportunistically syncs `photo_url` (`:1341-1345`). Failures are `print` only (`:1352`) |
| How it clears | **Only a manager**, via `UnflagUserView` → RPC `unflag_user` (`:206-220`). The employee has **no** in-app path (§0.7) |

**A design consequence worth stating:** a redesign that touches only `FlagUserView`
and `UnflagUserView` leaves the employee-facing half — banner, inline card and the
full-screen red wash — **untouched in `MainEmployeeView`**, which AMB.4 already
converted. The flag experience spans two phases' files.

**Recorded, not actionable here:** `TeamService.swift:58-66` states in-source that
the column allowlist is **not a security boundary** — `flag_note` is still reachable
via PostgREST by any signed-in employee. Accepted and documented.

## 2.3 Training

| Screen | Reach | Container | Theme |
|---|---|---|---|
| `PhotoCritiqueListView` | feature `training` (`MainEmployeeView.swift:128`), dispatch `:978-979`; **also a push deep link** — `PushNotificationManager.swift:356-360` sets `pendingCritique` + `selectedTab = "training"` | **self-nav** (`:767`); own `NavigationView` `:26`, applies `.homeToolbarItem()` `:53` and `.tabBarClearance()` `:57` | **`#C43B6D`** (`DesignTokens.swift:68`) |
| `PhotoCritiqueDetailView` | `.sheet(item:)` from the list (`:74-76`) | **sheet** with its own `NavigationView` (`:16`) | n/a |

**No permission check — correctly**, since the query self-scopes to
`target_photographer_id == me` (`PhotoCritiqueService.swift:61`). No dashboard
widget targets Training.

**`PhotoCritiqueListView` (257)** — controls: segmented `Picker("Filter")` bound
**straight into the shared singleton** (`:127-132`), so the choice persists across
screen exits; a grid/list toggle `Button` (`:137-146`) whose **icon shows the
current mode, not the destination**, with no label and no a11y label, and whose
`@State` resets to grid on every appear; card taps; `.refreshable` (`:77-79`);
**"Show All"** in the no-results state (`:229-234`).
Filter segment titles come from the service enum: **"All Examples"**, **"Good
Examples"**, **"Needs Improvement"** (`PhotoCritiqueService.swift:16-20`).
**Hidden query filters, not exposed in UI** (`:58-66`):
`target_photographer_id == currentUserID.lowercased()`, org match,
`status == "published"`, ordered `created_at` desc. **No sort control, no date
grouping, no search.**
Literals: stat cards **"Total"** (`photo.stack`, blue), **"Good"**
(`checkmark.circle`, green), **"Needs Work"** (`exclamationmark.triangle`, orange) —
**note "Needs Work" here vs "Needs Improvement" in the filter and on the badge:
three words for one concept**; nav title **"Training Photos"** `.large`;
`ProgressView("Loading training photos...")`; empty `camera.on.rectangle` 60pt +
**"No Training Photos Yet"** + **"Your training examples will appear here\nwhen
managers submit them."** (hard-coded newline); no-results `magnifyingglass` 60pt +
**"No Results"** + **"No training photos match the selected filter."** +
**"Show All"**.
States: loading only on first load; empty and no-results are distinct; **error
ABSENT** — `critiqueService.error` is published (`:10`), set (`:76`) and **read by
nobody**, so a failed fetch shows "No Training Photos Yet"; **offline ABSENT**.
Lifecycle: `.onAppear` starts realtime + consumes the deep link (`:58-61`),
`.onDisappear` stops it (`:62-64`). Because the service is a singleton whose
`@Published` state is never cleared on stop, **`critiques` survives sign-out until
the process dies**.

**`PhotoCritiqueDetailView` (305)** — controls: **"Close"** (`:33-37`); a `Menu`
(`ellipsis.circle`) with **"Save to Photos"** (`square.and.arrow.down`) and
**"Share"** (`square.and.arrow.up`); a paged `TabView` (`:71-120`); pinch-to-zoom
clamped 1.0–3.0; double-tap toggle 1.0↔2.0; a thumbnail strip with a selected ring;
alert **"OK"**.
Literals: title **"Training Photo"** `.inline`; **"Image unavailable"** + `photo`
50pt; counter **"\(i+1) of \(count)"**; `Label("Submitted by", …person.circle.fill)`,
`Label("Date", …calendar)`, `Label("For", …camera.fill)`; **"Training Notes"** +
`note.text` orange; alert **"Save to Photos"** with **"Image saved to Photos"** /
**"Failed to save image"** / **"Please allow access to Photos in Settings"**.
States: per-image loading and failure exist; **thumbnail failure ABSENT** (the
two-closure `AsyncImage` at `:149-157` has no failure branch, so a broken thumbnail
spins forever); **zero-images ABSENT** (an empty `TabView` at half screen height,
and Save/Share crash — §0.8); **offline ABSENT**; **save-in-progress ABSENT**.
Photos permission: the **deprecated** `PHPhotoLibrary.requestAuthorization` (`:243`),
and **`.limited` is treated as denied** (`:244`) even though add-only writes are
permitted under limited access. `UIImageWriteToSavedPhotosAlbum` is passed no
completion target (`:249`), so **"Image saved to Photos" reports a download success,
not a save success.**

**Components:** `CritiqueGridCard` (113) — 150pt `AsyncImage` `.fill` clipped,
failure = `photo` + **"Image unavailable"**, `ExampleTypeBadge` at `.scaleEffect(0.9)`,
an image-count pill on `.ultraThinMaterial` only when `imageCount > 1`, submitter
line, 2-line notes, date; card `systemBackground`, radius 12, shadow
`0.08/4/0/2`. `CritiqueListCard` (115) — 100×100 thumbnail whose **failure branch is
icon-only with no text**, inconsistent with the grid card; shadow `0.05/2/0/1`,
also different. `ExampleTypeBadge` (31) — binary on `type == "example"`, strings
**"Good Example"** / **"Needs Improvement"**, green/orange at 0.2 fill, capsule
radius 20; **any `example_type` other than `"example"` silently renders as a
criticism badge**. `StatsCard` (43) — generic title/value/icon/colour, used only by
the list view. **All three of these carry allowlist rows.**

**Data limits:** `Critique` (`Models.swift:839-898`) — the cards read the
**singular** `thumbnailUrl` while the detail reads the **plural** `thumbnailUrls`
and `imageUrls`: **three different fields for the same asset**. `imageCount`
defaults to `0` when NULL (`:884`), which suppresses both the "n of m" counter and
the entire thumbnail strip **even for genuinely multi-image rows**.
`submitter_email` is decoded and never displayed. `PhotoCritiqueService` is a
singleton **not `@MainActor`-isolated at class level** — handlers hop explicitly but
`startListening`/`stopListening` are nonisolated and write `channel` off-actor
(`:173`). **No pagination, no limit clause, no local cache** — the full published
set is re-queried on every appear. **There is no image cache anywhere in Training or
Manager Features**; full-resolution URLs are used for 60pt and 100pt tiles, and Save
and Share each perform a **second, independent full download** of the same URL
(`:247`, `:273`).

## 2.4 The time-tracking surface — named in no phase

10 screens, 2,662 lines. `FeatureTheme` gives `timeTracking` `#12A594`
(`DesignTokens.swift:51`) and **none of the ten reads it** — every colour is a
hardcoded `.blue`/`.red`/`.green`/`.orange`/`systemGray6`.

| Screen | Entry | Nav |
|---|---|---|
| `TimeTrackingMainView` (317) | `MainEmployeeView.swift:958-959`; feature registered `:113` | **shell-wrapped**; sets its own `.navigationTitle("Time Tracking")` `.inline` |
| `TimeEntryListView` (478) | embedded child, `TimeTrackingMainView.swift:24` | none of its own |
| `SessionSelectionView` (227) | **three** call sites — `TimeTrackingMainView.swift:34`, `TimeTrackingButton.swift:62`, **`DashboardWidgets.swift:80` (HoursWidget)** | self-nav sheet |
| `NotesInputView` (122) | `TimeTrackingMainView.swift:42` and **`DashboardWidgets.swift:97`** | self-nav sheet, `.navigationBarHidden(true)` |
| `CustomClockOutView` (205) | **only** via the "Long Shift Detected" alert (`TimeTrackingMainView.swift:73-75`) | self-nav sheet |
| `ActiveClockInEditView` (179) | **only** via "Edit Clock-In Time" (`:163-179`) | self-nav sheet |
| `ManualTimeEntryView` (278) | `TimeEntryListView.swift:220`, via "Add" | self-nav sheet |
| `EditTimeEntryView` (484) | `TimeEntryListView.swift:226-227`, via a row tap | self-nav sheet |
| `TimeEntryDetailView` (245) | **NONE — dead** | — |
| `TimeTrackingButton` (127) | **NONE — dead** | — |

**Three other clock affordances exist outside these ten, and two of them write
payroll:** the home dashboard **HoursWidget** header capsule
(`DashboardWidgets.swift:244-276`, described in-source as "the app's primary way in
and out of a shift", `:250-252`), the **AllFeaturesView toolbar** button
(`:162-208`), and the bottom-bar **`.active` badge** rendered as a green 7pt dot
(`BottomTabBar.swift:524-525`, `:388-395`).

### Payroll sensitivity — 7 write paths, ONE confirmation

| Screen | Write | Validation | Confirmation |
|---|---|---|---|
| `SessionSelectionView` | INSERT clock-in | notes ≤500; already-clocked-in check | **NONE.** Button never disables, no spinner. Double-tap is blocked only by a server round-trip away |
| `NotesInputView` (clock-out) | UPDATE end_time/total_hours/status | re-entrancy guard `:304-306`; zero-row guard `:360` | disables via `isProcessing`; **no "are you sure"** |
| `CustomClockOutView` | UPDATE end_time with an operator-chosen timestamp | 3 client + 3 identical server checks; zero-row guard | **NO confirmation and NO in-flight guard** — the button stays enabled during the call |
| `ActiveClockInEditView` | UPDATE start_time on a **live shift** | future + 48h window, client and server; zero-row guard | **NO confirmation.** The copy warns "Adjusting clock-in time will update your total hours" (`:72`) and nothing is confirmed |
| `ManualTimeEntryView` | INSERT a fabricated shift | client >start, ≥1min, **≤16h**, not future; server adds **overlap detection** | **NO confirmation.** Overlap is discovered only after Save |
| `EditTimeEntryView` | UPDATE start/end/session/notes | 30-day window, ownership, 16h server ceiling, overlap excluding self; zero-row guard | **NO confirmation on Save** |
| `EditTimeEntryView` | **DELETE** | 30-day, ownership, zero-row guard | **Has a destructive confirm alert (`:263-270`) — the ONLY confirmation in the entire surface** |
| `AllFeaturesView` toolbar | INSERT or UPDATE, **with no session and no notes** (`:167-172`) | server-side only | **NO confirmation, no session picker, no notes.** One tap in a nav bar creates or closes a payroll record. It does surface failures properly (alert + haptic, `:176-183`) — the best error handling in the chunk |
| `HoursWidget` | INSERT/UPDATE via the two sheets | — | **errors swallowed with a bare comment** (`// Clock in error` `:90`, `// Clock out error` `:107`) — on the path the source itself calls primary |

**A real ceiling conflict:** manual creation caps at **16h**
(`ManualTimeEntryView.swift:151`, `Models.swift:706`) but *editing* caps at **24h**
(`EditTimeEntryView.swift:318`), and the edit path then calls `validateManualEntry`
server-side, which enforces 16h. **An edit the UI accepts (17h) is rejected on
Save.**

**Cross-midnight is impossible in manual entry** — `createDateTime` forces both
start and end onto `selectedDate` (`:160-164`), so an overnight shift just fails
"End time must be after start time".

**Data-layer guarantees and limits:** every UPDATE and DELETE appends `.select("id")`
and runs `requireRowsWritten` (`TimeTrackingService.swift:44-48`), throwing on a
zero-row match — the documented fix for PostgREST returning 200 on a no-op write.
Case is never folded on `time_entries.id` because the column holds mixed casing
(in-source note `:39-41`). **`getTimeEntries` has a hard `limit(100)` with no
pagination and no UI indication** (`:591`) — a 14-day period with >100 entries
silently truncates **and the "Total Hours" figure on screen is then wrong**.
`getCurrentTimeEntry` uses `.limit(1)` with **no ordering** (`:544-556`) — with two
stray `clocked-in` rows, which one is "current" is undefined. **Offline support is
asymmetric:** `clockIn`/`clockOut` queue to `TimeClockOutbox` and replay FIFO;
`clockOutManual`, `updateActiveClockInTime`, `createManualTimeEntry`,
`updateTimeEntry` and `deleteTimeEntry` have **no offline path and simply throw**. A
queued offline clock-out whose row no longer exists is **logged and dropped**,
deliberately, to avoid wedging the queue (`:212-218`) — a silently lost clock-out.
`TimeEntry.total_hours` is **never populated by the camelCase initializer**
(`Models.swift:635`), so every offline-constructed entry has a nil total.
`TimeEntry.taskId` exists in the model and is written by nothing.

**Pay-period anchor:** `TimeEntryListView` computes 14-day cycles from a hardcoded
literal **`"2/25/2024"`** (`:41-49`) — the same anchor `ManagerMileageView` uses and
that AMB.9 named as AMB.12's to reconcile.

### Time-tracking literals worth preserving

`TimeTrackingMainView`: **"Currently Clocked In"** / **"Currently Clocked Out"** /
**"Ready to start"**; `"Since <h:mm a>"`; an `HH:MM:SS` elapsed clock;
**"Current Session"**; a session name or the literal **"Session"**; alert
**"Long Shift Detected"** with **"Clock Out Now"** / **"Set Custom Time"** /
**"Cancel"** and the body **"You've been clocked in for over 24 hours. Would you
like to set a custom clock out time?"**
`TimeEntryListView`: segmented **"Today"** / **"This Week"** / **"Pay Period"**;
**"Recent Time Entries"**; **"Total Hours"** with a blue **"(Pay Period)"** suffix;
**"Entries"**; rows rendered **"Today" / "Yesterday" / "MMM d"**, `"Xh Ym"`,
`"h:mm a - h:mm a"` or **"- Present"**, **"• ACTIVE"** green, `pencil`/`lock`;
empty **"No time entries for \(range.lowercased())"**.
`SessionSelectionView`: **"Clock In"**; **"Loading today's sessions..."**; empty
`calendar.badge.exclamationmark` + **"No sessions assigned for today"** +
**"You can still clock in without selecting a session"**; **"Today's Sessions"**;
**"Notes (optional)"** + **"Add notes for this time entry..."**
`NotesInputView`: **"Clocking Out"** / **"Clocking In"**; **"Add optional notes for
this time entry"**; **"Notes (optional)"**; a 500-char cap with a `"\(n)/500"`
counter turning red above 450; **"Clock Out"/"Clock In"** switching to
**"Processing..."**
`CustomClockOutView`: **"Set Clock Out Time"**; **"Clock In Time"**,
**"Clock Out Date & Time"**, **"Duration"**, **"Notes (Optional)"**; presets
**"End of Yesterday"**, **"Start of Today"**, **"Now"**; `"\(h)h \(m)m"` and, above
24h, **`"\(h)h \(m)m ⚠️ Exceeds 24 hours"`**; `Label("Long shift - crosses midnight", "moon")`.
`ActiveClockInEditView`: **"Edit Clock-In Time"**; **"Current Status"**,
**"Adjust Clock-In Time"**, **"Preview"**; **"Adjusting clock-in time will update
your total hours"**; **"New Clock-In"**, **"Time Elapsed"**, **"Original Clock-In"**;
footer **"Clock-in time can only be adjusted within the last 48 hours"**.
`EditTimeEntryView`: **"Edit Time Entry"**; `Label("This entry cannot be edited", "lock")`;
`Label("Crosses midnight", "moon.fill")`; **"End must be after start"** /
**"Exceeds 24 hour limit"**; **"Delete Time Entry"** with **"Are you sure you want
to delete this time entry? This action cannot be undone."**
`TimeEntryDetailView` (dead): **"Active Clock Entry"** / **"Manual Time Entry"** /
**"Clock-based Entry"**; and **the only copy anywhere explaining the edit window** —
**"Editable (within 30-day window)"** and **"Read-only (outside edit window or
system-generated)"** (`:38`, `:41`).

### Time-tracking dead / suspicious

| # | Sev | Finding | file:line |
|---|---|---|---|
| K1 | **HIGH** | `TimeEntryDetailView` — 245 lines, zero call sites; holds the only 30-day-window explanation in the app | `:3`, `:38`, `:41` |
| K2 | **HIGH** | `TimeTrackingButton` + `TimeTrackingFloatingButton` — 127 lines, zero call sites; the floating variant hardcodes a pre-AMB.4 `padding(.bottom, 100)`. **Yet it holds 2 allowlist cards** | `:3`, `:104-119` |
| K3 | **HIGH** | Fetch error rendered as an empty state inviting an unattributed clock-in | `SessionSelectionView.swift:145-149` vs `:61-65` |
| K4 | **HIGH** | Same shape in the entry list — payroll appearing to be zero | `TimeEntryListView.swift:258-264` vs `:190` |
| K5 | **HIGH** | `AllFeaturesView.task` installs a 1Hz timer after an `await` with no `Task.isCancelled` check | `:148-151`, `:230-238` |
| K6 | **HIGH** | **User-visible typo in shipped copy: "while clocked-in**ly clocked in**"** | `EditTimeEntryView.swift:187` |
| K7 | **HIGH** | 16h/24h ceiling conflict — an edit the form accepts is rejected on Save | `EditTimeEntryView.swift:318` vs `TimeTrackingService.swift:843-850` |
| K8 | MED | Empty completion handler `{ _, _ in }` with a comment explaining it | `TimeTrackingMainView.swift:55-57` |
| K9 | MED | `debugTimeEntryQuery()` — **an empty function body with a live call site**, awaited on every empty result | `TimeTrackingService.swift:613-615`, called `TimeEntryListView.swift:251` |
| K10 | MED | `NotesInputView.isProcessing` set true and never reset — a failed clock-out **permanently wedges** the button at "Processing…" with no in-sheet error | `:70-93` |
| K11 | MED | Unused: `AllFeaturesView.userRole` (declared, passed in, never read); `TimeEntryRow.dateFormatter`; a `let calendar` never used | `AllFeaturesView.swift:8`; `TimeEntryListView.swift:272-276`; `ManualTimeEntryView.swift:139` |
| K12 | MED | Dead auto-correct and a dead `onAppear` block | `EditTimeEntryView.swift:326-335`, `:258-261` |
| K13 | MED | Silent print-only session-load failures — the Session picker just never appears | `ManualTimeEntryView.swift:240-243`, `EditTimeEntryView.swift:391-394` |
| K14 | MED | Per-body formatter allocations across **eight** files; none use `Formatters` from `DesignTokens.swift:88-140`, which exists precisely for this | `SessionSelectionView.swift:14-18`; `TimeEntryListView.swift:272-282`, `:443`, `:453`; `TimeEntryDetailView.swift:7-17`; `TimeTrackingMainView.swift:309-313`; `ActiveClockInEditView.swift:154-158`; `CustomClockOutView.swift:158-162`; `EditTimeEntryView.swift:447` |
| K15 | MED | **Three independent 1Hz timers** for one clock can run at once | `TimeTrackingService.swift:512`; `AllFeaturesView.swift:234`; `DashboardWidgets.swift:283` |
| K16 | MED | Frozen "live" values — `elapsedTime` and the >24h warning glyph read `Date()` in a computed body with no timer driving them | `ActiveClockInEditView.swift:49-52`; `TimeTrackingMainView.swift:146-151` |
| K17 | LOW | Two sheets are `if let` with no `else` and render **empty** if the entry is nil at presentation | `TimeTrackingMainView.swift:49-68` |
| K18 | LOW | Debug `print`s left on payroll paths | `TimeEntryListView.swift:236-260`; `SessionSelectionView.swift:109-110` |
| K19 | LOW | `CustomClockOutView` notes has **no 500-char cap or counter**, unlike all four siblings — enforced only server-side | `:101-104` |
| K20 | LOW | Manual-entry date picker unbounded — a future date is selectable, rejected only after the fact | `:26` vs `:184` |
| K21 | LOW | `CustomClockOutView` defaults its pickers to `Date()` rather than deriving from `clockInTime` | `:9-10` |
| K22 | LOW | First load gated on a `DispatchQueue.main.asyncAfter(0.5)` "to ensure authentication is set up" — a race papered over with a delay | `TimeEntryListView.swift:210-215` |

**No force unwraps and no `try!` anywhere in the nine screens.** One `!` in the
service (`TimeTrackingService.swift:652`).

## 2.5 `AllFeaturesView`, `LoadingOverlay`, `AddressAutocompleteField`

**`AllFeaturesView` (269)** — pushed from `MainEmployeeView.swift:930-935`; applies
its own `.tabBarClearance()` (`:136`) because a pushed view does not inherit the
shell's inset (comment `:132-135`). **Already reads `FeatureTheme`** (`:267-269`) —
right colours, hand-rolled container, exactly as the shell inventory says.
Two sections: `"Employee Features"` (19 rows, drag-reorderable in edit mode via a
`line.3.horizontal` grip, persisted to `UserDefaults["employeeFeatureOrder"]`) and
`"Management Features"` (7 rows) behind the file's **only** permission check,
`Permissions.has("users", level: .edit)` at `:95`. **There is no per-item gate — all
seven manager features are all-or-nothing on `users:edit`.**
Org flag: `filteredEmployeeFeatures` (`:253-265`) hides the three report ids under
`usePhotoshootNotesOnly` — **the same three-id list exists in three places**
(`MainEmployeeView.swift:238-240`, `:262`, and here).
Toolbar: a clock in/out capsule (`:162-208`) and **"Edit"/"Done"** (`:210-225`).
Alert **"Clock In/Out Failed"** with the fallback **"Something went wrong. Your time
may not have been recorded — please try again or check your connection."**
(`:143-147`) plus an error haptic (`:181`).
**Known permission mismatch, documented in-repo:** the `timeOffApprovals` row is
visible on `users:edit` while the screen it opens gates on a different area
(`TimeOff/Views/TimeOffApprovalView.swift:14`).

**`LoadingOverlay` (40)** — `Color.black.opacity(0.4)` scrim + a
`RoundedRectangle(16).fill(Color.black.opacity(0.8))` card with a white
`ProgressView` at `scaleEffect(1.5)` and a headline white message, padding 32.
Default message **"Loading..."** (`:32`). **One consumer** (`NFC/ScanView.swift:277`).
**No dark-mode branch** (it is black in both), **no cancel affordance, no timeout,
no accessibility label.**

**`AddressAutocompleteField` (347)** — label **"Address"**, `TextField("Enter address")`,
`.autocapitalization(.words)`, `.disableAutocorrection(true)`; suggestion rows show
`primaryText` over `secondaryText` with dividers, max height 200; **"View on Map"**
(`map` icon) only when coordinates parse and the map is hidden. Search fires at ≥3
characters (`:50`); a `DispatchWorkItem` schedules a **1.5s** debounced geocode
(`:58-62`); suggestions hide 0.1s after end-editing to let a tap register; a Places
session token is minted at init and rotated after each detail fetch (`:18`, `:197`).
`AddressMapView` (`:231-347`) — hybrid map at 250pt, radius 12,
**"Drag the pin to adjust location"**, **"Coordinates:"** `"%.6f, %.6f"`.
States: loading **"Searching..."**; **empty ABSENT** — a query with zero predictions
shows nothing at all, no "No matches"; **error ABSENT** — both failure paths are
`print` only (`:200`, `:223`), so a bad API key, quota exhaustion or no network is
indistinguishable from "still typing"; **offline ABSENT**. **Falls back to San
Francisco on unparseable input** (`:254`, `:346`) — a silent wrong-location default.
Coordinate validation is duplicated in **three** places. **Two allowlist cards.**

## 2.6 Device-conditional layout in the tail

- `Settings/` — **one grep hit, and it is a comment** (`SettingsView.swift:15`). No
  device-conditional layout anywhere. The tree is nonetheless iPad-oriented in
  *content*: Device Name, Sync & Cache and Metrics are all iPad-sync features shown
  unconditionally to iPhone users.
- `Manager Features/` — **zero**. The indirect one: the Home toolbar button is
  iPhone-only, so on iPad `UnflagUserView` has no top-left Home and depends entirely
  on the floating bar.
- `Training/` — **two hits, and one is a real second layout**:
  `PhotoCritiqueListView.swift:155` (2-col iPhone / 3-col iPad, on raw idiom, so
  Slide Over still gets 3), and `PhotoCritiqueDetailView.swift:121`
  `.frame(height: UIScreen.main.bounds.height * 0.5)` — **half the SCREEN, not half
  the sheet**, so on iPad the pager can overflow its container.
- Time tracking + `AllFeaturesView` + `LoadingOverlay` + `AddressAutocompleteField` —
  **zero hits across all 14 files.** Every screen is device-agnostic, and every size
  is a hard constant: `SessionSelectionView`'s list at `maxHeight: 300`, the address
  map at 250pt, the suggestion dropdown at 200pt. Six `Form`-based sheets present at
  iPad sheet size with **no `.presentationDetents` and no size-class adaptation
  anywhere**.

---

# PART THREE — the shell: five surfaces that belong to no phase

`AMB_SHELL_INVENTORY.md` was written at the start of AMB.5 because the bottom tab
bar belonged to no phase and neither discovery mechanism could see it. That document
is now fifteen months of commits old in app-time and **three of its claims are
wrong** — verified below. AMB.12 closes the arc, so these land here unless the
operator says otherwise, exactly as D13 was his call.

## 3.0 Drift against `AMB_SHELL_INVENTORY.md`

| Doc claim | Line | Today | Verdict |
|---|---|---|---|
| "Three call sites: MainEmployeeView, NFC/ScanView, and Misc Features/DailyJobReportView" | `:64-65` | Repo-wide `.toast(` yields exactly **two**: `MainEmployeeView.swift:689` and `NFC/ScanView.swift:278`. **There is no `DailyJobReportView.swift` anywhere.** The report toast is posted as `Notification.Name("ShowReportSuccessToast")` (`Reports/DailyReportView.swift:1352`) and rendered by the **MainEmployeeView** site (`:690-693`) | **WRONG, and structurally so** |
| "two of the three call sites already get the shell's inset… only the MainEmployeeView call site is bare" | `:46-50`, repeated verbatim in `Components/ToastView.swift:35-39` | Only ScanView gets the inset. **The bare site is the one that fires on every successful daily report** | **Halves the reasoning** — the double-count risk applies to ONE site, and the collision risk is on a routine path, not an edge case |
| "UIComponents.swift — AMB.12, 1 card. ModernCheckboxRow and ModernSegmentButton" | `:120-121` | **The file does not exist.** Deleted by AMB.7 (`b5679dc`); both symbols have zero references | **STALE** |
| Design Lab entry goes at AMB.12 | `:86` | Still present, `MainEmployeeView.swift:1047-1050` | Confirmed |
| Sign-in surface = SignInView / ForgotPasswordView / ResetPasswordView | `:93-97` | `ResetPasswordView` is in fact a **RootView-owned sheet** (`RootView.swift:84-86`) that can appear over either branch | Refinement |

**Separately discovered:** **nine production comments reference lab mockup files
that no longer exist** (§2.0), and `Reports/ReportRules.swift:4` +
`Reports/ReportSchoolLink.swift` still say "PRODUCTION CODE, used by the lab" with no
lab file referencing either type.

## 3.1 `ToastView` (64 lines) — app-wide chrome

Takes exactly two inputs, `message: String` (`:4`) and `isSuccess: Bool` (`:5`), and
**displays no literal string of its own** — every word is caller-supplied.

| Element | Value | Line |
|---|---|---|
| Glyph | `checkmark.circle.fill` / `xmark.circle.fill` | `:9` |
| Glyph colour | `.white` hardcoded, not a token | `:10` |
| Glyph size | `.title2` | `:11` |
| Text | `.white`, `.subheadline`, `.medium` | `:13-16` |
| Layout | `HStack(spacing: 12)`, `.padding()` | `:8`, `:18` |
| Container | **`Capsule()`** — which is why the drift gate is blind to it | `:20-22` |
| Fill | `Color.green` / `Color.red` — **system colours, not `FeatureTheme` or `AmbientStyle`** | `:21` |
| Shadow | `.shadow(radius: 10)` | `:23` |

**Behaviour** (`:43-64`): attaches as `.overlay(...)` on the modified view (`:45`), so
its coordinate space is that view's frame including its safe-area insets;
`VStack { Spacer(); ToastView(...) }` then `.padding(.bottom, 50)` (`:48-60`);
transition `.move(edge:.bottom).combined(with:.opacity)` (`:51`); auto-dismiss
scheduled in **`.onAppear`** via a single `asyncAfter(.now() + 3)` (`:52-57`).

Three behavioural consequences a redesign must keep or deliberately change:
1. **No dismiss-on-tap and no queue.** A second toast raised while one is visible
   replaces the string in place; `onAppear` does not re-fire, **so the first toast's
   timer dismisses the second message early**.
2. **The show is un-animated; only the hide is animated.** Every call site sets the
   flag bare (`MainEmployeeView.swift:692`; `ScanView.swift:285, 479, 502, 514, 534,
   575, 598, 657, 709`); only the dismissal is wrapped (`:54`).
3. **Fixed 3s for every message**, including the multi-line failure strings at
   `ScanView.swift:512` and `:596`.

**Absent, verified by full read, not "elsewhere":** tap-to-dismiss, a close glyph,
queue/stacking, configurable duration, any accessibility announcement or label, a
neutral/warning/info variant, a top-anchored variant, and any design-system token.

**The reverted-fix comment still exists verbatim at `:27-42`**, annotating an
unchanged `.padding(.bottom, 50)` (`:60`). But its own factual basis is now partly
false — `:36-39` names "ScanView and DailyReportView" as the two inset-protected
sites, and DailyReportView has no `.toast` call at all.

**Geometry.** `TabBarMetrics`: `height = 68` (`BottomTabBar.swift:76`),
`bottomInset = 6` (`:83`), `clearance = 84` (`:92`); the bar occupies **6pt → 74pt
above the safe-area bottom**. At the ScanView site the host carries the shell's 84pt
inset, so the toast's bottom edge sits at 134pt — clearing the bar by 60pt. At the
MainEmployeeView site the host has **no** inset, so the toast bottom sits at **50pt,
24pt inside the bar band**, spanning roughly 50→104. **Draw order resolves
"clipped":** the toast is an `.overlay` on the whole body `ZStack` (`:626-694`) and
the bar is a child *inside* that ZStack (`:645-652`), so the toast **covers** the
bar's left/right cells rather than hiding behind them — and participates in
hit-testing over that band for ~3 seconds. **This is arithmetic and view-order
reasoning, not a device observation; it still needs one look on a device.** Also
unverified: the bar slides down by 144 when the keyboard is up (`:448`, `:242`)
while the toast does not, so a keyboard-visible toast has no collision at all. And
**`ToastView` has no device branch**, while `TabBarMetrics.iPadMaxWidth = 560`
(`:82`) centres and narrows the iPad bar — so a full-width toast on iPad overhangs it
horizontally rather than sitting over it.

**Every message the toast can display:** `"Report submitted successfully"` (true,
`MainEmployeeView.swift:691`) · `nfcReader.errorMessage` pass-through (false,
`ScanView.swift:284`) · `"User organization not found."` (false, `:477`, `:532`) ·
a service-supplied SD success message (true, `:500-501`) ·
`"Failed to save record: …"` (false, `:512-513`) · a service-supplied job-box
success message (true, `:573-574`) · `"Failed to save job box record: …"` (false,
`:596-597`) · `"Could not fetch card history. Starting fresh."` (**false**, `:655-656`) ·
`"Could not fetch job box history. Starting fresh."` (**false**, `:707-708`). Note
the last two: **success-shaped copy delivered on the red/xmark treatment.**

## 3.2 The home profile toolbar (`MainEmployeeView.swift:1017-1068`)

`@ToolbarContentBuilder` (`:1022-1023`), attached only inside `homeContainer`
(`:728-730`) — **it exists on Home and nowhere else.** One
`ToolbarItem(.navigationBarTrailing)` (`:1025`) containing an `HStack(spacing: 10)`.

| # | Element | Detail |
|---|---|---|
| 1 | First-name label | `Text(storedUserFirstName)` `.headline`, `.primary`, `lineLimit(1)`, `minimumScaleFactor(0.8)` (`:1027-1031`). Source `@AppStorage("userFirstName")` default `""` — **an unpopulated profile renders an empty, unlabelled Text with no placeholder** |
| 2 | Avatar | `SupabaseAvatarView(storageURL:size:28)` when non-empty, else a grey `person.crop.circle` 28×28 (`:1032-1039`). **Not a control** — no Button, no tap gesture |
| 3 | Menu | label is `Image(systemName:"line.3.horizontal")` — **no accessibility label, no title** (`:1063-1065`) |

| Order | Label | Icon | Action | Destination |
|---|---|---|---|---|
| 1 | **"Settings"** | `gear` | `homeDestination = .settings` | `SettingsView()` (`:1041-1043`, dispatch `:901-902`) |
| 2 | **"Appearance"** | `paintbrush` | `showThemePicker = true` | `themePickerSheet` (`:1044-1046`, sheet `:895-897`) |
| 3 | **"Design Lab"** | `paintpalette` | `homeDestination = .designLab` | `DesignLabView()` — marked `// TEMPORARY — removed at AMB.12 with the lab itself.` (`:1047-1050`) |
| 4 | **"Logout"** | *(none — a plain `Button(String)`, so no icon)* | `signOut()` then `isSignedIn = false` | — (`:1051-1062`) |

**Logout has no confirmation dialog and no user-visible error path** —
`catch { print("Logout error: …") }` (`:1058-1060`). A failed sign-out is silent and
the user stays signed in with no feedback. On a shared iPad that is a PII-retention
failure.

Both pushes route through `HomeDestination` (`:41-58`) and the single
`.ambientPush(item:)` at `:899`, implemented as a hidden `NavigationLink(isActive:)`
(`DesignSystem/AmbientFoundation.swift:316-333`). `HomeDestination.id` is a
conformance read by nothing, and its own comment says so (`:47-50`).

## 3.3 The appearance picker (`themePickerSheet`, `MainEmployeeView.swift:1176-1218`)

A **plain, untokenised** `NavigationView { List { … } }` (`:1177-1178`) with no
`listStyle`, `.navigationTitle("Appearance")` (`:1209`).

| Option | Label | Icon | Stored | Line |
|---|---|---|---|---|
| 1 | **"System"** | `gear` | `"system"` | `:1179-1187` |
| 2 | **"Light"** | `sun.max` | `"light"` | `:1189-1197` |
| 3 | **"Dark"** | `moon` | `"dark"` | `:1199-1207` |

Each row is a `Button` with `HStack { Label; Spacer; if selected { Image(systemName:"checkmark") } }`
— a bare checkmark with no tint. Toolbar: one trailing **"Done"** that only closes
the sheet (`:1210-1216`). **No Cancel — the choice commits the instant a row is
tapped** (`setTheme` writes storage before dismissing, `:1223-1229`).

**Storage:** key **`appTheme`**, `@AppStorage`, default `"system"`, **declared twice**
— `MainEmployeeView.swift:555` and `Iconik_EmployeeApp.swift:14` (same key, one
value). **`applyAppTheme()` exists in two copies with different bodies:**
`MainEmployeeView.swift:1232-1262` sets `window.overrideUserInterfaceStyle` on every
window of `connectedScenes.first` (`:1234-1247`), **then also writes the string
`"Light"`/`"Dark"` into `UserDefaults` under `"AppleInterfaceStyle"`** (`:1250-1258`)
and posts `AppleInterfaceThemeChangedNotification` (`:1261`);
`Iconik_EmployeeApp.swift:110-125` has the window half only.
**Nothing in the repo reads that key or observes that notification** — those two
statements are **dead**. The functional mechanism is `overrideUserInterfaceStyle`
alone. `connectedScenes.first` is unordered, so on iPad multi-window this can apply
the override to a scene other than the visible one (inferred from `:1235`, not
device-verified).

## 3.4 The sign-in gate and the launch state (`RootView.swift`, 89 lines)

```
if isCheckingAuth   -> ProgressView()
else if isSignedIn  -> MainEmployeeView(isSignedIn: $isSignedIn)
else                -> SignInView(isSignedIn: $isSignedIn)
```
(`:12-21`; `isCheckingAuth` starts true, `isSignedIn` false, `:5-6`.)

**The first frame is a bare, unmodified `ProgressView()` — `RootView.swift:15`.**
One line. No text, no logo, no background, no `progressViewStyle`, no `tint`, no
`controlSize`, no frame. Centred by `Group`'s default layout.

The gate reads `SupabaseAuthService.shared.isAuthenticated` once (`:36`) after
polling `sessionCheckComplete`, which is set true **on both branches** of the
do/catch (`SupabaseAuthService.swift:60-73`) — it means "the check finished", not
"the check succeeded". The poll runs to a **10-second deadline** (`:31`) sleeping
50ms per iteration (`:33`). On success (`:38-57`) the view **stays on the spinner**
while it awaits `initializeOrganizationIDAsync()`, `refreshCurrentUserProfile()`,
and — if the cached org id is still empty — **a second** profile refresh (`:47-51`).
**So the 10s deadline bounds only the poll; the three network awaits after it are
unbounded.**

| Launch state | Present? |
|---|---|
| Spinner label ("Signing you in…") | **ABSENT** |
| Branded splash / logo | **ABSENT** — no `Image` in the file |
| Timeout error | **ABSENT** — on deadline expiry control falls through and the user silently lands on SignIn |
| Offline detection / retry | **ABSENT** — no reachability check, no retry, no `Network` import |
| Error surface for the two profile refreshes | **ABSENT** — bare `await`s with no result inspection |
| Org-id-still-empty terminal state | **ABSENT** — retries once, then enters `MainEmployeeView` regardless with an empty org id |
| Poll cancellation | **Partial and worse than its sibling** — `try?` swallows the cancellation error (`:33`), so a cancelled sleep becomes a tight main-actor spin until the deadline. `MainEmployeeView.swift:522-530` explicitly `break`s out of exactly this and documents why; **RootView has no such break** |

**`RootView` has ZERO device conditionals** — the launch path is identical on every
device.

## 3.5 `HomeToolbarButton` (`Navigation/HomeToolbarButton.swift`, 41 lines)

`isPhone = UIDevice.current.userInterfaceIdiom == .phone` (`:17`); **on iPad the body
renders nothing** — `if isPhone` with no `else` (`:20-27`). Control is a `Button`
(`:21`) whose action sets `TabBarManager.shared.selectedTab = "home"` **by direct
singleton mutation, not a binding** (`:22`); label is `Image(systemName:"house.fill")`
with no size, weight or colour modifiers (`:24`); `.accessibilityLabel("Home")`
(`:26`); placement `.navigationBarLeading` (`:31-41`).

**Device consequence:** on iPad the toolbar leading slot is empty for every
shell-wrapped feature, and the only route home is the bottom bar's centre button.
`BottomTabBar.swift:1-5` states it bluntly: on iPad the bar is the sole route back.

## 3.6 Shell reference tables

### `isSelfNavFeature` (`MainEmployeeView.swift:765-779`) — complete

| Feature id | Self-nav | Condition |
|---|---|---|
| `capture`, `training`, `unflagUser`, `tasks`, `equipment` | yes | unconditional (`:767`) |
| `sportsShoot`, `focalPointSports` | **conditional** | `UIDevice.current.userInterfaceIdiom != .phone` (`:770-775`) — deliberately `!= .phone` so an iPad in Split View still counts |
| everything else | no | `default` (`:776-777`) |

### `featureContainer(for:)` (`:739-760`)

| Branch | What the shell applies |
|---|---|
| Self-nav | **NOTHING.** Renders bare — no NavigationView, no Home button, no clearance. The comment (`:744-750`) records why: applying clearance here double-stacked to 168pt on `EquipmentView`, a real `NavigationStack`, which honours an outer inset unlike a legacy `NavigationView` |
| Shell-wrapped | `NavigationView { view.homeToolbarItem().tabBarClearance(showsTabBar, keyboardVisible:) }` + `.navigationViewStyle(StackNavigationViewStyle())` |

`homeContainer` (`:723-734`) additionally applies `.navigationBarTitle("", .inline)`,
`.navigationBarBackButtonHidden(true)`, `.toolbar { homeProfileToolbar }` and the
same clearance. `mainContent` (`:698-712`) routes home → `homeContainer`; else if
available → `featureContainer`; **else a `Color.clear` that force-redirects to home
in `onAppear` (`:706-709`) — a silent bounce with no message.**

### Counts
**26 `FeatureItem`s** (19 employee `:112-132` + 7 manager, the manager array
**declared twice** and the `MainEmployeeView` copy dead); **27 dispatch cases +
`default: homeView`** (`:955-1015`) — the default **silently renders the dashboard
for an unknown id with no error**; **27 `FeatureTheme` entries + `default: .gray`**
(`DesignTokens.swift:33-76`), 10 families, all hexes distinct.

**Two registration asymmetries worth knowing:** **Settings is not a `FeatureItem`
at all** — no id, no dispatch case, no theme colour, reachable only from the profile
menu. **`chat` is the mirror case** — dispatched (`:960-961`), coloured
(`DesignTokens.swift:66`) and a registered tab-bar item (`TabBarItem.swift:108`),
but with **no `FeatureItem`**, so it never appears in All Features.

### The four device predicates (§0.19)

| Site | Predicate | Effect |
|---|---|---|
| `MainEmployeeView.swift:616-618` | `horizontalSizeClass == .regular && idiom == .pad` | **Note the AND** — a narrow-Split-View iPad is `.compact`, so it gets the **iPhone widget set** |
| `:775` | `idiom != .phone` | self-nav for Sports |
| `BottomTabBar.swift:184` | `idiom == .pad` | centre button, symbol, tint, max width, a11y label |
| `:585` | `idiom == .pad`, **a locally re-declared shadow of `:184`** | an iPhone-only branch in the customise screen |

**Two entirely different dashboards** hang off the first predicate
(`MainEmployeeView.swift:1382`): iPhone `[hours, mileage, shifts, tasks]` (`:25`) vs
iPad `[sportsRosters, classGroups, photoshootNotes]` (`:26`) — **zero overlap**, with
separately persisted orders (`:1383`, `:1402-1406`).
`BottomTabBar.swift:173` declares `horizontalSizeClass` and **never uses it**.
`TabBarItem.swift:325` sets max visible tabs to **10 on iPad, 6 on iPhone**.

### Shell dead code

| Item | file:line | Why dead |
|---|---|---|
| `MainEmployeeView.managerFeatures` | `:575-583` | declared, never read; AllFeaturesView carries an identical live copy |
| `AllFeaturesView.userRole` | `:8`, passed at `MainEmployeeView.swift:934` | never read |
| `UserDefaults "AppleInterfaceStyle"` write | `MainEmployeeView.swift:1250-1258` | nothing reads the key |
| `AppleInterfaceThemeChangedNotification` post | `:1261` | no subscriber in the repo |
| `BottomTabBar.horizontalSizeClass` | `BottomTabBar.swift:173` | declared, unused |
| `HomeDestination.id` | `:51-57` | conformance only; its comment says so |
| `LabPalette` | `DesignLab/LabPalette.swift` | no consumer outside `DesignLab/`; superseded by `DesignTokens.swift:33-76` |
| Nine mockup-file comment references | §2.0 | all point at deleted files |
| `HomeToolbarButton` body on iPad | `:20` | renders nothing |

---

# CONSTRAINTS THE REDESIGN MUST RESPECT

## Dead API surfaces — do NOT promise these in a mockup

- **No employee-side unflag request.** `FlaggedStatusView` is unreachable and its
  two columns have no readers. Building it is a feature, not a restyle.
- **No job-box flagging.** The columns do not exist. Either the schema grows or the
  three affordances come out.
- **No date filtering on the Job Box Tracker.** `selectedDate` is read by nothing.
- **No card-number concept on the tracker.** `cardNumber` is hardcoded `""`; every
  branch that reads it is unreachable.
- **No SD-card photographer anywhere** — not on save, not on read, not in search,
  not in the chart. The column does not exist (§0.26).
- **No multi-day metrics export.** `listFiles()` has no callers; only today's file is
  shareable, and it may not exist.
- **No kit-template detail screen** — the "Manage Kits" rows have never been
  tappable, and `EquipmentService` has no write method for them.
- **No NFC tag read-back, no duplicate-number check, no overwrite confirmation** in
  the writer.
- **No job-box offline cache** — SD cards fall back to a cache; job boxes throw.
- Dead service methods with zero callers: `JobBoxService.generateCustomShiftID`,
  `debugQueryAllJobBoxes`, `debugQueryJobBoxesByPartialShiftID`,
  `DatabaseManager.debugPrintJobBoxDocuments`, `PasswordResetViewModel.resetResetPasswordFlow`,
  `StatisticsView.findTappedStatus` / `labelPosition` / `startAngle` / `endAngle`,
  `StatusColors.hexColor`, `Color.rgbComponents`.
- Dead screens: `FlaggedStatusView`, `TimeEntryDetailView`, `TimeTrackingButton`,
  `TimeTrackingFloatingButton`, `ComingSoonView`.

## Cross-feature shared types

- **`ShareSheet` is declared in Yearbook and consumed by Training**
  (`PhotoCritiqueDetailView.swift:61`). **A Yearbook conversion is running in
  parallel and may move or rename that declaration.** State the coupling, do not pin
  the file: *Training requires an app-level activity-sheet wrapper it does not own.*
  Three near-identical wrappers exist (`ShareSheet`, `MetricsShareSheet`,
  `ImageShareSheet`) — consolidating them is the obvious AMB.12 cleanup and is a
  cross-feature change.
- **`EmptyStateView` is an unqualified global type** declared in
  `ClassGroupJobsListView.swift:146` (from batch 3) — a new global with that name
  collides.
- **`struct MapPin`** at file scope in `SchoolDetailView.swift:416-419` **shadows
  SwiftUI's own `MapPin`**.
- `JobBoxStatus`'s `CaseIterable` conformance is bolted on from a view file
  (`ManagerJobBoxTrackerView.swift:952-957`) and **excludes `.unknown`**.
- `StatsCard` (Training) and `AmbientStatTile` (design system) are two stat tiles;
  the redesign should not add a third.

## Shared web-app contracts

- **`STATUS_COLORS_DOCUMENTATION.md` declares the SD-card and job-box colour maps a
  cross-platform iOS↔web standard.** Re-tokenising them to AURA breaks a stated
  contract — operator decision (§0.21).
- **`job_boxes` is an append-only scan log** and its rows ARE a box's history. The
  shipped meter depends on that; so does the web app's reading of the same table.
- **`class_group_jobs` job-type ids** and the `records`/`job_boxes` status strings are
  stored values, not display strings — changing the vocabulary is a schema change.
- The `flag_user` / `unflag_user` RPCs enforce permission, org and self-target
  server-side; **the app-side `Permissions.has` checks are convenience, not the
  boundary** (`TeamService.swift:167-186`).

## Permission checks and their absence

- **There is no client-side permission gate on any batch-4 screen except
  `FlagUserView` and `UnflagUserView`.** The Job Box Tracker, Job Box Settings,
  Statistics and every Settings screen rely entirely on `AllFeaturesView.swift:95`
  (a section-level gate any `selectedTab` write bypasses) plus server-side RLS. A
  redesign must not *introduce* the impression of a gate that is not there, and must
  not remove the two that are.
- `AllFeaturesView` gates all seven manager features on `users:edit` all-or-nothing,
  and the `timeOffApprovals` row's own screen gates on a different area.
- Photos permission: `.limited` is treated as denied (`PhotoCritiqueDetailView.swift:244`);
  the photo library picker has no permission check at all
  (`ProfilePhotoView.swift:41`); NFC has exactly one availability check in the whole
  app and the writer does not use it.

## Structural rules inherited from earlier phases

- **D3 holds: no `NavigationStack` migration.** Pushes go through the
  `ambientPush` / `NavigationLink(isActive:)` wrapper because the shell hands
  features a `NavigationView` per NAV.1. `AmbientFoundation.swift:316` is the one
  wrapper; two push targets means an enum destination.
- **iOS 16.6 floor holds (D4)** — which makes ~150 lines of `#available(iOS 16.0,*)`
  else-branches in `StatisticsView` unreachable and not design to preserve.
- **A pushed screen does not inherit the container's `tabBarClearance`** — it must
  apply its own, as `AllFeaturesView.swift:136` and `PTOBalanceView.swift:315-319`
  do and as SettingsView and `ManagerEmployeeDetailView` do not.
- **Self-nav features get NOTHING from the shell** — no nav bar, no Home button, no
  clearance. `training` and `unflagUser` are self-nav; `scan`, `jobBoxTracker`,
  `flagUser`, `timeTracking` and everything else in batch 4 are shell-wrapped.
- **`JobBoxProgressRules.swift` must stay SwiftUI-free** — its 60-check harness
  depends on it.
- **The drift gate blocks a NEW hand-rolled card in any file in this batch** at exit
  2. `.ambientCard(…)` is invisible to it; `.cornerRadius` on a `Color` background
  with no shadow does not trip it, which is exactly why so many unconverted files
  carry no row.

## States that must be ADDED rather than preserved

Because they do not exist today and their absence is actively misleading:
offline on 13 of 14 Settings screens and on the Job Box Tracker; a loading state on
`StatisticsView`, `SchoolDetailView`, `UnflagUserView` and every Submit path; an
empty state on `SearchView` and `AddressAutocompleteField`; an error state on
Training, the tracker (retry), and every screen listed in §0.29 where a fetch
failure currently renders as "nothing here"; a 30-day-window explanation on the
tracker; a missing-org-id state; a success confirmation after a status edit; and a
confirmation on any payroll write other than delete.

## Things that are correct and easy to break

- `JobBox.timestampDate` returns `.distantPast` on nil **deliberately** — a prior
  `Date()` substitution made "latest scan" random (`JobBoxStatus.swift:26-36`).
- The manager's status buttons **INSERT rather than UPDATE** deliberately — an update
  falsified the scan moment and skipped the crew push trigger
  (`ManagerJobBoxTrackerView.swift:351-360`).
- The tracker rebuilds each box's history from the **unfiltered** row set (`:256`)
  because building it from search-filtered rows drew "never scanned" based on what
  was typed in a search field.
- The pickup guard **fails open** on offline or lookup error, by design
  (`JobBoxPickupRules.swift:96`, `:104`).
- Every `TimeTrackingService` update and delete proves a row changed
  (`requireRowsWritten`, `:44-48`) and **never folds case on `time_entries.id`**,
  because the column holds a mixed population.
- `PTOBalanceView`'s "hours used" caption is deliberate and accurate — it explains a
  real data gap rather than showing a wrong number.
- The employee flag banner is rendered **twice on purpose** (`MainEmployeeView.swift:1131-1136`).

---

## Verification status

**PROVED by live query:** `job_boxes` has exactly 10 columns and no
`flagged`/`flag_note`/`flagged_at`; `records` has 10 columns and **no
`photographer`**; live row counts `records` 4,168 (4,166 on one org), `job_boxes`
1,059, of which 17 fall inside the tracker's 30-day window; job-box status
distribution Packed 674 / Picked Up 160 / Turned In 159 / Left Job 66 with zero rows
outside the four; SD status distribution with **`Personal` at zero rows**; 336 of
1,059 job-box rows have a NULL or empty `photographer`; `records` and `job_boxes`
both carry RLS with org-scoped policies.

**NOT verified, flagged rather than claimed:** whether `NFCNDEFReaderSession` starts
under the `TAG`-only entitlement (§1.16.1 — the highest-value device check); whether
a second NFC write in one view session saves a record; whether the toast is clipped
at the MainEmployeeView call site on a device; whether `pto_settings` is stored
camelCase or snake_case (G45); whether the `user-photos` bucket is public or private
(G34); every CoreNFC writer branch. **NFC hardware cannot run in a simulator at all**
— everything in §1.16 marked unverifiable needs a physical device and a physical tag,
and no amount of simulator work substitutes.

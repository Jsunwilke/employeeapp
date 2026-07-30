# Batch 3 parity inventory — Mileage + Stats, Class Groups + Yearbook

Read from the source 2026-07-29, at the start of AMB.9, BEFORE any mockup
exists. Batch 3 is AMB.9 (Mileage + Stats) and AMB.10 (Class Groups +
Yearbook). AMB.8 was supposed to mock this batch and named it unbuilt instead —
same call AMB.6 made — so the mockups open AMB.9, and D10 blocks every real
screen until the operator approves them.

This exists because every phase of this arc that skipped or shortcut the
source-inward inventory shipped feature LOSS: AMB.3 lost three capabilities
inside an approved design, AMB.4 seventeen, AMB.5 four, AMB.6 four. The
inventory is the check; the mockup is only the proposal.

STATUS at creation: the AMB.10 half (Class Groups + Yearbook) is complete
below. The AMB.9 half (Mileage + Stats) follows in the next section as its
read completes.

---

# PART ONE — AMB.9: Mileage + Stats

Source-inward inventory, read from source 2026-07-29. Paths relative to
`Iconik Employee/` unless absolute. Two live DB checks were run against the
shared project (via `supabase db query --linked` from
~/Desktop/Focal-Point-Supabase); results in §6.

| File | Lines |
|---|---|
| `Misc Features/MileageReportsView.swift` | 276 |
| `Misc Features/MileageReportsViewModel.swift` | 377 |
| `Misc Features/MileageDetailView.swift` | 299 |
| `Misc Features/RoutePlannerView.swift` | 818 |
| `Services/RouteOptimizerService.swift` | 504 |
| `StatsView.swift` | 1005 |
| `StatsViewModel.swift` | 566 |
| `Manager Features/ManagerMileageView.swift` | 472 (VM + View in one file) |

## 0. HEADLINE FINDINGS (read these first)

1. **The Stats screen is almost certainly broken end-to-end right now.** `StatsViewModel` selects `start_time, end_time` from `daily_job_reports` (`StatsViewModel.swift:462-469`) and `id, value` from `schools` (`:300-305`). **PROVED by live query: none of `start_time`, `end_time`, `schools.value`, `schools.type` exist.** INFER (strong): both queries 400 → `errorMessage` set (`:381`, `:519`) → `StatsView.swift:23` replaces the *entire* tab area with "Error Loading Data", even though three of the five datasets loaded fine.
   **OBSERVED 2026-07-29 on the signed-in iPhone simulator, no longer an inference:** opening All Features → Management Features → Statistics renders "Error Loading Data — Error fetching photographer data: column daily_job_reports.start_time does not exist" with a Try Again button and NO content on any tab. The Statistics screen does not render for this org, and by construction cannot render for any org.
2. **Weather Impact on Jobs is hardcoded fake data** — `StatsViewModel.swift:526-543`, literal rows Clear/320/95, Cloudy/280/92, Rain/180/85, Snow/90/70, Fog/60/80. 930 fabricated "jobs" shown to every org with no caveat.
3. **Every total-mileage number on Stats is 2× actual.** `StatsViewModel.swift:239-245` adds to the `"total"` bucket in the `else` branch *and* again unconditionally on the next line. Only names literally `John`/`Sarah`/`Mike` take the other branch.
4. **Mileage Trends draws flat zero lines in grey for every real org.** `MileageData.subscript` answers only `"month"/"John"/"Sarah"/"Mike"/"total"`, `default: nil` (`StatsViewModel.swift:19-28`); the chart looks up real photographer names (`StatsView.swift:391`) → 0, `maxMileage` falls back to the literal `600.0` (`:367-371`), and `getColorForPhotographer` returns `.gray` for anything not John/Sarah/Mike (`:880-887`).
5. **Three mileage-money engines disagree** (§5.4) — Stats uses a flat 0.67, Mileage Reports uses the signed-in user's rate, Manager Mileage uses each employee's rate. Plus R22's two *authoring* engines. Four figures for the same miles.
6. **The Route Planner's Google Maps app deep link is malformed** and is the branch that fires when Google Maps *is* installed (`RoutePlannerView.swift:698-707`) — doubled `?` and web-style params against the `comgooglemaps://` scheme.
7. **No `.ambientCard` anywhere in any of the five files.** All containers hand-rolled. All five surfaces are shell-nav (parent `NavigationView`).
8. **Zero device-conditional code in any of the five files.** No second screen nobody has seen.

## 1. MILEAGE REPORTS (`MileageReportsView` + ViewModel)

### Reach, container, theme
- `FeatureItem(id: "mileageReports", title: "Mileage Reports", systemImage: "car.fill")` (`MainEmployeeView.swift:120`), default employee list, **no permission gate**, user-reorderable. Dispatch `MileageReportsView(userName: storedUserFirstName)` (`:984-985`).
- FeatureTheme **`#E8830C`** ("On the road" family, `DesignTokens.swift:41`). Shell-nav. Second entry: the home `MileageWidget` header is a `NavigationLink` to this screen (`DashboardWidgets.swift:731-732`). Short tab title "Mileage" exists (`TabBarItem.swift:74`).
- Drift-gate row: `MileageReportsView.swift|AMB.9|2`.

### Controls — the complete set is FOUR
Period carousel card ×6 (select + reload), list row `NavigationLink` → `MileageDetailView(record:personalRate:companyRate:)`, and that is all. **No add, no delete, no swipe, no search, no export, no toolbar items, no sheets, no alerts, no `.refreshable`** — loads via `.onAppear` only.

### Every displayed string (label-loss guard)
Carousel: start `MMM d`, "to", end `MMM d` (end **+13 hardcoded**, `:71`). "Selected Period: <medium> - <medium>" (`:88`). Summary cards: "Current Period" (`:99`), "Miles in <FullMonthName>" (`:109`, month from today), "Miles this Year" (`:120`, full width); inside each: big number, "miles" caption (`:225`), money "$n.nn", "reimbursement" caption (`:236`), and conditionally "Personal <n.n> · Company <n.n> mi" **only when company miles > 0** (`:244`, `VehicleRates.swift:57`). Rows: date `MMMM d, yyyy`, school name, orange "Company" pill when company vehicle (`:148-149`), "<n.n> miles" (`:164`), "$<n.nn>" (`:168`). Icons: calendar / **clock** (the month card uses a clock, `:113`) / calendar.badge.clock. Formatter-nil fallbacks "0.0" / "$0.00".

### Filter/sort + the period-length defect
`availablePeriods`: current + previous five, **hardcoded 14-day step** (`:11-24`) — **contradicts the settings model**: `PayPeriodSettings.type` is bi-weekly/weekly/monthly (`OrganizationService.swift:14`) and the *data* uses the real `payPeriodService.getPayPeriod` range (`MileageReportsViewModel.swift:213-215`), so for a weekly/monthly org **the carousel labels and the data disagree.** Rows sorted date-desc (redundant with the query). No client filter/grouping/search.

### States — all four absent
No loading, no empty, no error, no offline state of any kind. Both fetch paths swallow to `print` (`MileageReportsViewModel.swift:272-274`, `372-374`). **On any failure the cards read `0.0 miles / $0.00` — indistinguishable from a genuine zero-mileage period.** (The dashboard widget, by contrast, caches to UserDefaults.)

### Dead / suspicious
- `@AppStorage("userHomeAddress")` declared, never read (`MileageReportsView.swift:7-8`).
- `calculateMileage(forPeriodStart:periodEnd:)` — 19 lines, **zero callers** (`MileageReportsViewModel.swift:279-297`).
- **`selectedPeriodStart` is seeded before the pay period is known** (init reads a value that is `Date()` until an async completion replaces it) — on first render the selection typically matches **none** of the six cards (`:50`; VM `:44`, `89-106`).
- `currentPeriodStart/End` not `@Published` but mutated from async completions — carousel contents timing-dependent (`:44-45`, `93-94`, `175-176`).
- **Double fetch per appearance** (`.onAppear` calls both loaders; `loadRecordsInternal` already chains the second) (`MileageReportsView.swift:181-182`, VM `:267`); `loadRates()` refires on every carousel tap (`:183`).
- `updateCallback` is a single slot silently unsubscribing prior observers (`:48`, `110-112`); **two VM instances with different data** — `.shared` for the widget, fresh for the screen — an edit refreshes the screen only, the dashboard goes stale (`:5`; `MileageReportsView.swift:48`).
- `userName` fetched/stored/logged, never used functionally; nil userId → guard-return → **permanently empty screen, no message** (`:235-238`).
- 12+ emoji `print`s, several logging identity; magic reference date `"2/25/2024"` in fallback period math (`:162`).
- **"Current Period" mislabels a past selection**: the card's values are overwritten with the *selected* period's data (`:257-263`) while the title stays "Current Period" (`MileageReportsView.swift:99`).
- **Compensation is `Σ(miles) × today's rate`, not `Σ(miles × rate)`** (`:30-37`) — a rate change retroactively revalues history; the per-report accumulator that would fix it (`VehicleRates.Split.add`, `VehicleRates.swift:61-69`) **exists and is unused**.

## 2. MILEAGE DETAIL (`MileageDetailView`)

Pushed only from the list. Hand-rolled card with a manual dark-mode branch (`:29`, `:131-132`); nav modifiers + both alerts attached **inside** the ScrollView (`:180-197`) — porting trap. Save/Cancel/Edit are **inline content buttons, not toolbar items** (`:136-178`). Deprecated `presentationMode`.

Capabilities: Edit mode toggles four swaps — school (searchable picker sheet: "Select School" / "Done" / "Search schools..."), vehicle segmented Personal/Company (read-only mode shows the orange "Company car" line **or nothing at all for personal** — absence is the only signal), miles TextField `.decimalPad` 42pt centered, computed "$n.nn reimbursement". Save validates number ("Invalid mileage value. Please enter a number.") and school ("Please select a school."); success alert "Changes Saved" → pops. **The screen exposes 3 of 28 model columns and is a dead end** — no delete, no link to the full report.

Defects: **two stacked `.alert` modifiers** (deprecated + iOS15 form — swallow hazard, `:183-196`); `errorMessage` never cleared (`:23`); **zero org schools → permanent "Loading schools..." with no retry AND an unsatisfiable "Please select a school."**; school stored **by NAME not id** — a rename orphans history (`:271`); rates are `let`s captured at push time — late-resolving parents pin 0.67/0.10 for the screen's lifetime (`:14-15`); Save not disabled in flight → repeated UPDATEs (`:156`); offline edit = raw error, lost; **no permission/ownership gate on editing**; `import Supabase` in a view writing the UPDATE inline — no service method exists for this write (`:269-278`); the UPDATE carries **no user_id/org filter** — RLS is the only cross-tenant guard (flagged for verification, §6).

## 3. ROUTE PLANNER (`RoutePlannerView` + `RouteOptimizerService`)

### Reach + structure
`FeatureItem(id: "routePlanner", "Route Planner", "map.fill")` (`MainEmployeeView.swift:131`), default employee list, no gate, dispatch `:1010-1011`. FeatureTheme **`#F76B15`**. Shell-nav; no short tab title. Drift row `RoutePlannerView.swift|AMB.9|1`, and the generator's own header note records: mileage is AMB.9's, but the **route planner "belongs to no phase in the list at all"** — retagged to AMB.9 so the row wouldn't read as AMB.7 having failed; **where it lands is the operator's call** (`check_card_drift.py:106-111`).

**The screen is two full-screen modes swapped by one boolean** (`:66-72`) — no push, no sheet. In preview mode the user sees the system "Route Planner" bar **plus** a hand-rolled second header ("Optimized Route") — two stacked title rows (`:277-298`).

### Mode A — selection
Hand-rolled search bar (not `.searchable`); filter searches **name + address only** (city/state/zip/district/notes not searched, `:37-45`). Start picker segmented **Current / Home / Work** (unavailable segments not disabled; orange warnings "Home address not set in profile" / "Organization address not available"). End point: Toggle "Add End Point" (disabled when neither address available), picker **Home / Work** (labels asymmetric with start's `shortName`s), footer names only "home" though a work address also satisfies it. Schools section: header "Schools" + "<n> selected" + "Clear"; rows are whole-row buttons with checkbox, name, one-line address, and a coordinate indicator (`mappin.circle.fill` green / `mappin.slash` orange) — **indicator only, does not block selection**. Bottom "Optimize Route"/"Optimizing..." bar **renders only at ≥2 selected — below 2 there is no button and no explanation.**

### Mode B — preview
Back "Edit" chevron; totals pill (car + distance, clock + duration) **only when distance > 0**; list of start row (green circle, icon, "Current Location/Home Address/Work Address", caption "Starting point"), per-leg rows (`arrow.down`, "<dist> • <dur>", hidden when 0), numbered blue stop circles, optional red end row; two buttons "Open in Apple Maps" (blue) / "Open in Google Maps" (gray). **There is no map** — no MapKit import, no polyline (the server is asked not to return one). The route is a text list.

### States
Loading overlay "Loading schools..."; one alert "Error" (`.constant` binding, OK clears); **no empty state** (no schools / no match → blank section, "0 selected"); **no offline state**; **location permission never surfaced** — a denied user learns only via a 2-second timeout message after tapping Optimize; no `.refreshable`.

### Dead / suspicious (the worst list of the five)
1. **Google Maps deep link malformed on the installed-app branch** (`:698-707`): rewrites the web URL prefix onto `comgooglemaps://?` → doubled `?`, wrong param scheme; `comgooglemaps` IS in `LSApplicationQueriesSchemes`, so the broken URL wins whenever the app is installed. Plus a force-unwrapped `URL(string:)!` on the same path.
2. **Coordinate-less schools are selectable, counted, then silently dropped** by `validSchools = filter { parsedCoordinates != nil }` (`RouteOptimizerService.swift:203`) — no notice.
3. **`skippedShipments`** (schools Google refused to route) decoded, counted, printed — never surfaced (`:265-272`).
4. **A failed optimization is indistinguishable from success**: no `optimizedOrder` → the service silently returns the ORIGINAL order with `totalDistanceMiles: 0`, and the `> 0` gate hides the totals pill (`:274-284`; `RoutePlannerView.swift:301`).
5. **The server's real error is discarded** — read, printed, then a hardcoded `apiError(500)` thrown; 5 of 7 error cases unreachable (`:258-262`, `:480-503`).
6. **Fixed 2-second `Task.sleep` as the location strategy** (`:584-586`) — cold GPS fix routinely loses.
7. `checkAddressAvailability()` can mutate the start/end selection **while the preview is on screen** (realtime org-coordinate updates), and the preview labels read live `@State` — the displayed start/end can silently change to something the route was not computed for (`:79-81`, `522-535`).
8. `isStartingPointAvailable` never called; `OptimizedRouteResult.startingPointType` set 5×, read 0×; `authorizationStatus` published, never read; `getSchools` **does not filter `is_active`** — deactivated schools appear (`SchoolService.swift:39-51`); verbose prints of school names + precise coordinates; edge function logs full request/response.

### What the optimizer can and cannot carry
Thin client for the `optimize-route` Supabase Edge Function → Google **Route Optimization API** (VRP solver). No API keys in the app. Per-school hardcoded 5-min service time (not included in the reported duration — travel time only); **cost model 10,000:1 distance:time** (`costPerKilometer: 1000` vs `costPerHour: 0.1`) — the solver accepts an almost arbitrarily slower route to save a kilometre; `considerRoadTraffic: false`; no polyline requested (nothing to draw); OAuth token minted fresh per request. Single-destination short-circuits to zero miles without calling Google.

**Cannot deliver:** offline anything; dropped/skipped school visibility; traffic; time windows or appointment times; a drawable route; **any persistence** (`@State` only — dies on navigating away); **any mileage record or reimbursement** — the Route Planner has NO money math and is fully disconnected from the reimbursement chain (§5.5). Home "address" is actually a `"lat,lng"` coordinate string (`UserDefaults "userHomeAddress"`); work = org coordinates via realtime. Duration display **truncates** minutes (59.9 → "59 min"); sub-mile legs read "0.0 mi"; zero-distance legs disappear entirely.

## 4. STATS (`StatsView` + `StatsViewModel`)

### Reach + container
`FeatureItem(id: "stats", "Statistics", "chart.bar.fill")` in **managerFeatures — declared verbatim in two files** (`MainEmployeeView.swift:575-582` never rendered; `AllFeaturesView.swift:16-23` live). Gate is section-level `Permissions.has("users", level: .edit)` at `AllFeaturesView.swift:94-96`; **`featureView(for:)` re-checks nothing** — any `selectedTab = "stats"` write bypasses it. FeatureTheme **`#7A7FA6`** ("Manager tools — deliberately desaturated") — **never applied as a backdrop; the screen has no wash.** Exactly one entry path (All Features → Management Features). Shell-nav. `.onAppear` refetches all five queries every appearance, no guard. Drift row `StatsView.swift|AMB.9|7` — the largest in the file. Two hand-rolled card recipes (`ChartCard` ×14, `summaryCard` ×4) plus a third inline in the error view.

### Controls
"Photography Business Analytics" title; segmented **Month/Quarter/Year** (fixed width 200, hardcoded cases, default Year); custom five-button tab strip **Overview / Mileage / Locations / Photographers / Job Types** (not a TabView; switching does not refetch); error-view "Try Again". **No sort, no filter, no search, no pull-to-refresh, no toolbar.**

### States
Loading spinner (initialises `true`); **error replaces the entire tab area** (header + strip remain); **no empty states** — empty arrays render titled cards with nothing inside; mileage+location+jobType all empty → "No data available for the selected time period" rendered as an **error**; no offline handling.

### Cards (all five tabs, every literal)
- **Overview:** 2-col stat grid — "Total Mileage"/"<n> miles"/"Avg <n> per month" (car, blue); "Total Jobs"/"Across <n> job types" (briefcase, green); "Photographers"/"Avg <n> jobs each" (person, orange); "Locations"/"Avg <n.n> visits each" (mappin, red). "Mileage Summary" card — columns "Total Miles" / "Total Jobs" / **"Avg Locations" (mislabelled — the value is avg visits per location)**. "Job Types Distribution" — **renders no distribution graphic despite the title** (dot + name + % only). "Monthly Mileage" — horizontal-scroll purple bars.
- **Mileage:** "Mileage by Photographer" (h-bars); "Mileage Trends" (hand-drawn Path lines, legend, **max 3 photographers by hard cap**); "Mileage Reimbursement" (green bars, "$<Int>" truncated whole dollars).
- **Locations:** "Top Locations by Visits" / "Locations by Mileage" / "Visit Efficiency (Miles per Visit)", each `.prefix(5)` h-bars (orange/purple/teal).
- **Photographers:** "Jobs by Photographer" / "Average Job Time (Hours)" / "Jobs per 100 Miles" (blue/green/orange).
- **Job Types:** "Job Type Distribution" — **a nested ScrollView pinned to 300pt inside the page ScrollView**; "Weather Impact on Jobs" — the fake data, labels Clear/Cloudy/Rain/Snow/Fog, caption "On-time arrival:".
- **No Swift Charts anywhere** — every chart is hand-built Rectangles/Paths with **no axes, no gridlines, no scale**; bar scaling has a **5pt floor so a zero value still draws a visible bar**.

### Number computations (exact)
- **Windows are rolling, not calendar** — "Month" = trailing ~31 days, "Year" = trailing 12 months (`:548-565`); UTC filter instants vs local bucketing → boundary reports land in the wrong bucket.
- **Monthly buckets have no year in the key** → a 12-month window sums the same month from two years into one bar; buckets sorted Jan→Dec so a trailing window renders out of chronological order (`:222-263`).
- Reimbursement = personal×0.67 flat + company×org rate (**per-photographer `amount_per_mile` deliberately not consulted**, comment `:77-82`); displayed `$<Int>` truncated.
- `totalJobs` counts **job-description entries, not reports** (a report with 3 descriptions counts 3); `avgMileagePerMonth` is integer division by *buckets present*, not months; `totalLocations` counts **all org schools including never-visited**; visits = one per school per local day; location match is **exact case-sensitive name string** — free-text destinations become "locations".
- Photographer roster = `users.first_name` only — **no user_id: two employees named Chris merge; renames orphan reports**; a report with no mileage **is not counted as a job at all**; avgJobTime defaults to the literal **3.0 hours** when timestamps are missing — and since the columns don't exist, **it would be 3.0 for every row even if the query succeeded**.

### Dead / faked / suspicious (selection; full list in the drift-gate section)
Fake weather (§0.2); 2× mileage (§0.3); phantom columns (§0.1); `monthlyRevenue`/`MonthlyRevenueData` fully dead; `MileageData.john/sarah/mike` demo fields; Trends month labels drawn **through the middle of the chart** and gridlines mispositioned; `let id = UUID()` on every model → identity churn, O(n) colour lookups per row; **no `.limit()` on any query** → default row cap silently truncates (~2,500-row table); **four separate full reads of `daily_job_reports`** for the same window; `errorMessage` never cleared by later success, 5 tasks race to write it; only one of four fetches guards empty org id; `StatTab.icon` computed never used; `TimeRange: CaseIterable` unused; manager-features array duplicated verbatim in two files.

## 5. MANAGER MILEAGE (`ManagerMileageView`) — scope call for the operator

Reached only via All Features → Management Features behind `Permissions.has("users", .edit)`; FeatureTheme **`#8A7A5F`** (Manager tools family). **It belongs with AMB.12 Manager tools, not AMB.9** — except its money math is one of the three disagreeing engines, which AMB.9 must reconcile or name even if it doesn't redesign the screen.

Capabilities: 6 fixed 14-day period cards (**hardcoded 2/25/2024 anchor — `PayPeriodService` never consulted**, unlike the employee screen); flat list of employees with **hidden hardcoded filter: only `periodMiles > 0`** — an employee with zero period miles but month/year miles is invisible; per-row: name, "Rate: $n.nn", optional split caption, "This Period / Miles in <Month> / Miles this Year" with money each; push to `ManagerEmployeeDetailView`. **"Miles in <Month>" uses TODAY's month name over the SELECTED period's numbers** — pick a June period and the row reads "Miles in July" over June's figures (`:414-416`, `:240`). No loading state rendered (`isLoadingOrgID` written, never read), no empty state, no export, no org-wide grand total, no filter/sort controls, no realtime. Year-clamped query loses cross-year period days; no `.limit()` → row-cap truncation risk. The org-rate read is `try?`-swallowed → silent 0.10 fallback.

### 5.4 THE MONEY FIGURES — three consumer engines + R22's two authoring engines

R22 verbatim (`AMB_BATCH2_PARITY.md:905-908`): the standard form uses real MKDirections driving routes; the template form's smart field uses straight-line Haversine; both write the same `total_mileage` column that feeds reimbursement.

| Engine | Personal rate | Period source | Month/year basis |
|---|---|---|---|
| Mileage Reports (employee) | signed-in user's `amount_per_mile`, nil-or-0 → 0.67 | org-configured `PayPeriodService` (2/25/2024 math only as fallback) | today |
| Manager Mileage | **per-employee** `amount_per_mile` | **hardcoded 2/25/2024 + 14 days** | selected period |
| Stats | **flat 0.67, ignores rates entirely** | rolling windows from now | trailing, year-less keys |
| Hand edit (4th writer) | — | `MileageDetailView` in-view UPDATE | — |

Consequences to name rather than fake: if the org's pay period is anything but a 2/25/2024-anchored 14-day cycle, **the manager's period boundaries disagree with what the employee sees**; browsing back a period changes the manager's month/year totals but not the employee's, so past periods never match; and the mile→dollar constant `0.000621371` is duplicated at three Swift sites with no shared constant.

## 6. LIVE DB VERIFICATION (2026-07-29, shared project, `supabase db query --linked`)

**PROVED — `public.daily_job_reports` has exactly 31 columns**; **`start_time` and `end_time` DO NOT EXIST**; `vehicle_type`, `school_or_destination`, `total_mileage` exist.
**PROVED — `public.schools`:** `name` and `is_active` exist; **`value` and `type` DO NOT EXIST.**

Consequences: the two Stats queries citing phantom columns fail → whole-screen error (INFER, §0.1). The same phantom columns appear at `DashboardWidgets.swift:1741` (selects `value`, filters `type` — a second suspect path) and `ShiftDetailView.swift:1281`. `DATABASE_SCHEMA.md` is stale in both directions (missing the real `vehicle_type`, listing nothing about `value`) — treat the live query as the only authority.

Not verified, flagged: `optimize-route` `verify_jwt` state (no `supabase/config.toml` in this repo); whether Google emits a trailing transition when an end point is set (the end row may display the last leg's distance twice); RLS on `daily_job_reports` against `MileageDetailView`'s unscoped in-view UPDATE; whether `getCurrentUserIDUnified()` returns lowercase (several `eq` comparisons carry no `.lowercased()`).

## 7. Drift-gate status for AMB.9

Rows owned by AMB.9: `MileageReportsView.swift|2`, `RoutePlannerView.swift|1`, `StatsView.swift|7` — shrink-only; AMB.9 must reduce them to zero. **Three AMB.9-scope files have NO row and are nonetheless unconverted** (`MileageDetailView`, `ManagerMileageView`, plus the service) — the gate's documented `.background + .cornerRadius` blind spot. An empty allowlist row means nothing about whether a surface is converted. `LabPalette.swift` carries a stale parallel colour map for all four features (lab-only, dies at AMB.12).

---

# PART TWO — AMB.10: Class Groups + Yearbook

Source-inward inventory, read from source 2026-07-29. All paths relative to
`Iconik Employee/` unless absolute.

Files read completely: `Class Groups/Models/ClassGroupModels.swift` (317), `Class Groups/Services/ClassGroupJobService.swift` (633), `Class Groups/Views/ClassGroupJobsListView.swift` (228), `ClassGroupJobDetailView.swift` (287), `AddClassGroupView.swift` (360 — **two** views), `CreateClassGroupJobView.swift` (209), `ClassGroupSlateView.swift` (136); `Yearbook/Models/YearbookModels.swift` (293), `Yearbook/Services/YearbookShootListService.swift` (546), `Yearbook/ViewModels/YearbookShootListViewModel.swift` (399), `Yearbook/Views/YearbookShootListsView.swift` (243), `YearbookChecklistView.swift` (316), `YearbookItemRow.swift` (336), `YearbookChecklistViewForSession.swift` (201).

**Screen count for the redesign: 11 distinct surfaces** (5 Class Groups views containing 7 top-level types; 4 Yearbook view files containing 6 top-level types).

## 0. Headline findings (read these before designing)

1. **Neither feature uses the design system at all.** Zero `FeatureTheme`, zero `.ambientCard(...)`, zero design tokens in either directory. Every surface is a hand-rolled `Color(.systemGray6)` + `.cornerRadius(...)` block. The registered brand colours exist but never reach the screens (§5).
2. **`check_card_drift.py` has NO allowlist row for either directory** and reports "clean" — but that is a false negative, not a conversion. The gate matches a rounded *fill*; `.background(Color…) + .cornerRadius(…)` slips past it (`scripts/check_card_drift.py:116-120`), and that exact shape is present in both features (`ClassGroupJobDetailView.swift:234-239`, `YearbookShootListsView.swift:75-76`). `EXEMPT_DIRS = ("DesignSystem", "DesignLab")` (`scripts/check_card_drift.py:72`) — so the hook *will* fire on new writes into these directories once real card fills appear.
3. **There is no way to create a yearbook list from iOS.** Both the "+" toolbar button (`YearbookShootListsView.swift:26`) and the empty-state "Create Yearbook List" button (`:70`) open a sheet whose entire body is `Text("Create New Yearbook List")` (`:36-39`). A redesign must not promise a create flow.
4. **"Mark All Required Complete" does nothing.** `markAllRequired()` is an empty function (`YearbookChecklistView.swift:266-268`), wired to a live session-only menu item (`:64-70`).
5. **Zero permission checks in either feature.** No `Permissions.has`, no created-by/ownership test, no status gating. Any signed-in org member can create, edit and destructively delete any Class Groups job and any yearbook item. The `YearbookError.permissionDenied` case exists (`YearbookModels.swift:286`) and is never thrown.
6. **Zero iPad adaptation in either feature.** No `isIPad`, no `horizontalSizeClass`, no `userInterfaceIdiom` anywhere in either directory (§2). AMB.10 designs the iPad layout from scratch, not adapting one.
7. **The Yearbook cache can serve indefinitely stale data, and realtime reads *through* the stale cache.** See §4 "Cache correctness".
8. **Every Class Groups and Yearbook write is a whole-row read-modify-write with no concurrency guard.** Two photographers on the same job/list silently lose each other's work.

## A. CLASS GROUPS

Registered as feature id **`classGroups`**, title **"Groups"**, icon `person.3`, description "Track class group, candid, and club photos" (`MainEmployeeView.swift:127`). One feature, **three job types** switched by a segmented picker: `classGroups` / `classCandids` / `clubs` (`ClassGroupModels.swift:9-14`).

### A.5 How it is reached / theme

| Path | Evidence |
|---|---|
| Feature menu / bottom bar → shell route | `MainEmployeeView.swift:976-977` `case "classGroups": ClassGroupJobsListView()` |
| iPad dashboard widget → tab switch deep link | `DashboardWidgets.swift:1285-1287` sets `tabBarManager.selectedClassGroupJobId` / `selectedClassGroupJobType` then `selectedTab = "classGroups"`; consumed by `ClassGroupJobsListView.swift:121-142` `checkForSelectedJob()` |
| iPad dashboard widget → **direct create sheet, bypassing the feature screen** | `DashboardWidgets.swift:1378-1379` `.sheet { CreateClassGroupJobView(initialJobType: "classGroups") }` |
| All-features grid | `AllFeaturesView.swift:59-62` sets `tabBarManager.selectedTab = feature.id` |
| Bottom-bar quick access | eligible — short title `"Groups"` at `Navigation/Models/TabBarItem.swift:80` |

- **Nav ownership: shell-owned.** `classGroups` is not in `isSelfNavFeature` (`MainEmployeeView.swift:765-779`), so `featureContainer(for:)` (`:739-760`) wraps it in the shell `NavigationView` with `.homeToolbarItem()`, `.tabBarClearance(...)`, `StackNavigationViewStyle`.
- **FeatureTheme colour: `#46A758`** (green) — `DesignSystem/DesignTokens.swift:47`. Historical lab value `.teal` at `DesignLab/LabPalette.swift:59`; approved hex at `:101`.
- **Availability gating: none** — `getAvailableFeatures()` filters only the three photoshoot-notes-only ids.

### A.1 Screen: `ClassGroupJobsListView` (`ClassGroupJobsListView.swift:3`)

**Title:** `.navigationTitle(ClassGroupJobType.displayName(selectedTab))` (`:51`) → "Class Groups" / "Class Candids" / "Clubs".

Controls:
- **Segmented picker** (`:22-28`) — segments "Class Groups" / "Class Candids" / "Clubs" from `ClassGroupJobType.all` (`ClassGroupModels.swift:23-29`).
- **List rows** — `NavigationLink(destination: ClassGroupJobDetailView(jobId:), tag:, selection:)` (`:36-47`), the deprecated tag/selection form used deliberately so widget deep-links can drive selection. `.listStyle(InsetGroupedListStyle())`.
- **Swipe-to-delete a whole job** — `.onDelete(perform: deleteJobs)` (`:46`).
- **Toolbar trailing `+`** (`:53-59`).
- **Sheet:** `CreateClassGroupJobView(initialJobType: selectedTab)` (`:61-68`); completion sets `selectedJobId` after a hard-coded 0.5 s `asyncAfter` (`:64-66`).
- **Alert:** `"Delete Job?"` / Cancel / Delete (destructive); message "This will delete the entire job and all its \(rowNounPlural). This action cannot be undone." (`:75-84`).

Filter / sort / grouping: `filteredJobs` = jobs filtered to the selected type (`:15-17`). **No search, no secondary grouping, no user sort.** Order from the query `order("session_date", ascending: false)` (`ClassGroupJobService.swift:444`).

States: loading `ProgressView("Loading jobs...")` gated `isLoading && isEmpty` (`:30-32`); empty `EmptyStateView` (`:33-34`, defined `:146`). **No error state** — `service.error` is never read by any view; a failed load renders as "no jobs". **No offline state, no `.refreshable`.**

Lifecycle: `.onAppear { loadData() }`; `.onDisappear { service.stopListening() }`.

`EmptyStateView` (`:146`) — icon `person.3`/`camera`/`person.2` by type, "No \(singularTitle) Jobs", "Create a job for an upcoming session to start tracking \(rowNounPlural)", Button `Label("Create Job", systemImage: "plus.circle.fill")` `.borderedProminent`.

`ClassGroupJobRowView` (`:179`):
- `formattedDate` `.headline`, format `"EEEE, MMM d"` — **no year**.
- `job.schoolName` `.subheadline`/`.secondary`.
- If count > 0: `Label("\(count) \(countNoun)", systemImage: "person.3")` `.caption` `.blue`; else `Text("No \(countNounPlural) added")` `.caption` `.orange`.
- If images > 0: `Label("\(totalImageCount) images", systemImage: "photo")` `.caption` `.green` — never singularized.

### A.2 Screen: `ClassGroupJobDetailView` (`ClassGroupJobDetailView.swift:3`)

Input `jobId: String`. **Nav bar deliberately blank** — `.navigationTitle("")` + `.inline`; the real title is in-body.

Displayed: `job.schoolName` `.largeTitle` bold centered; job type display name `.headline`/`.secondary`; **the session date is never shown on this screen**; **`job.notes` (job-level) is never displayed or editable anywhere in the feature**; `List` of `ClassGroupDetailRowView` with `.onDelete`.

Controls: toolbar `+` → `AddClassGroupView` sheet; `.sheet(item:)` → `EditClassGroupView`; `"Error"` alert; `"Delete \(singularTitle)?"` alert with "Are you sure you want to delete this \(rowNoun)?".

States: loading; empty → `emptyStateView` (`:115-139`, uses the **plural** display name where the list's empty state uses the singular; "Tap the + button to add \(rowNounPlural) as you photograph them"; `Add \(singularTitle)` button); not-found `Text("Job not found")` — reachable, but `loadJob` also raises the error alert for a missing job, so the user gets both at once. **No offline state, no pull-to-refresh.**

`ClassGroupDetailRowView` (`:191`):
- `"\(grade) - \(teacher)"` hard **22 pt** bold — renders `"3rd Grade - "` with a dangling dash when teacher is blank (teacher optional; only grade required, `AddClassGroupView.swift:143`).
- `"Images: \(imageNumbers)"` 16 pt `.blue` lineLimit(nil) / else `"No images"` 16 pt `.gray`.
- If notes non-blank: `note.text` icon + "Has notes", 14 pt `.orange`. **The note body is not shown — you must open Edit to read it.**
- Hand-rolled card: padding 16/12, `Color(.systemGray6)`, cornerRadius 10 (`:234-239`).
- **Edit button** pencil `.blue` 36×36; **Slate button** `camera.viewfinder` `.green` 36×36 → `.fullScreenCover` → `ClassGroupSlateView(grade:teacher:schoolName:)` (`:270-276`) — **the only place the slate gets a real school name**.

### A.3 Screens: `AddClassGroupView` + `EditClassGroupView` (`AddClassGroupView.swift:3`, `:178`)

Two **line-for-line duplicate** forms differing only in container, title, populate-on-appear (Add `NavigationView`+StackStyle, Edit `NavigationStack`), and dismissal API (`presentationMode` vs `dismiss`).

Form: section "\(formNoun) Information" → "Class / Candid / Club Information"; `TextField` placeholder **"Grade"** or **"Club Name"**; **grade-suggestion `Menu`** (not for clubs) with 14 items from `ClassGroup.commonGrades` ("Pre-K"…"12th Grade"); `TextField` **"Teacher Name"** or **"Advisor Name"**; section **"Images"** with comma-separated numbers field (`.numbersAndPunctuation`) and live count caption (naive split — `"12,"` reads as 1); section **"Notes"** `TextEditor` minHeight 100, no placeholder; inline saving `ProgressView`; **"Show Whiteboard"** full-width button disabled until grade non-blank. Toolbar Cancel / Save, Save disabled unless grade non-blank — teacher, images, notes all optional. `@FocusState` chain grade→teacher→images→notes. `.fullScreenCover` slate with **schoolName hard-nil on both form paths** (`:135`, `:315`). Save trims all fields; failure alert "Failed to save/update: …"; `onComplete(false)` never called.

### A.4 Screen: `CreateClassGroupJobView` (`CreateClassGroupJobView.swift:3`)

Title "Create \(singularTitle) Job". Loading gated on empty. Empty state (`:30-45`): `calendar.badge.exclamationmark`, "No Available Sessions", "There are no upcoming sessions without \(rowNoun) jobs in the next 2 weeks." — **no escape hatch**; the 2-week window is hard-coded server-side (`ClassGroupJobService.swift:90-91`). `List` of session rows, tap-to-select single-select, no deselect. Toolbar Cancel / "Create Job" (disabled until selection). **No job-type picker on this screen** — `selectedJobType` only ever assigned `initialJobType`.

`ClassGroupSessionRowView` (`:157`): `"EEE, MMM d 'at' h:mm a"` `.headline`, fallback **"Date not available"** when startDate nil; school `.subheadline`/`.secondary`; session types joined `.caption` `.blue`; selected → `checkmark.circle.fill` `.blue` + row background `Color.blue.opacity(0.1)`.

### A.5b Screen: `ClassGroupSlateView` (`ClassGroupSlateView.swift:3`) — the shooting whiteboard

Hard white full-screen (intentionally not theme-aware). `Text(grade)` dynamic ~15% of min dimension, bold black; `Text(teacher)` at 0.9×; optional school name at 0.5× `.gray`. Exit `xmark.circle.fill` 44 pt top-trailing. **Tap-anywhere-to-dismiss** (`:65-69`) — no confirmation; a stray tap kills the slate mid-shoot. Status bar hidden; brightness → 1.0 on appear; idle timer disabled on appear, restored on disappear; **brightness deliberately never restored** (comment `:91`).

## B. YEARBOOK

Registered as feature id **`yearbookChecklists`**, title **"Yearbook Checklists"**, icon `list.clipboard` (`MainEmployeeView.swift:126`).

### B.5 How it is reached / theme

| Path | Evidence | sessionContext |
|---|---|---|
| Feature menu / bottom bar → shell route | `MainEmployeeView.swift:974-975` → `YearbookShootListsView()` | **nil** |
| **Schedule → shift detail → clipboard button → sheet** | `Schedule/ShiftDetailView.swift:861-871` (gated `!session.schoolId.isEmpty`) → `.sheet` at `:262-275` `NavigationView { YearbookChecklistViewForSession(...) }` | **non-nil** |

The schedule sheet passes schoolId/schoolName plus `YearbookSessionContext(sessionId:, photographerId: currentUserID ?? "", photographerName: … ?? "Unknown", sessionDate: session.startDate ?? Date())`. It is a **sheet, not a push**, and brings its own `NavigationView`.

- **Nav ownership: shell-owned** for the root list.
- **FeatureTheme colour: `#2E9B4F`** (deeper green) — `DesignSystem/DesignTokens.swift:48`. Lab placeholder `.purple` at `LabPalette.swift:58`, approved hex at `:102`.
- **No bottom-bar short title** (falls back to the full "Yearbook Checklists"); **no dashboard widget**; no availability gating.

### B.1 Screen: `YearbookShootListsView` (`YearbookShootListsView.swift:3`)

Title "Yearbook Checklists". Toolbar `+` → `showingCreateList`, disabled on nil org id. `.searchable` always visible. `.refreshable` exists but is **fire-and-forget** — `loadLists` (`:144-147`) does no awaited work, the spinner vanishes before data arrives. Create sheet is the **placeholder Text** (§0.3). Error alert with `.constant(...)` binding, OK clears. `.onAppear` re-subscribes on every appearance.

States: loading gated on empty; empty state (icon `list.clipboard`, "No Yearbook Lists", "Create your first yearbook checklist to track photo requirements for schools.", blue "Create Yearbook List" button — **not disabled on nil org id, unlike its toolbar twin**). **No error state in body, no offline state. No empty-search-results state** — the empty check tests the *unfiltered* array, so filtering to zero rows renders a blank List.

Content: `List` grouped by school (`Dictionary(grouping:)` by schoolName, ascending), section header `building.2` `.blue` + school `.headline`, rows `NavigationLink` → `YearbookChecklistView(shootList:, sessionContext: nil)`. **No swipe actions, no delete** — `deleteYearbookList` is unreachable from any UI.

Search: school name (case-insensitive) OR schoolYear (**case-sensitive**, `:118`) OR any item name (case-insensitive).

`YearbookListRow` (`:151-237`): `yearDisplay` "2024-2025"→"2024-25" `.headline`; `isActive` → green "CURRENT" chip; `isCompleted` → green checkmark; linear `ProgressView` tinted by ladder (**`total: 0` for a zero-item list**); "\(completed)/\(total)" `.caption`; optional category summary "A, B, C +N more" one line; "Updated \(relative)" `.caption2` (**new `RelativeDateTimeFormatter` per body evaluation**). `progressColor`: 100 green / ≥75 orange / ≥50 yellow / else **red — a brand-new 0 % list renders red**, reading as an error.

### B.2 Screen: `YearbookChecklistView` (`YearbookChecklistView.swift:3`)

`init(shootList:sessionContext:)` sets `viewModel.selectedShootList` **once**. **This screen never subscribes to realtime and never refetches** — data goes stale the moment it is pushed; another photographer's completions never appear.

Title: "\(schoolName) • \(shortYear)" (or "Yearbook Checklist"), `.inline`. Toolbar overflow `Menu` (`ellipsis.circle`): Filters toggle; Export → `exportChecklist()`; **session-context-only** "Mark All Required Complete" → **empty function** (`:266-268`).

Body: `progressHeader` always; `filterBar` (condition always true); `searchBar` when filters shown; `filteredItems.isEmpty ? emptySearchResults : checklistContent`; else "Checklist not found". **No offline state, no `.refreshable`, and no error surface at all** — `viewModel.error` (set at VM `:195`, `:211`, `:225`) is never read here, so **a failed toggle is completely silent**.

Sheets: `.sheet(item:)` → `YearbookItemDetailView(item:, listId: id ?? "", viewModel:)`; export → `ShareSheet(activityItems: [exportText])`.

`progressHeader` (`:97-132`) — wrapped in `if let list` with **no else** (vanishes when nil): "\(completed) of \(total) completed" `.headline`; "\(pct)% Complete" `.caption`; 60 pt progress ring (8 pt stroke, ladder colour, animated) with centre percentage; background `Color(.systemGray6)`.

`filterBar` (`:134-172`) — horizontal chips: All / Incomplete / Completed, divider, then category chips. **Bug: the three quick filters route through `clearFilters()` (VM `:299`, `:291-296`), which resets the category to "All" and wipes the typed search.**

`searchBar`: magnifier + `TextField("Search items...")` rounded-border + clear button; `Color(.systemGray6)` background.

`checklistContent`: sections by category, header `Text(category)` `.headline` + "\(completed)/\(count)" — **counts the *filtered* items, so under "Completed" every header reads N/N**. Rows `YearbookItemRow(item:, onToggle:, onTap:)`. **No swipe actions, no reordering, no context menu.**

`emptySearchResults` ("No items found" / "Try adjusting your search or filters" / "Clear Filters" `.bordered`) — **doubles as the genuinely-empty-list state**: a zero-item list shows search copy.

`FilterChip`: `.caption`, selected = `Color.blue` bg white text, else `systemGray5`, cornerRadius 15.

`ShareSheet` (`:297-305`): `UIActivityViewController` wrapper. **Declared here but also consumed by `Training/PhotoCritiqueDetailView.swift:61`** — do not delete or rename during the redesign.

### B.3 `YearbookItemRow` + `YearbookItemDetailView` (`YearbookItemRow.swift`)

Row (`:3-110`): checkbox Button (`checkmark.circle.fill` green / `circle` gray, `.title2`, animated); whole row `.contentShape` + tap → detail; long-press press-scale only (empty `perform`, `maximumDistance: .infinity`). Name `.body`, medium when required, strikethrough+secondary when completed. If required → red "REQUIRED" chip — **`required` defaults to `true` (`YearbookModels.swift:161`), so nearly every row carries the red tag: no hierarchy**. Optional description 2-line `.caption`. When completed: photographer `person.fill` + completion date `calendar`, `.caption2`. If imageNumbers non-empty → "\(count) images" `.blue` (**always plural**). `if item.notes != nil` → orange `note.text` badge — **tests nil, not emptiness**, so an empty-string note shows the badge. Trailing chevron. **New `DateFormatter` per row per body evaluation** (`:104-109`).

Detail sheet (`:113-298`) — own `NavigationView` + `Form`:
- "Item Details": read-only Name / Description / Category / Status (icon + Completed/Incomplete) / Priority (REQUIRED chip when required).
- "Completion Details" (completed only): Photographer / Date Completed / Session — **shows the raw session UUID; no lookup to a session name or date**.
- "Image Numbers": `TextField("Enter image numbers (comma separated)")` — no keyboard type, no validation.
- "Notes": `TextEditor` minHeight 100, no placeholder.
- Toggle button: "Mark as Complete" green / "Mark as Incomplete" red.
- Toolbar Cancel / Save (disabled while saving). `.onAppear` populates notes + joined image numbers.

**`toggleCompletion` (`:276-281`) discards unsaved notes/image edits without warning** and surfaces no error. **`saveChanges` (`:283-297`) fires two sequential full read-modify-write round-trips and dismisses unconditionally even on failure** — no error alert, no unsaved-changes confirmation. `item` is a `let` captured at open; notes/image writes do no optimistic update, so **saved values do not appear in the row until the whole screen is rebuilt**.

### B.4 Screen: `YearbookChecklistViewForSession` (`YearbookChecklistViewForSession.swift:4`)

Inputs schoolId, schoolName, **non-optional** `sessionContext`. Flow: loading → `noListsFound` → year selection (when several years) → child `YearbookChecklistView(shootList:, sessionContext:)` — **the only non-nil-context path in the app**. Toolbar leading "Close". Once the child renders, its nav title wins the same bar, so "Close" coexists with the school•year title.

`noListsFoundView`: `list.clipboard` 60 gray, "No Yearbook List Found", "No yearbook checklist exists for \(schoolName)", "Close" `.bordered`. **Shown for three different causes** — no org id (`:134`), zero years (`:149`), and any thrown network/decode error (`:179`): **a network failure is reported as "no checklist exists".**

`yearSelectionView`: "Select School Year" / "Multiple yearbook lists found for \(schoolName)"; per-year buttons with "(Current)" marker, chevron, `systemGray6` cornerRadius 10. **Not scrollable** — many years overflow off screen. **Unbounded spinner** if the initial fetch returns nil (`:31`) — no timeout, no error, no retry.

## 2. Device-conditional layout — NONE in either feature

Zero hits for `isIPad` / `horizontalSizeClass` / `userInterfaceIdiom` in both directories (the slate's `UIScreen` uses are brightness/orientation, not layout). **No second screen exists.** Container inconsistency to clean up: `AddClassGroupView.swift:139` forces `StackNavigationViewStyle()`; `EditClassGroupView` uses `NavigationStack` (`:201`); `CreateClassGroupJobView.swift:25` is a bare `NavigationView` with no style modifier, so the create sheet can render split on iPad while the add sheet cannot.

## 3. Dead / suspicious controls

### Class Groups

| Severity | file:line | Finding |
|---|---|---|
| **Empty function** | `ClassGroupJobDetailView.swift:160-162` | `refreshJob()` empty; both sheet completions call it, so their `success: Bool` does nothing |
| Empty closure | `ClassGroupJobDetailView.swift:51-53` | `onSlate: { }` passed for every row; the parameter exists only to be called and discarded |
| **Fake affordance** | `ClassGroupJobDetailView.swift:269` | `.contentShape(Rectangle())` with **no tap gesture** — the row reads tappable; editing requires the 36 pt pencil |
| **Silent failure** | `ClassGroupJobsListView.swift:114-115` | Job-delete failure only printed — no alert (row delete *does* alert) |
| **Silent failure** | `ClassGroupJobsListView.swift:90-92` | Missing org id → print only; screen shows the empty state as if there were no jobs |
| Nav hacks | `ClassGroupJobsListView.swift:64-66`, `139-141` | Two hard-coded 0.5 s `asyncAfter` deep-link delays |
| **Dead, recursive** | `ClassGroupSlateView.swift:108-115` | `fullScreenSlate()` = `fullScreenCover(isPresented: .constant(true)) { self }` — un-dismissable; zero call sites |
| Unused `@State` | `ClassGroupJobsListView.swift:7`; `ClassGroupSlateView.swift:9` | `organizationId` written never read; `orientation` written never read (its notification subscription is pure overhead) |
| **Silent data substitution** | `CreateClassGroupJobView.swift:133` | `session.startDate ?? Date()` stamps today's date on the job if the session has no day rows |
| Thread hazard | `CreateClassGroupJobView.swift:94-97`, `125-128` | `@State` mutated from the UserManager callback thread with no main hop |
| Ownership smell | `ClassGroupJobsListView.swift:4` + `:73` | Singleton held as `@StateObject` + `.onDisappear { stopListening() }` — any other holder loses realtime when this screen leaves |
| Copy bugs | `ClassGroupJobsListView.swift:208`, `:196-197` | "images" never singularized; `person.3` icon hard-coded for Clubs and Candids in rows |
| Global name | `ClassGroupJobsListView.swift:146` | `struct EmptyStateView` — unqualified global type |
| Duplication | `AddClassGroupView.swift:31-109` vs `:203-281` | Verbatim duplicate form bodies |
| **Never surfaced / never used** | `ClassGroupModels.swift:121`, `:261-279`; `ClassGroupJobService.swift:13`, `:61-84`, `:601-632` | `job.notes` never shown; `displayName`/`imageNumbersArray`/`hasClassGroups`/`shortGrades` unused; `@Published error` never read; `fetchClassGroupJob(forSession:)` and `exportToCSV` have **zero call sites — there is no export button in any Class Groups view** |
| Always-true clause | `ClassGroupJobService.swift:141` | `$0.schoolId != nil` on a non-optional |

No TODO/FIXME in the directory; no `?? UUID()` fallbacks (only legitimate init defaults).

### Yearbook

| Severity | file:line | Finding |
|---|---|---|
| **Dead control, visible** | `YearbookChecklistView.swift:266-268` + `:67-69` | "Mark All Required Complete" does nothing |
| **Dead control, visible** | `YearbookShootListsView.swift:36-39`, `:26`, `:70` | Create sheet is a placeholder Text. **No way to create a yearbook list from iOS at all** |
| **Filter clobber** | `YearbookChecklistView.swift:141/147/153` → VM `:299` | Quick filters call `clearFilters()`, wiping the active category and search text |
| **Errors never surfaced** | checklist + item screens | `viewModel.error` displayed only by the root list's alert; every failure on the checklist and detail screens is silent |
| **Error swallowed** | `YearbookChecklistViewForSession.swift:177-181` | catch prints and shows "No Yearbook List Found" |
| **Unbounded spinner** | `YearbookChecklistViewForSession.swift:31` | nil initial fetch → spins forever |
| **Lowercase-UUID hazard** | `ShiftDetailView.swift:265` → Service `:33`, `:77` | `schoolId` passed with no `.lowercased()`; every `id` comparison in the service lowercases, **`school_id` and `organization_id` never do** |
| **No org scoping on the subscription** | `YearbookShootListService.swift:365-366`, `:394` | `organizationId` param unused; realtime filter is `school_id` only |
| Unused `@State`/deps | `YearbookChecklistView.swift:9`; `YearbookItemRow.swift:122`; `YearbookShootListsView.swift:5,7` | `showingItemDetail`; `showingImagePicker` (no picker exists); `SchoolService` never read; `selectedSchool` unused |
| No-op filter case | VM `:308-310` | `QuickFilter.required` → `break` |
| Always-true / unreachable | `YearbookChecklistView.swift:26`, `:36`, `:39` | categories never empty; loading branch can't fire; unused `if let` binding |
| **Dead API surface** | VM `:277-287`, `:262-274`, `:233-259`, `:111-141`, `:160-172`; Service `:487-495`, `:161-206`, `:89-102`, `:536-545` | delete, copy, create, `loadShootListForSchool`, `loadActiveListsForOrganization`, `getActiveYearbookLists`, `clearAllCache` — **no callers anywhere** |
| Dead error cases | `YearbookModels.swift:284-290` | `.invalidSchoolYear`, `.permissionDenied`, `.networkError`, `.unknownError` never thrown |
| Off-actor writes | `YearbookChecklistViewForSession.swift:134,149,154,163,176` | `@Published`/`@State` written from a Task with no MainActor hop; `:154` assigns VM state from outside the VM |
| Perf | `YearbookItemRow.swift:104-109`, `:269-274`; `YearbookShootListsView.swift:206` | Formatters allocated per body evaluation |
| Duplicated logic | `YearbookShootListsView.swift:213-224` vs `YearbookChecklistView.swift:254-264` | Progress-colour ladder hardcoded twice |
| **No cross-screen invalidation** | — | Zero NotificationCenter posts/observers in the module; list counts stay stale until `.onAppear` refires |

Zero literal TODO/FIXME — the gaps are prose comments (`YearbookChecklistView.swift:267`, `YearbookShootListsView.swift:37`, VM `:309`, Service `:153`).

## 4. What the data layer actually carries

### Class Groups models (`ClassGroupModels.swift`)

**`ClassGroupJob`** (`:112`): id, session_id, session_date, school_id, school_name, organization_id, job_type, class_groups `[ClassGroup]`, notes?, created_at, updated_at, created_by, last_modified_by. `init` defaults `id = UUID().uuidString` — **uppercase, violating the repo's lowercase rule**. Computed: classGroupCount, totalImageCount, hasClassGroups (unused).

**`ClassGroup`** (`:216`): id, grade, teacher, image_numbers `String` (free-text comma list, **not an array**), notes. Computed: displayName (unused), hasImages, imageCount = naive split count, imageNumbersArray (unused).

**Row-shape reality (`:4-7`):** all three job types share the same four keys — **clubs store the club name in `grade` and the advisor in `teacher`**. `class_group_jobs` and these keys are a **shared contract with the web app**; raw `job_type` ids must not change.

**Limits:** a row carries **no photo, no roster, no student list, no time, no location, no assigned photographer** — grade, teacher, a comma list of image numbers, a note.

### Class Groups service (`ClassGroupJobService.swift`)

Singleton; tables `class_group_jobs`, `sessions`. All queries single-table except one embedded `sessions + session_days(*)` join in `getUpcomingSessions` (`:126-132`). Notables:
- `getUpcomingSessions` (`:87`): day-row query has **no organization_id filter** — pulls every org's day rows in range (`:109-115`); window now→+2 weeks hard-coded (`:90-91`); exclusion done client-side case-insensitively; clubs rely on the jobs table alone (legacy session flags cover only the other two types).
- `addClassGroup` / `updateClassGroup` / `deleteClassGroup` (`:247`, `:298`, `:351`): **whole-row read-modify-write on the `class_groups` JSON array, no concurrency guard** — two photographers adding rows concurrently silently lose one. Update matches `$0.id == classGroup.id` **case-sensitively**; a missed match **silently persists the unmodified array with no error** (`:316-318`).
- `updateSessionHasJob` (`:575`): maps classGroups/classCandids to session flags, **clubs return early** (D3); **errors swallowed with a print** — a job can exist while the session flag stays stale.
- `startListening` (`:432`): org-filtered realtime channel; **any change refetches the whole org list**.
- `exportToCSV` (`:601`): builds "Date,School,\(primary),\(secondary),Images,Notes" rows — **no caller**.

### Yearbook models (`YearbookModels.swift`)

**`YearbookShootList`** (`:4`): id, organization_id, school_id, school_name, school_year, start_date, end_date, is_active, copied_from_id?, completed_count (var), total_count, items `[YearbookItem]` (var), created_at, updated_at. **Items are a JSON array inside the list row, not a table.** Computed: completionPercentage (guards /0), isCompleted.

**`YearbookItem`** (`:118`): id, name, description?, category, required (default **true**), completed, completed_date?, completed_by_session?, photographer_id?, photographer_name?, image_numbers `[String]?`, notes?, order. `init` mints **uppercase** UUIDs (`copyYearbookShootList` writes them into the DB).

**Limits:** an item carries **no photo, no due date, no assignee (only a completer), no subtasks, no priority beyond `required`, no history**. `order` is the only sort key. `getCurrentSchoolYear`: month ≥ 8 → "Y-(Y+1)" else "(Y-1)-Y".

### Yearbook service + VM

One table (`yearbook_shoot_lists`), **no joins, no RPCs, no PowerSync**. Notables:
- `getYearbookShootList` (`:22`): **cache-first with NO expiry**; **no organization_id filter** (RLS-only). `getOrganizationYearbookLists` (`:51`) bypasses the cache and decodes the full items JSON for every school/year when the list screen needs only counts — so **the list screen and the checklist screen can disagree**.
- **Cache correctness — the module's most serious defect:** the cache is invalidated only by this device's own item write (`:298`), never by delete, never by a realtime event; the realtime callback's refetch **reads through the same stale cache** (`:375`, `:398-408`). The single-school path (the schedule entry) can serve indefinitely stale data. Cache persists list JSON into `UserDefaults` with no TTL (`:504-506`).
- `updateShootListItem` (`:211`): **whole-row RMW, stringly-typed `[String: Any]` updates with `NSNull` sentinels** — a typo'd key silently no-ops; last-write-wins; `completed_count` incremented ±1 from the stored value rather than recounted, **so it drifts permanently once out of sync**.
- `toggleItemCompletion` (`:304`): two reads + one write per checkbox tap; photographer name from UserDefaults falling back to the literal "Unknown".
- VM `toggleItemCompletion` (`:177-198`): "optimistic" update runs AFTER the await and re-toggles from the current local value rather than applying the server's value — counts can drift. `updateItemNotes` / `updateItemImageNumbers` (`:201-228`): **no local update at all — the UI never reflects the save**.
- VM `exportCompletedItems` (`:317-353`): **despite the name it exports ALL items and ignores every active filter and the search text.** Format: header, school-year, generated stamp, completion line, per-category "✓/○" items with "(by X on date)", notes, images.

## 6. Constraints the AMB.10 redesign must respect

- **Do not promise a create flow for yearbook lists** — none exists on iOS. Same for yearbook delete and copy (dead API surface).
- **Do not promise export for Class Groups** — `exportToCSV` has no button and no caller. Yearbook export exists and works but exports everything.
- **Do not promise photos or thumbnails anywhere** — neither model carries an image reference, only free-text/array image *numbers*.
- **Do not promise per-item assignment** — only completion attribution exists, yearbook-only.
- **Clubs share the class-group row shape** — a club-specific field set is a schema change against a shared web-app contract.
- **Some existing jobs carry today's date, not the session date** (`session.startDate ?? Date()` at create).
- **`ShareSheet` is used by Training** — moving it is a cross-feature change.
- **`EmptyStateView` is a global type** declared in `ClassGroupJobsListView.swift:146`.
- **The 2-week create window is server-side** — a date-range control needs a service change.
- **Both features are shell-nav** — new root screens stay bare containers using `.navigationTitle`/`.toolbar`. Exception: `YearbookChecklistViewForSession` is sheet-presented with its own `NavigationView` from the call site.
- **The drift gate's silence over these directories is a false negative** — allowlist rows appear/disappear as the conversion proceeds.


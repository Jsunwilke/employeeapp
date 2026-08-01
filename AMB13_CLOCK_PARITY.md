# AMB.13 — the time clock: capability inventory

The parity document for the arc's last phase, written before anything was
redesigned (D12: a surface's capabilities are inventoried FROM THE SOURCE, not
from the screen and not from memory, and every one is marked kept, moved, added
or open).

It is also the phase's scope statement, because the clock is the one surface in
the arc that was never in a batch and never got a mockup.

**Read alongside** `AMB_BATCH4_PARITY.md` §2.4, which surveyed this surface at
AMB.10 while building the drift gate's allowlist. That survey is the reason this
phase exists — it is where the clock was found to belong to no phase. Every one
of its 22 findings (K1–K22) is re-verified against the code as it stands TODAY in
§6 below, because two of them have already been fixed by AMB.12 and carrying a
stale finding forward is how a phase "fixes" something that is not broken.

---

## 1 The surface

Ten view files, 2,543 lines by `wc -l`, plus the two write paths the home
dashboard owns. Nothing here reads `FeatureTheme` — the feature's own colour
(`timeTracking` → `#12A594`, `DesignTokens.swift:51`) is unused by all ten, and
every colour on the surface is a hardcoded `.blue` / `.red` / `.green` /
`.orange` / `systemGray6`.

| File | Lines | Reached from | Kind |
|---|---|---|---|
| `TimeTrackingMainView.swift` | 317 | `MainEmployeeView.swift:988`, feature id `timeTracking` | the feature's root, shell-wrapped |
| `TimeEntryListView.swift` | 478 | embedded child, `TimeTrackingMainView.swift:24` | list + range picker + totals |
| `EditTimeEntryView.swift` | 484 | row tap, `TimeEntryListView.swift:226` | form, self-nav sheet |
| `ManualTimeEntryView.swift` | 278 | "Add", `TimeEntryListView.swift:220` | form, self-nav sheet |
| `SessionSelectionView.swift` | 228 | **three** sites (below) | clock-in sheet |
| `CustomClockOutView.swift` | 205 | long-shift alert only, `TimeTrackingMainView.swift:73` | form, self-nav sheet |
| `ActiveClockInEditView.swift` | 179 | "Edit Clock-In Time", `TimeTrackingMainView.swift:163` | form, self-nav sheet |
| `NotesInputView.swift` | 122 | `TimeTrackingMainView.swift:42`, `DashboardWidgets.swift:97` | clock-out sheet |
| `TimeEntryDetailView.swift` | 245 | **nothing — dead** | — |
| `TimeTrackingButton.swift` | 127 | **nothing — dead** (both structs) | — |

`SessionSelectionView`'s three call sites are `TimeTrackingMainView.swift:34`,
`DashboardWidgets.swift:80` (the home Hours widget) and
`TimeTrackingButton.swift:62` — and the third is dead, so **two live sites**.

### Clock affordances that live outside these files

Three, and two of them write payroll. They are named here because a redesign of
"the clock" that only touches the clock's own directory leaves the app's two
most-used clock buttons behind.

| Where | What it does | Owned by |
|---|---|---|
| Home **Hours widget** header capsule (`DashboardWidgets.swift:245-275`) | opens the clock-in sheet or the clock-out sheet — described in its own source as "the app's primary way in and out of a shift" | styled by AMB.4; its two write paths are AMB.13's |
| **All Features** toolbar button (`AllFeaturesView.swift:195-224`) | one tap clocks in or out with **no session and no notes** | styled by AMB.12; behaviour is AMB.13's |
| Bottom bar `.active` badge (`Navigation/BottomTabBar.swift`) | a green dot meaning "running" | AMB.4, display only |

---

## 2 Every capability, from source

`K` = kept as-is · `M` = moved (same capability, different place or shape) ·
`A` = added · `O` = open question for the operator.

### 2.1 The clock itself — `TimeTrackingMainView`

| # | Capability | Source | Verdict |
|---|---|---|---|
| 1 | Clocked-in / clocked-out status header, with "Currently Clocked In" / "Currently Clocked Out" / "Ready to start" | `:91-127` | **M** — becomes the hero card; the words survive |
| 2 | Live elapsed readout, `HH:MM:SS`, driven by the service's 1Hz timer | `:99`, `TimeTrackingService.swift:510-541` | **K** |
| 3 | "Since h:mm a" — when the running shift began | `:106` | **K** |
| 4 | Clock In button → session-selection sheet | `:187-203` | **K** |
| 5 | Clock Out button → notes sheet, via the long-shift check | `:133-160` | **K** |
| 6 | ⚠️ glyph inside the Clock Out button past 24h | `:144-152` | **M** — moves onto the hero card, where it is legible; see K16, it does not currently update on its own |
| 7 | "Long Shift Detected" alert with **Clock Out Now / Set Custom Time / Cancel** | `:69-79` | **K** — the only route to `CustomClockOutView` |
| 8 | "Edit Clock-In Time" button (running shifts only) | `:163-179` | **K** |
| 9 | Current-session block: session name or the literal "Session", plus notes, 2 lines | `:208-251` | **M** — folds into the hero card |
| 10 | Failure alert for clock in / clock out | `:80-86`, `:281-303` | **K** |

### 2.2 The entry list — `TimeEntryListView`

| # | Capability | Source | Verdict |
|---|---|---|---|
| 11 | Range picker: **Today / This Week / Pay Period**, default Pay Period | `:11-14`, `:169-175` | **K** |
| 12 | 14-day pay period computed from the hardcoded anchor **2/25/2024** | `:37-80` | **K** — same anchor `ManagerMileageView` uses; changing it is payroll, not design |
| 13 | Total hours for the range, formatted `Xh Ym` / `Xh` | `:85-144` | **K** |
| 14 | Entry count | `:115-125` | **K** |
| 15 | "(Pay Period)" suffix when that range is selected | `:100-104` | **K** |
| 16 | "Add" → manual entry sheet | `:155-165` | **K** |
| 17 | Row tap → edit sheet | `:200-202` | **K** |
| 18 | Row: date as **Today / Yesterday / MMM d** | `:440-460` | **K** |
| 19 | Row: duration, time range `h:mm a - h:mm a` or **"- Present"** | `:346`, `:462-470` | **K** |
| 20 | Row: three entry KINDS drawn differently — running (green, `play.circle.fill`, "• ACTIVE"), manual (`pencil.circle`), clock-based (`clock.circle`) | `:288-333` | **K** |
| 21 | Row: editable vs locked, as a `pencil` or a `lock` glyph | `:377-387` | **M** — becomes a badge with a word, not a bare glyph |
| 22 | Row: session name, or the literal "Session" | `:392-411` | **K** |
| 23 | Row: notes, one line | `:414-424` | **K** |
| 24 | Empty state "No time entries for \<range\>" | `:189-194` | **M** — split from the failure state, see §3 |
| 25 | Loading state | `:181-188` | **K** |
| 26 | Reload on range change and on sheet dismiss | `:216-232` | **K** |

### 2.3 Clocking in — `SessionSelectionView`

| # | Capability | Source | Verdict |
|---|---|---|---|
| 27 | Today's assigned sessions, sorted by start time | `:130-151` | **K** |
| 28 | Session row: school, position, start–end, multi-day label, location | `:154-221` | **K** |
| 29 | Single selection, and **selection is optional** — you may clock in with no session | `:80-89`, `:111` | **K** |
| 30 | Empty state: "No sessions assigned for today" + "You can still clock in without selecting a session" | `:55-71` | **M** — kept as the EMPTY state, no longer shown on failure (§3) |
| 31 | Notes field, optional | `:96-105` | **K** |
| 32 | Clock In button | `:107-126` | **M** — gains a disabled/in-flight state, see §4 |
| 33 | Cancel | `:42-46` | **K** |

### 2.4 Clocking out — `NotesInputView`

| # | Capability | Source | Verdict |
|---|---|---|---|
| 34 | "Clocking Out" / "Clocking In" header — the view is built for both, only clock-out is used | `:20-32` | **K** (both paths kept; only one is wired, as today) |
| 35 | Notes, 500-char cap with a counter that turns red above 450 | `:42-63` | **K** |
| 36 | Confirm button, "Processing…" while in flight | `:70-93` | **M** — see K10 in §6, the reset is a real bug |
| 37 | Cancel | `:95-105` | **K** |

### 2.5 The three edit forms

| # | Capability | Source | Verdict |
|---|---|---|---|
| 38 | `ActiveClockInEditView`: adjust a RUNNING shift's start, date + time | `:80-97` | **K** |
| 39 | …live preview — new clock-in, elapsed, original clock-in | `:99-125` | **K** |
| 40 | …48-hour window enforced client and server, with the reason shown | `:44-47`, `:127-132` | **K** |
| 41 | `ManualTimeEntryView`: fabricate a shift — date, start, end, duration readout | `:24-52` | **K** |
| 42 | …optional session picker, populated for the chosen date | `:54-73` | **K** |
| 43 | …notes with the 500 cap | `:76-93` | **K** |
| 44 | …validation banner naming the specific failure | `:95-101`, `:166-189` | **K** |
| 45 | `EditTimeEntryView`: edit start, end, session and notes on a past entry | `:82-174` | **K** |
| 46 | …read-only rendering when the 30-day window has passed | `:205-244` | **K** |
| 47 | …"Crosses midnight" note | `:118-123` | **K** |
| 48 | …Delete, behind "This action cannot be undone" | `:193-204`, `:263-270` | **K** — the surface's only confirmation |
| 49 | …clocked-in entries edit start + notes only, and say so | `:87`, `:94`, `:184-191` | **K** — and the sentence is rewritten, see K6 |

### 2.6 What the dead screens hold

| # | Capability | Source | Verdict |
|---|---|---|---|
| 50 | `TimeEntryDetailView`'s **explanation of the edit window** — "Editable (within 30-day window)" / "Read-only (outside edit window or system-generated)" | `TimeEntryDetailView.swift:36-44` | **M** — the ONLY copy in the app that tells a photographer why a row is locked. The screen dies; the sentence moves onto the locked row and into the edit form |
| 51 | `TimeEntryDetailView`'s entry-kind names — "Active Clock Entry" / "Manual Time Entry" / "Clock-based Entry" | `:186-194` | **M** — become the row badge's words, replacing bare glyphs (#20, #21) |
| 52 | `TimeEntryDetailView`'s technical block — entry id, org id, user id | `:120-151` | **DROPPED**, deliberately. It is a dead screen's debug panel; no photographer has ever seen it and nothing links to it |
| 53 | `TimeTrackingButton` / `TimeTrackingFloatingButton` | whole file | **DROPPED** — dead, and the floating variant hardcodes a `padding(.bottom, 100)` that predates the AMB.4 tab bar |

---

## 3 A failure is not an empty state

The single biggest defect on this surface, and it is a DRAWING defect, which is
what makes it this phase's rather than a service arc's.

Two payroll screens catch a fetch error and render the empty state:

- `SessionSelectionView.swift:145-149` → the catch sets `isLoading = false` and
  nothing else, so a failed session fetch draws **"No sessions assigned for
  today / You can still clock in without selecting a session"** — an invitation
  to clock in unattributed, on a day where sessions probably do exist.
- `TimeEntryListView.swift:258-264` → same shape, so a failed load draws **"No
  time entries for pay period"**, and the "Total Hours" figure above it reads
  **0h**. Payroll appearing to be zero because a request timed out.

`AmbientFailureCard` exists for exactly this (`AmbientControls.swift:232`) and
was promoted in AMB.12 with these two screens named in its own doc comment. Both
get it, both get Retry.

**A** — a distinct failure state on both screens, with a retry.

---

## 4 The seven write paths and the one confirmation

Verified against `TimeTrackingService.swift` and `Models.swift:670-750` today.

| Path | Write | Client validation | Server validation | Confirmation | In-flight guard |
|---|---|---|---|---|---|
| `SessionSelectionView` | INSERT clock-in | notes ≤500 | already-clocked-in check | none | **none** — button never disables |
| `NotesInputView` | UPDATE end/total/status | — | re-entrancy + zero-row guard | none | `isProcessing`, **never reset on failure** |
| `CustomClockOutView` | UPDATE end with a chosen timestamp | >start, ≤24h, not future | same three, + zero-row | none | **none** — stays live during the call |
| `ActiveClockInEditView` | UPDATE start on a LIVE shift | not future, ≤48h back | same, + zero-row | none | none |
| `ManualTimeEntryView` | INSERT a fabricated shift | >start, ≥1min, **≤16h**, not future | same + **overlap detection** | none | none |
| `EditTimeEntryView` Save | UPDATE start/end/session/notes | 30-day, **≤24h** | 30-day, ownership, **≤16h**, overlap | none | none |
| `EditTimeEntryView` Delete | DELETE | 30-day | 30-day, ownership, zero-row | **yes** | none |
| *(All Features toolbar)* | INSERT or UPDATE, no session, no notes | — | server only | none | none |

**The data layer is sound and is not being touched.** Every UPDATE and DELETE
appends `.select("id")` and runs `requireRowsWritten`
(`TimeTrackingService.swift:44-48`), which throws on a zero-row match — the
documented fix for PostgREST answering 200 to a write that matched nothing. Case
is deliberately never folded on `time_entries.id`. That is all correct and stays.

**A** — an in-flight guard on every one of the seven, drawn rather than implied,
via `AmbientActionButton(isLoading:)` which disables and spins in one place. This
is presentation: the button is what fails to say "working", and
`AmbientActionButton` was built in AMB.12 precisely because "buttons across
Settings and the manager tools were never disabled and validated only AFTER the
tap".

**O — ONE OPERATOR QUESTION.** Should a **destructive-or-irreversible payroll
write get a confirmation** beyond Delete? The candidates are the two that change
a shift that already exists rather than recording one you just worked: editing a
LIVE shift's start time (`ActiveClockInEditView`, whose own copy admits it "will
update your total hours"), and setting a custom clock-out time hours after the
fact. Recommendation: **yes, a one-line summary confirmation on those two only**
("Change start to 6:42 AM? Today's total becomes 7h 18m."), and no confirmation
on ordinary clock in / clock out, which people do several times a day and would
come to tap through blind. Not decided here — it changes what Jason sees.

---

## 5 The ceiling conflict (K7) — verified, and it is real

- `ManualTimeEntryView.swift:151` — client cap **16h**.
- `Models.swift:706` (`validateManualEntry`) — server-side cap **16h**.
- `EditTimeEntryView.swift:289`, `:318` — client cap **24h**.
- `EditTimeEntryView` Save → `TimeTrackingService.updateTimeEntry` →
  `validateManualEntry` → **16h**.

So an edit of, say, 17 hours passes the form (the duration renders blue, Save
enables), and throws on Save with "Time entry cannot exceed 16 hours". The form
is lying about what it will accept.

**Fix is presentational and stays inside the phase:** the form adopts the ceiling
the write path actually enforces, so the ceiling is stated once. `CustomClockOut`
keeps 24h — it is a different write path (`clockOutManual`) with its own 24h rule
in `TimeTrackingService.swift:366-430`, and that one agrees end to end. Both
ceilings move into `TimeClockRules.swift` so there is nothing left to disagree.

---

## 6 The batch-4 findings, re-verified today

Two are already fixed. That is why this section exists.

| # | Status today | Note |
|---|---|---|
| K1 `TimeEntryDetailView` dead | **CONFIRMED** | zero call sites; #50–52 above |
| K2 `TimeTrackingButton` dead | **CONFIRMED** | zero call sites; holds 2 drift-gate cards |
| K3 fetch error as empty state (sessions) | **CONFIRMED** | §3 |
| K4 fetch error as empty state (entries) | **CONFIRMED** | §3 |
| K5 `AllFeaturesView` timer leak | **FIXED BY AMB.12** | now a structured `runElapsedClock()` loop inside `.task` (`:302-320`) — do not "fix" again |
| K6 typo "while clocked-in**ly clocked in**" | **CONFIRMED** | `EditTimeEntryView.swift:187`, shipped copy |
| K7 16h/24h ceiling conflict | **CONFIRMED** | §5 |
| K8 empty completion handler | **CONFIRMED** | `TimeTrackingMainView.swift:55-57` |
| K9 `debugTimeEntryQuery()` empty body, live call site | **CONFIRMED** | `TimeTrackingService.swift:613-616` is an empty function; awaited on every empty result at `TimeEntryListView.swift:251` |
| K10 `isProcessing` never reset | **CONFIRMED** | `NotesInputView.swift:70-93` — a failed clock-out wedges the button at "Processing…" permanently, with no error shown in the sheet |
| K11 unused declarations | **CONFIRMED** | `TimeEntryRow.dateFormatter`; `ManualTimeEntryView.swift:139` `let calendar` |
| K12 dead auto-correct + dead `onAppear` | **CONFIRMED** | `EditTimeEntryView.swift:258-261` reads `availableSessions` before it is loaded |
| K13 silent print-only session-load failures | **CONFIRMED** | picker just never appears |
| K14 per-body formatter allocation, 8 files | **CONFIRMED** | none use `Formatters` (`DesignTokens.swift:88-140`), which exists for this |
| K15 three 1Hz timers | **PARTIALLY FIXED** | `AllFeaturesView`'s is now a cancellable loop; the service's (`:512`) and `DashboardWidgets`' (`:283`) remain, and both are legitimate owners |
| K16 frozen "live" values | **CONFIRMED** | `ActiveClockInEditView.swift:49-52` and the >24h glyph at `TimeTrackingMainView.swift:146-151` read `Date()` in a computed body with nothing driving a redraw |
| K17 sheets that render empty | **CONFIRMED** | `TimeTrackingMainView.swift:49-68`, `if let` with no `else` |
| K18 debug prints on payroll paths | **CONFIRMED** | `TimeEntryListView.swift:236-260`, `SessionSelectionView.swift:109-110` |
| K19 `CustomClockOutView` notes uncapped | **CONFIRMED** | the only one of five without the 500 cap and counter |
| K20 manual date picker unbounded | **CONFIRMED** | `:26`, a future date is selectable and rejected only after Save |
| K21 `CustomClockOutView` defaults to `Date()` | **CONFIRMED** | rather than deriving from `clockInTime` |
| K22 first load behind a 0.5s delay | **CONFIRMED** | `TimeEntryListView.swift:210-215`, a race papered over |

Also confirmed and **not** on that list: the two HoursWidget catch blocks that
swallow a payroll failure with a bare comment (`DashboardWidgets.swift:90`,
`:107`) — on the path the source itself calls the app's primary one.

---

## 7 Explicitly out of scope

Named so that nothing here is quietly assumed to have been handled.

- **`getTimeEntries` caps at 100 rows** with no pagination and no indication
  (`TimeTrackingService.swift:591`). A 14-day period with more than 100 entries
  silently truncates AND the Total Hours figure is then wrong. That is a data
  bug with a payroll consequence and it needs its own phase — a design phase
  must not invent pagination. **Recorded, not fixed.**
- **`getCurrentTimeEntry` uses `.limit(1)` with no ordering** (`:544-556`) — with
  two stray `clocked-in` rows, which one is "current" is undefined.
- **Offline is asymmetric.** `clockIn`/`clockOut` queue to `TimeClockOutbox` and
  replay FIFO; the other five write paths have no offline route and throw. A
  queued clock-out whose row no longer exists is logged and dropped on purpose
  (`:212-218`) to avoid wedging the queue — a silently lost clock-out. This is
  the OFF arc's territory.
- **Cross-midnight is impossible in manual entry** — `createDateTime`
  (`ManualTimeEntryView.swift:160-164`) forces both start and end onto
  `selectedDate`, so an overnight shift fails as "End time must be after start
  time". Fixing it means giving the form a second date field, which is a
  capability the form does not have today. **O — worth asking**, but the
  recommendation is to leave it: `EditTimeEntryView` already supports
  cross-midnight with two date pickers, so the route exists.
- **`TimeEntry.total_hours` is never set by the camelCase initializer**
  (`Models.swift:635`), so offline-constructed entries carry a nil total.
- **`TimeEntry.taskId`** is in the model and written by nothing.
- Data layers, services, PowerSync and RLS, per D12.

---

## 8 Acceptance

The phase is done when, on iPhone AND iPad, light AND dark:

1. Every numbered capability in §2 marked K or M is present.
2. A failed fetch on either payroll screen says so and offers Retry (§3).
3. No write path can be double-fired by a second tap (§4).
4. The edit form's ceiling equals the ceiling the write actually enforces (§5).
5. Every CONFIRMED finding in §6 is fixed or carries a written reason.
6. `scripts/check_card_drift.py` reports **zero** rows for AMB.13.
7. `scripts/test_timeclock_rules.sh` passes.
8. The built screens were diffed back against the approved mockup (workflow 3b).

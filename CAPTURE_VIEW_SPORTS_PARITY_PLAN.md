# Capture View — Sports Feature Parity Plan

Date: 2026-04-22
Scope: extend the capture view (PoserStationView.swift) so it has feature parity with FP Sports view (FPSportsRosterView_iPad.swift) for sports shoot types. Items 2 and 8 from the original gap analysis are dropped — Item 2 was already solved by today's teacher dropdown work, and Item 8 turned out to be stale dead-code in FP Sports (not an actual feature).

This plan is research output, not an implementation. A new conversation will work from this plan.

---

## Constraints reaffirmed

- Do NOT touch SportsShootDetailView (Captura legacy view). Other photographers in Jason's studio still use it daily.
- Do NOT touch FPSportsRosterView_iPad except to extract shared helpers when truly safe — that view is itself slated for retirement, but it is NOT being deleted in this work.
- The capture view (PoserStationView) is the consolidation target. All net-new sports UI lives there.
- The FP local sync wire protocol (FocalPointSyncClient) and the local SQLite schema are NOT changed by this plan. All work is at the view + viewmodel layer.

---

## Item 1 — Inline image-number editing on each row

### Goal
Tap the image-numbers cell on a row, type, focus-loss saves. No detail-panel hop required for the most-frequent edit on a sports shoot.

### Where it lives in FP Sports
- ViewModel state: FPSportsRosterView_iPad.swift line 46 to 48 — three @Published fields, currentlyEditingEntry (UUID?), editingImageNumber (String), originalImageNumber (String — the value when editing started, used by the save guard to ignore false dirty-checks from PowerSync watch merges).
- Per-row rendering: line 3849 area — when isCurrentlyEditing is true, show AutosaveTextField instead of the static label.
- Save trigger: AutosaveTextField onTapOutside calls saveCurrentEditingEntry (line 5150).
- Capture-driven update of an editing row: line 668 to 669 — when an inbound capture for the currently-edited entry arrives, the editing buffer (editingImageNumber) is also updated so the user sees the live append.
- Lock-loss handling: line 1465 — when a lock-lost event arrives for the row being edited, decide based on hasChanges whether to save or discard.

### What capture view needs
- Three new @State fields on PoserStationView: currentlyEditingEntry (UUID?), editingImageNumber (String), originalImageNumber (String).
- Per-row rendering change in subjectRow: when subject.id matches currentlyEditingEntry AND isSports, replace the row's right-side trailing area with an AutosaveTextField bound to editingImageNumber. Single line, 120pt wide, blue 0.25 background — match FP Sports visual.
- New method saveCurrentEditingEntry that mirrors FP Sports' impl: short-circuit if editingImageNumber == originalImageNumber, write to subjects[idx].imageNumbers, call saveSubject (the existing path that handles PowerSync write + WS broadcast + the audit-fix per-subject debounce).
- Tap handler on the cell to enter edit mode: set currentlyEditingEntry, copy current value into editingImageNumber + originalImageNumber.
- Capture-completion auto-fill update: when onCaptureCompleted appends an image number to a subject that is currently being edited, also update editingImageNumber so the user sees the new number appear in the field they are typing into.
- Move-to-next behaviors: AutosaveTextField onEnterOrDown / onEnterOrUp handlers exist; the capture view does not currently have moveToNextEditableEntry / moveToPreviousEditableEntry — port these from FPSportsRosterView_iPad lines 4140 area for keyboard navigation between rows.

### Dependencies
- AutosaveTextField (existing, unchanged).
- KeyboardManager (existing, unchanged).
- LockManager — Item 4 should land before this so the inline editor properly acquires/releases locks like FP Sports does. If Item 1 lands first, ship it without locks and let Item 4 retrofit them.
- The per-subject capture-save debounce that landed today (pendingCaptureSaves) should be reused — saveCurrentEditingEntry calls saveSubject which already has the debounce.

### Scope
~100 lines added in PoserStationView.swift. No new files. No protocol changes.

### Risk
Medium. The editing state interacts with capture-driven updates and with the detail panel's existing draft state. Have to make sure they do not stomp each other — e.g., if the user is inline-editing image # for subject A and the detail panel is showing subject B, both must work independently.

### Test plan
- Open a sports gallery in capture view.
- Tap the image # cell on a row that has photos. Confirm field becomes editable in place.
- Type a number, tap elsewhere. Confirm it saves and the row reflects the new value.
- Start a capture (real or simulated) for the row being edited. Confirm the new image # appears in the field without losing focus or what the user is typing.
- Tap a different row's image # cell. Confirm focus moves and the previous row saves.
- Open the detail panel for a different subject while editing inline. Confirm both work.

---

## Item 3 — Group photo support

### Goal
Sports shoots produce two kinds of photos — individual subject photos and team / group photos (Football Team, Cheer Squad, etc.). FP Sports has a separate "Groups" tab for group photos. The capture view has no concept of groups today.

### Where it lives in FP Sports
- ViewModel state: line 23 — groupImages (array of GroupImage).
- ViewModel state: line 28, 31 — showingAddGroupImage (Bool), selectedGroupImage (GroupImage?).
- Tab selector to switch between Roster and Groups: line 2400 area uses a viewModel.selectedTab Int with a NavigationStack.
- Groups list rendering: line 3998 — groupImagesListView shows each group with the same kind of row treatment as subjects, plus a "+" button to add a new group.
- AddGroupImageView sheet: presented at line 2688, lets the user pick a group name (auto-suggesting unique sport values) and capture image numbers for that group.
- Data layer: PowerSyncManager.getGroupImages(forJob:) and watchGroupImages(forJob:) — already exist as the canonical way to read group images.
- Service: GroupImageService.shared.releaseExpiredLocks(forJob:) called on appear and on shoot change.
- WS callback: fpSync.onGroupPhotoReady (line 816) and onGroupCaptureCompleted are wired to update group photo state when the Mac broadcasts group capture events.

### What capture view needs
- Add a tab selector at the top of the capture view body (visible only when isSports) — "Roster" and "Groups" tabs. Use a Picker(selection: $selectedTab, .segmented).
- New @State on PoserStationView: groupImages [GroupImage], showingAddGroupImage Bool, selectedGroupImage GroupImage?, selectedTab Int.
- New view groupsList — renders viewModel.groupImages as a vertically scrolling list, each row showing groupName, image count, and the auto-fill image numbers (similar visual to subject row but no name/teacher badges).
- Wire fpSync.onGroupPhotoReady — when the Surface broadcasts a group photo capture, append the image number to the matching group's imageNumbers field, save (debounced).
- Wire fpSync.onGroupCaptureCompleted — same as onCaptureCompleted but for groups.
- Sheet presentation for AddGroupImageView (existing) when showingAddGroupImage flips true.
- Data load on appear: powerSync.getGroupImages(forJob: galleryId) — populate groupImages array.
- Watch: in startWatching, also subscribe to powerSync.watchGroupImages(forJob:).
- Release expired locks on appear: GroupImageService.shared.releaseExpiredLocks(forJob: galleryId).

### Dependencies
- GroupImage model (existing, unchanged — see SportsShootModel.swift).
- AddGroupImageView (existing — verify it works without FP Sports view present).
- GroupImageService (existing).
- PowerSyncManager.getGroupImages / watchGroupImages (existing).
- FocalPointSyncClient.onGroupPhotoReady / onGroupCaptureCompleted (existing).

### Scope
~250 lines added in PoserStationView.swift. No new files. The data layer and service layer already exist — this is wiring the capture view UI on top of them.

### Risk
Medium-high. Two concerns. First, the existing GroupImage workflow assumes the FP Sports view is the orchestrator — verify nothing in GroupImageService or AddGroupImageView assumes specific FPSports state. Second, the WS callbacks (onGroupPhotoReady etc.) are currently set in FP Sports; if the user opens the capture view and then later opens FP Sports, the capture view's callback gets overwritten — needs lifecycle care.

### Test plan
- Open a sports gallery in capture view. Tap "Groups" tab. Confirm empty state ("Add your first group").
- Tap "+" to add a group. Pick or type a group name (e.g., Football Team). Save.
- Confirm the group appears in the list.
- From the Mac, broadcast a group capture for that group name. Confirm the image number appears on the group's row.
- Tap a group to open its edit view. Confirm image numbers can be manually edited and saved.

---

## Item 4 — Lock manager wiring (concurrent-edit prevention)

### Goal
When two devices have the same subject's detail panel open and both type, prevent the second device from editing — show "being edited by Jason on iPad" instead. Mirrors FP Sports behavior.

### Where it lives in FP Sports
- @ObservedObject lockManager = LockManager.shared at line 235.
- ViewModel.lockedEntries dictionary [UUID : String] (entryId : editorName) at line 49 — populated from the LockManager subscription.
- isOwnLock helper at line 1268 — compares stored locker against currentEditorIdentifier (which comes from LockManager.shared.currentEditorIdentifier, line 201).
- Initialize on appear: LockManager.shared.setCurrentUser(...) at line 1365.
- Acquire on edit start: at line 5151 area in saveCurrentEditingEntry context, the inline editor calls acquire before allowing input.
- Release: line 2525 — releaseSubjectLock(subjectId:) when the editing finishes or focus is lost.
- Lock-lost handler: .onChange(of: lockManager.lockLostEvent?.id) at line 1451 — when this device's lock is forcibly released by another, decide whether to save or discard the in-flight edit based on hasChanges.
- Network reconnect handling: line 1399 — await LockManager.shared.handleNetworkReconnection() to resync locks after coming back online.

### What capture view needs
- Add @ObservedObject private var lockManager = LockManager.shared on PoserStationView.
- Add @State private var lockedEntries: [UUID: String] = [:].
- Initialize on appear: LockManager.shared.setCurrentUser(...) using the user's identity.
- In SubjectDetailPanel: when focusedField changes from nil to a non-nil value (panel gains focus on any field), call await LockManager.shared.acquireSubjectLock(subjectId: subject.id). If it returns false, surface a non-blocking banner and dismiss the keyboard.
- On focus-out (focusedField goes nil) and onDisappear and onChange of subject.id, call LockManager.shared.releaseSubjectLock(subjectId: previousSubjectId).
- Subject row: when lockedEntries[subject.id] is non-nil and not own lock, show a small lock badge with the editor name in the row (similar to ABSENT badge).
- Wire the lockLostEvent observer: if the panel is open for the lost subject and there's a draft, save it; either way clear the draft and show a toast.

### Dependencies
- LockManager (existing).
- The existing user-identity infrastructure (UserManager.shared.getCurrentUserIDUnified etc.).

### Scope
~80 lines added in PoserStationView.swift. No new files.

### Risk
Medium. Lock acquisition is async — any focus path that doesn't await will race. Lock release on app suspend (scenePhase transition) needs to be quick — iOS gives the app limited time before suspension, so use Task with a strict deadline.

### Test plan
- Two iPads on the same network. Open the same subject's detail panel on both.
- Confirm the second iPad sees the "being edited by [first iPad's user]" banner and cannot type.
- First iPad closes the panel. Second iPad's banner disappears within a second.
- Force-quit the first iPad mid-edit. Second iPad sees the lock release after the lock TTL (LockManager handles this).

---

## Item 5 — Inline teacher dropdown on the row

### Goal
Set the teacher code (None / Coach / Senior / 8th Grader) directly from the row, without opening the detail panel. Quick triage during a shoot.

### Where it lives in FP Sports
- specialDropdown at line 1076 — Menu with four buttons that call updateSpecial.
- updateSpecial at line 1140 — writes the code to subject.teacher and saves with retry.
- specialColor at line 1149 — the per-code color (we already ported this as sportsTeacherBadgeColor).
- specialLabel at line 1158 — the per-code label (we already ported this as decodeSportsTeacherCodeShort).
- Row rendering: line 3809 calls specialDropdown(entry:) twice (different layout positions for landscape vs portrait).

### What capture view needs
- Tap-to-cycle behavior on the existing teacher badge: tap the top-right teacher badge → present a Menu with None / Coach / Senior / 8th Grader → selection writes the code and saves.
- OR put a separate Menu trigger somewhere on the row — but tapping the badge itself is more intuitive (less new UI).
- Should NOT conflict with the row's existing onTapGesture that selects the subject — the badge tap needs its own Button that doesn't propagate.

### Dependencies
- The existing SportsCodes.swift helpers (already shipped today).
- The existing saveSubject path (handles PowerSync + broadcast).

### Scope
~30 lines added in PoserStationView.swift.

### Risk
Low. UI-only change, reuses existing data path.

### Test plan
- Tap the teacher badge on a sports row. Confirm a menu appears with the four options.
- Pick Senior. Confirm the badge updates immediately to brown SENIOR.
- Confirm the Surface receives the change (subject_updated WS message).
- Confirm the detail panel teacher picker reflects the change next time it opens.

---

## Item 6 — Multipeer iPad-to-iPad sync (REVISED SCOPE)

### Important research finding
The MultipeerRosterSync in FP Sports is NOT general iPad-to-iPad roster sync. It is specifically for KIOSK sync — pushing roster updates from the FP Sports "shooting" iPad to a SECOND iPad running the registration kiosk view. The comment at FPSportsRosterView_iPad.swift line 54 reads "Multipeer connectivity for kiosk sync."

The capture view does not currently launch a kiosk sub-view, so this feature has no analog. It's not "missing" from the capture view — it's irrelevant unless and until the capture view ALSO gains kiosk-launching ability.

### Recommendation
Defer indefinitely. If the capture view later gets a kiosk mode, then port MultipeerRosterSync along with it. Otherwise no work needed.

### If kiosk mode is added later
- New KioskLaunchView entry point from the capture view (button in the toolbar similar to FP Sports').
- Wire MultipeerRosterSync as in FPSportsRosterView_iPad lines 365 to 470.
- Connection-details sheet (line 353) ported.

### Scope
N/A — defer.

---

## Item 7 — Image-state filter

### Goal
Quick-filter chips for "all / has-photos / no-photos" so the operator can triage who they have not shot yet, late in a sports shoot.

### Where it lives in FP Sports
- ImageFilterType enum at line 135 with three cases — all, hasImages, noImages.
- @Published imageFilterType on viewModel at line 62, default .all.
- Filter logic in filterRoster at line 1332 — switch on imageFilterType, filter by entry.imageNumbers.isEmpty.
- UI: ImageFilterButton at line 3082 — two chip buttons (one for hasImages, one for noImages) in the FilterPanelView.
- Active-filter indicator at line 2326 area — shows "1 With photos" or "1 Without photos" pill near the search bar when active.

### What capture view needs
- Add an ImageFilterType enum (or reuse FP Sports' if accessible — likely better to make a shared one in a small new file or reuse via making it nested-public).
- Add @State private var imageFilterType: ImageFilterType = .all on PoserStationView.
- Apply in filteredSubjects (line 199 area) before sort — switch on imageFilterType, filter by isPhotographed and / or photoCountMap.
- Add two chips next to the existing Filter / Sort buttons in the toolbar (line 644 area): "Has Photos" and "No Photos." Tapping toggles between .all and the chosen state.

### Dependencies
- None new. Uses existing isPhotographed bool and photoCountMap.

### Scope
~50 lines added in PoserStationView.swift.

### Risk
Low.

### Test plan
- Tap "Has Photos" chip. Confirm only photographed subjects show.
- Tap "No Photos." Confirm only un-photographed show.
- Tap the chip again to clear. Confirm all subjects show.
- Take a photo. Confirm the subject appears in or disappears from the filtered list immediately.

---

## Item 8 — Conflict handling UI (DROPPED)

### Important research finding
FPSportsRosterView_iPad.setupConflictHandling at line 2972 is dead code. Read the implementation: it registers a NotificationCenter observer for "SyncConflictsDetected", but the handler immediately bails with "guard false else { return }". The comment above says "PowerSync handles conflicts automatically with last-write-wins strategy. This notification handler is kept for backwards compatibility but won't be triggered."

The ConflictResolutionView referenced inside is unreachable.

### Recommendation
Drop entirely. The capture view already has the same last-write-wins behavior via PowerSync. There is no actual conflict UI to port.

### If we ever want a real conflict UI
That would be a separate, larger project — surfacing PowerSync's CRDT resolution outcomes to the user requires hooking into PowerSync's internal conflict callbacks (not a NotificationCenter event), and there's no existing UI for it in either view. Out of scope.

---

## Implementation order recommendation

The user has flagged 1, 3, 4, 5, 6, 7, 8 as the items they care about. After research:

- 8 dropped (dead code).
- 6 deferred (only relevant if kiosk mode is added).
- 5 actually-needed items remain: 1, 3, 4, 5, 7.

Suggested order, lowest risk to highest:

1. Item 5 (inline teacher dropdown) — smallest scope, lowest risk, immediately useful.
2. Item 7 (image-state filter) — small, low risk, immediately useful late in a shoot.
3. Item 4 (lock manager) — medium scope, infrastructure for Item 1.
4. Item 1 (inline image # editing) — medium scope, depends on Item 4 being safe to use.
5. Item 3 (group photo support) — largest scope, most surface area, do last.

Total estimated work: 2-3 focused days for items 5, 7, 4, 1; another 1-2 days for item 3. Each item is independently shippable — pick the one with the most leverage for the next shoot.

---

## Files this plan touches

- /Users/jsunwilke/Desktop/employeeapp/Iconik Employee/Sports Shoot Feature/PoserStationView.swift (primary)
- Possibly a new small shared file for ImageFilterType if making it public-shared (vs nested).
- NO touches to FPSportsRosterView_iPad.swift, SportsShootDetailView.swift, or any service / data layer file.

## Files that already provide what we need (no changes)

- LockManager.swift — used as-is.
- GroupImageService.swift — used as-is.
- PowerSyncManager.swift — getGroupImages and watchGroupImages already exist.
- FocalPointSyncClient.swift — onGroupPhotoReady, onGroupCaptureCompleted already exist.
- AutosaveTextField.swift — used as-is for inline editing.
- SportsCodes.swift (created today) — provides the decoder and color helpers Items 1 and 5 will use.
- ImageNumberFormatting.swift (created today) — parseImageNumberRanges and formatImageNumberRanges Items 1 and 3 will use.

---

## Memory rules cited in this plan

- ~/Brain/rules/research-before-porting.md — every item lists FP Sports references with file:line numbers.
- ~/Brain/rules/trace-impact-before-changing.md — Item 6's revised scope came directly from grepping callers.
- feedback_dont_touch_captura_roster.md — SportsShootDetailView is explicitly out of scope.
- ~/Brain/rules/correctness-over-speed.md — no MVP framing; each item's scope is "what does FP Sports actually do" not "what's the minimum we can ship."
- ~/Brain/rules/plan-readability.md — this plan contains zero backticks per the rule.

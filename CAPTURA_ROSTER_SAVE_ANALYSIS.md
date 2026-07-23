# Captura Roster Save Analysis — Image Number Loss + iPad/iPhone Drift Map

Date: 2026-07-23. Read-only analysis; no protected files were modified.
Files renamed 2026-07-23: SportsShootListView.swift is now CapturaSportsView.swift,
SportsShootDetailView.swift is now CapturaSportsRosterView_iPhone.swift.

## The view map (verified from routing code)

- CapturaSportsView.swift — Sports tab entry point on both devices. iPhone: shoot list
  only, pushes the iPhone editor. iPad: the full roster workspace with image-number
  editing (image box around line 3087). This is the iPad view where numbers vanish.
- CapturaSportsRosterView_iPhone.swift — iPhone-only roster editor (image box around
  line 1492). Never shown on iPad. This is the iPhone view where numbers vanish.
- FPSportsRosterView_iPad.swift — Focal Sports iPad workspace. Different save path
  entirely (subjects table via SubjectSyncService), which is why it is unaffected.
  Note: its iPhone fallback branch pushes CapturaSportsRosterView_iPhone, so the
  FP-unaffected observation applies to iPad only.

## FINDING: a concrete iPad loss mechanism that survives the timestamp guard

Analytical result, not yet reproduced on device. Confidence: high — every step is
verified in current code; the runtime sequence itself is what needs confirmation.

The three interacting pieces (all in CapturaSportsView.swift):

1. Watch-stream protection clause (around line 4069): while entry A is being edited,
   every watch emission copies the live typed text into the in-memory array —
   merged[A].imageNumbers = viewModel.editingImageNumber — WITHOUT bumping updatedAt.
   The array now claims A already has the typed value, timestamped as old data.

2. Save guard (around line 4257): saveCurrentEditingEntry returns WITHOUT saving when
   viewModel.editingImageNumber equals the array entry's imageNumbers. After step 1
   poisoned the array, the typed value and the array value are equal, so the save is
   silently skipped. Nothing reaches SQLite or the server.

3. Emission metronome: the entry locks are columns on roster_entries rows
   (locked_by, locked_by_name via RosterEntryService), and LockManager refreshes the
   lock every 30 seconds while editing. So the row being edited is rewritten
   server-side at least twice a minute, each rewrite syncs back through PowerSync and
   fires a watch emission. On multi-photographer shoots, other devices add more
   emissions. Emissions during editing are the norm, not the exception.

Failure sequence:

- Photographer taps athlete A, types 123. Array A still holds the old value.
- Any watch emission arrives (lock heartbeat, another device, any roster write).
  The protection clause writes 123 into array A with the OLD updatedAt.
- Photographer taps athlete B. startEditing calls saveCurrentEditingEntry for A.
  The guard compares 123 (typed) with 123 (poisoned array) — equal — save skipped.
- Editing protection now covers B only. The next emission delivers SQLite truth for A
  (the old value, typically empty). The timestamp guard does not protect A because the
  poisoned array entry kept the old updatedAt. Array A reverts. The number is gone.

Why it is intermittent: loss requires an emission to arrive AFTER the final digit is
typed and BEFORE the tap on the next athlete. Fast typists who tap immediately rarely
lose; anyone who pauses after typing (looking up at the subject, camera adjustments)
is exposed on every entry, and the 30-second heartbeat guarantees periodic exposure.

Why the diagnostics log confirms this pattern: RosterEditDiagnostics logs at
PowerSyncManager.saveRosterEntry and the connector upload. In this mechanism the save
is never called at all, so the signature in roster_debug.log is the ABSENCE of any
save event for that entry near the loss time — not a save with an empty value.

## Why the iPhone view is (now) protected against this same mechanism

CapturaSportsRosterView_iPhone has the same array-poisoning clause in its watch merge
(around line 2046), BUT its stopEditing (around line 2185) saves UNCONDITIONALLY when
switching entries — the comment there says: ALWAYS save if there is a value, prevents
data loss when switching fields quickly. That unconditional save is exactly the patch
the iPad view is missing. The iPad guard was presumably written to avoid pointless
writes and nobody noticed it could be defeated by the poisoned array.

If iPhone losses are still occurring on current builds, they are a second mechanism
(candidates: 3x-retry exhaustion is silent beyond a haptic; app killed within the
0.3 second debounce window before focus loss fires). The diagnostics log
distinguishes: iPhone losses WITH a logged save event = sync layer; without = UI.

## The fix (APPLIED 2026-07-23, Jason-authorized; hook lifted for the edit and restored)

Matching the iPhone precedent: the view model now tracks lastSavedImageNumber — set
to the entry's value when editing starts (both startEditing branches) and advanced
whenever a save proceeds. saveCurrentEditingEntry's guard compares the typed text
against that baseline instead of against the watch-merged array entry, which the
watch stream itself poisons. Five small edits, all in CapturaSportsView.swift:
property declaration near line 54, guard near line 4261, baseline advance near line
4271, and baseline resets near lines 4317 and 4329. Build verified (workspace build
SUCCEEDED 2026-07-23).

The camera-capture path (near line 593) intentionally does not touch the baseline:
after a capture the typed text differs from the baseline, so switching entries
triggers one redundant save of identical content. Harmless by design — err toward
an extra write, never a skipped one.

The array-poisoning display clause (near line 4073) was deliberately left as-is; with
the guard no longer reading the array, it is display-only again. Do not also change
it without re-analyzing.

Validation: CONFIRMED on-device by the owner 2026-07-23 — smoke test passed (type,
wait through a heartbeat, switch entries, reload; numbers persist at speed as well).
On a pre-fix build, that exact sequence reproduced the loss.

## Drift map — the same feature implemented twice

Both views edit roster_entries through PowerSyncManager.saveRosterEntry and watch
through watchRosterEntries. Everything else has drifted:

Editing state
- iPhone: per-entry dictionaries editingValues and lastSavedValues keyed by entry id;
  currentlyEditingEntryId tracks focus.
- iPad: ONE shared slot viewModel.editingImageNumber plus currentlyEditingEntry.
  Whatever entry is current owns the single string.

Save triggers
- iPhone: 0.3 second debounce while typing (handleEditingValueChange), plus
  unconditional save on entry switch (stopEditing), plus focus-loss save from the
  text field. Change detection against lastSavedValues.
- iPad: save only on switch, focus loss, or arrow navigation
  (saveCurrentEditingEntry). No debounced save while typing. Change detection against
  the watch-merged array entry — the defect described above.

Save function differences
- iPhone saveEntry: does not touch version. Retries 3x with backoff, error haptic on
  final failure.
- iPad saveCurrentEditingEntry: increments version by 1. Same 3x retry. Also has an
  auth guard the iPhone save lacks.

Watch-merge differences
- iPhone: per-entry protection for the currently-edited entry, newer-timestamp-wins
  for all entries, keeps local entries missing from server data, conflict banner when
  server is newer with different content, tracks recentlyDeletedEntryIds.
- iPad: same currently-editing protection and newer-timestamp-wins, PLUS extracts
  lock info into lockedEntries, PLUS an empty-emission guard (does not clear a
  populated roster), PLUS a diff-merge that only replaces changed rows to prevent
  scroll jumps, with scroll-anchor restore. No conflict banner. No
  recentlyDeleted tracking on this path.

Keyboard
- iPhone: system number pad with a toolbar (up/down/hyphen).
- iPad: custom in-app keyboard via KeyboardManager (mini mode), shown from
  AutosaveTextField's iPad branch.

Maintenance rule until retirement: any fix applied to one view MUST be evaluated for
the other, explicitly, at fix time. The two views fail independently — the original
2026-03 timestamp guard was on iPhone only, and today the unconditional-save patch is
on iPhone only. History repeats.

Long-term: do not refactor these files to share code (protected production files).
The sanctioned path is FP Sports reaching feature parity, then deleting both Captura
views whole (delete-first migration).

# CRS.1 — Captura Roster Save Hardening (plan)

Proposed arc code CRS.1 (Captura Roster Save); register in
~/Brain/projects/registry.md (formerly FocalPointProduction/docs/PHASES.md) at kickoff per the family naming rule.
Written 2026-07-23. Source: the four pre-existing weaknesses documented in the
post-ship adversarial review of commit 6bf00ba — see CAPTURA_ROSTER_SAVE_ANALYSIS.md
(Post-ship adversarial review section). None are regressions; all predate the
2026-07-23 image-number fix. This plan fixes all four.

## Standing constraints (read before building)

- Both roster editors are protected Captura production files. Every edit to
  CapturaSportsView.swift or CapturaSportsRosterView_iPhone.swift requires the
  operator to explicitly authorize lifting the protect-captura-files hook. The
  established procedure (used 2026-07-23): comment the one basename out of the
  hook list, make the edits, restore the line, re-test the hook blocks again.
  Never leave the hook lifted between work sessions.
- Maintenance rule from the drift map: any fix applied to one view MUST be
  explicitly evaluated for the other at fix time. Each item below names its
  iPhone twin status; the builder verifies rather than assumes.
- The fix-twice history of this code (2026-03 timestamp guard, 2026-07 baseline
  guard) is the cautionary tale. Do not skip the twin checks.
- No refactoring toward shared code between the two views. Point fixes only.
  Consolidation happens by FP Sports retirement, not in these files.

## W1 — Own-lock entry switch loses the previous entry's text (iPad)

Where: CapturaSportsView.swift, startEditing, the already-own-lock early-return
branch (near line 4313).

Mechanism: the branch switches editing to the new entry without saving or
releasing the previous one. Reachable because lock release is async
fire-and-forget: edit B, move to A, type into A, tap B again within the stale
lockedEntries window (before the next watch emission) — isOwnLock(B) is still
true, the branch overwrites the editing text, A's typed value is lost and A's
lock leaks until expiry.

Fix: make the own-lock branch mirror the normal branch. Before setting the new
editing state: if currentlyEditingEntry exists and differs from the tapped
entry, call saveCurrentEditingEntry() and releaseLock for the previous entry.
Keep the existing baseline reset for the new entry. The save must run before
editingImageNumber is overwritten (same ordering the normal branch already
uses at its save-then-overwrite sequence).

iPhone twin: expected no change — iPhone startEditing awaits stopEditing for
the previous entry on every switch path. Builder verifies by reading the
iPhone startEditing and confirming there is no equivalent early-return branch
that skips the save.

On-device test: edit athlete B, arrow to athlete A, immediately type digits
into A, tap back on B within a second. A's digits must persist after reload.

## W2 — Sidebar shoot switch mid-edit drops unsaved text (iPad)

Where: CapturaSportsView.swift, the onChange handler for the selected shoot id
(near line 1985) and the sidebar selection set-points (near lines 1413 and
1461). The handler cancels watchers and reloads the roster without saving or
clearing editing state.

Mechanism: if the text field's focus-loss save does not fire before
rosterEntries is replaced with the new shoot's roster, saveCurrentEditingEntry
exits at its entry-lookup guard (the edited entry no longer exists in the
array) and the typed text is silently dropped. Editing state also leaks across
shoots: currentlyEditingEntry can point at an entry id from the previous shoot.

Fix: at the top of the shoot-switch handler, synchronously (before any roster
replacement or watcher cancellation): if currentlyEditingEntry is non-nil,
call saveCurrentEditingEntry() while the old roster array is still in memory,
release that entry's lock, then clear currentlyEditingEntry,
editingImageNumber, and lastSavedImageNumber. Only then proceed with the
existing teardown/reload sequence. Trace both sidebar set-points to confirm
they funnel through this one onChange; if either sets the shoot directly
without firing it, apply the same guard there.

iPhone twin: expected no change — the iPhone has no sidebar; leaving the
editor pops the navigation stack and onDisappear saves through stopEditing.
Builder verifies onDisappear actually runs the save on iOS 16-26 navigation
(read the code path, then device-test once: type, immediately swipe back,
reopen, value persisted).

On-device test: type digits into an athlete, immediately tap a different shoot
in the sidebar, return to the first shoot. Digits must persist.

## W3 — Camera capture mid-typing overwrites the in-flight typed text (iPad)

Where: CapturaSportsView.swift, the capture handler (near lines 584 to 609).

Mechanism: a capture landing while the photographer is typing merges the new
image number from the ARRAY value (which lags the live typed text between
watch emissions), then writes the merged result into editingImageNumber —
clobbering unsent keystrokes on screen. Persisted outcome was already safe;
this is a visible-text correctness fix.

Fix: inside the existing currentlyEditingEntry == entryId branch, parse the
image-number list from viewModel.editingImageNumber (the live typed text)
instead of from the array entry, append the captured number, format, and write
the result to BOTH editingImageNumber and the array entry (keeping the
existing fresh updatedAt and version bump). Leave lastSavedImageNumber
untouched — the deliberate redundant-save safety net from the 6bf00ba fix
then guarantees the merged value persists even if the debounced capture save
races. When the entry is NOT being edited, the current array-based merge
stays as is.

iPhone twin: builder greps the iPhone file for an equivalent
capture-updates-editing-text path; if none exists (captures are an iPad
workspace feature), record that and move on.

On-device test: start typing a partial number into an athlete, trigger a
capture for the same athlete from the camera station, confirm the typed
digits AND the captured number both appear, then persist after reload.

## W4 — Exhausted save retries lose the value with only a haptic (both views)

Where: CapturaSportsView.swift saveCurrentEditingEntry retry loop (near lines
4281 to 4299) and CapturaSportsRosterView_iPhone.swift saveEntry retry loop
(near lines 2243 to 2258).

Mechanism: the local PowerSync write is retried 3 times; on final failure the
only signal is an error haptic and a console print. The iPad baseline (and the
iPhone lastSavedValues) has already advanced optimistically, so the app
believes the value is saved and will never retry. Requires a local SQLite
write failure — rare, but the failure mode is silent data loss.

Fix, both files, same shape:
- Capture the pre-save baseline before advancing it. On final failure, revert
  it (iPad: lastSavedImageNumber back to its prior value; iPhone: do not
  advance lastSavedValues for that entry). A later switch/blur then re-attempts
  the save instead of skipping it.
- Log the failure through RosterEditDiagnostics with the entry id and the
  value that failed to persist (the logger is an unprotected additive file;
  extend it if a new event kind is needed).
- Surface a real alert naming the athlete and the value, replacing
  haptic-only. Reuse each view's existing errorMessage / showingErrorAlert
  plumbing — no new UI.
- Do not clear the typed value from the screen on failure.

iPhone twin: included above — this item is inherently both-files.

Bench test (no device failure needed): temporarily force the save call to
throw in a debug build, confirm the alert appears, the value stays on screen,
and switching away then back re-attempts and (once un-forced) persists.
Remove the forcing before commit — a phase cleans up its own scaffolding.

## Build order and verification

Order: W1 then W2 (real loss paths, same file, same authorization lift), then
W3 (visible-text correctness), then W4 (both files). One session, one hook
lift per file, hook restored and re-tested at the end.

Gate sequence per the working standard:
1. Build via the workspace (the xcodeproj alone fails at link — CocoaPods).
2. Re-grep every edit anchor to confirm landed.
3. Hook restored and verified blocking (exit 2 on both basenames).
4. Operator on-device smoke: the four per-item tests above, plus the 6bf00ba
   regression check (type, wait 35 seconds, switch, reload — must persist).
5. Separate /code-review (high) or /code-review ultra over the branch before
   push — operator-triggered.
6. Targeted git add by path only. Commit after review; push after operator
   confirms. Closeout: mark CRS.1 done in AUDIT_ROADMAP.md and
   kickoffs/START_A_PHASE.md, update the family registry, record in memory.

Explicitly out of scope: any shared-code refactor of the two views, any
change to FPSportsRosterView_iPad, the watch-stream display clause (left
as-is by design — see CAPTURA_ROSTER_SAVE_ANALYSIS.md), and W3's persisted
behavior (already safe; only the on-screen merge source changes).

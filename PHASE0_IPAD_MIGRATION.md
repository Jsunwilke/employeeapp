# Phase 0 iPad migration — chunk B receiver client

This is the iPad side of the Phase 0 sync rewrite. The Mac (FP Production) side is in `~/Desktop/FocalPointProduction/SYNC_ARCHITECTURE_SPEC.md`. This doc covers what changed on iPad, how to flip the flag, and what to verify.

## What landed

Five files touched in the iPad app:

1. **NEW: `Iconik Employee/Sports Shoot Feature/Phase0Flags.swift`**
   Feature flag (`useRepoPatternSubjects`) read from UserDefaults. Default OFF — the legacy iPad write path (PowerSync direct + WebSocket subject_updated broadcast) stays as the only production path until you opt in.

2. **NEW: `Iconik Employee/Sports Shoot Feature/SubjectCommandTypes.swift`**
   Swift port of the WebSocket `subject_command` envelope per SYNC_ARCHITECTURE_SPEC.md §4. Types: `SubjectCommand`, `CommandAck`, `SubjectCommandError`, plus a `SubjectCommandBuilder.update(...)` helper. Wire shape is locked — keys match the TS counterpart in `src/data/repositories/transports/surface-command-transport.ts`.

3. **MODIFIED: `Iconik Employee/Sports Shoot Feature/FocalPointSyncClient.swift`**
   - New state: `pendingCommandAcks: [String: CheckedContinuation<CommandAck, Error>]` (mirrors the existing `pendingImageRequests` pattern at line ~195).
   - New method: `sendSubjectCommand(_ cmd: SubjectCommand) async throws -> CommandAck`. Sends the wire dictionary, captures a continuation against the command_id, schedules a 30s timeout. Throws on timeout / not-connected / missing gallery.
   - New helper: `isConnectedAndInGallery(_ galleryId: String) -> Bool` for in-shoot detection.
   - New dispatcher case: `case "command_ack":` resolves the matching continuation; drops if no continuation found (typed-out, or this iPad isn't the originator).

4. **MODIFIED: `Iconik Employee/Sports Shoot Feature/SubjectSyncService.swift`**
   `updateSubject(_ req, currentSubject)` gets a flag-gated branch:
   - **Flag on + in-shoot**: build subject_command, send + await ack. On `applied`/`dedupe` → return without writing PowerSync (Surface is the writer per §11.1). On `rejected` or transport error → fall through to legacy path so the edit isn't lost.
   - **Otherwise**: existing legacy path (overlay + PowerSync + broadcast) — byte-identical to before this change.

5. **NEW: this runbook**

## How to flip the flag

The flag lives in UserDefaults. Three ways to turn it on:

**Xcode debugger console** (runtime, no rebuild):
```
e Phase0Flags.setUseRepoPatternSubjects(true)
```

**Xcode launch arguments** (per-run):
- Edit scheme → Arguments → Arguments Passed On Launch
- Add: `-use_repo_pattern_subjects YES`

**Programmatic** (e.g. a settings toggle you wire up):
```swift
Phase0Flags.setUseRepoPatternSubjects(true)
```

To revert: pass `false`. The next subject mutation reads the flag fresh, so you can flip mid-session.

## Build setup

The Iconik Employee target uses `PBXFileSystemSynchronizedRootGroup`
(Xcode 15+) — every file under `Iconik Employee/` is automatically part
of the build. The two new files (`Phase0Flags.swift`,
`SubjectCommandTypes.swift`) are picked up on the next Cmd+B without any
manual project edits.

## What to test once you build

You'll need:
- A Surface running FP Production with the chunk-A subjects flag and chunk-B receiver in place (it already is — `~/Desktop/FocalPointProduction` is at chunk B.3).
- An iPad running this build.
- Both on the same LAN so the iPad can connect to the Surface's WebSocket.

**Smoke test 1 — flag off (no behavior change)**:
1. Launch iPad with flag OFF. Connect to Surface and join a gallery.
2. Edit a subject's name on iPad. Should persist exactly as before — written to PowerSync + broadcast as `subject_updated`.
3. Surface UI should reflect the change within a few seconds.

**Smoke test 2 — flag on (new path)**:
1. Flip flag ON in Xcode debugger. Connect to Surface and join a gallery.
2. Edit a subject's name on iPad.
3. Expected: iPad sends a `subject_command` over WebSocket. Surface's chunk-B receiver applies it through SurfaceLocalTransport → local PowerSync write → cloud sync.
4. Surface emits a `subject_updated` broadcast back; iPad receives and refreshes the overlay.
5. iPad's PowerSync eventually pulls the cloud-confirmed row, overlay clears.

**How to verify**:
- iPad console logs: should show `[FPSync] Sent subject_command` and `[FPSync] Received: command_ack`.
- Surface DevTools (open in Tauri's WebView dev menu): WebSocket panel should show inbound `subject_command` and outbound `command_ack`.
- Supabase: query `command_log` table for the row corresponding to your edit. Outcome should be `applied`. Both `originating_device_id` and `authenticated_device_id` should equal the iPad's device id.
- Subject row in Supabase: `last_originating_device_id` should equal the iPad's device id (proves the write went through the receiver, not direct PowerSync).

**Failure mode test — Surface offline**:
1. Disconnect Surface (close lid, or kill the app).
2. iPad edit a subject with flag ON.
3. Expected: command times out after 30s. Falls through to legacy path. Edit lands in PowerSync locally, broadcasts on next reconnect. No data loss.

## Known limitations (chunk-B.4+ work)

- **`originating_device_id` is wire-claimed** — Surface's receiver records it as `originating_device_id` (claimed) AND `authenticated_device_id` (server-set). Currently both hold the same untrusted wire value because the §11.2 token plumbing isn't done. A malicious iPad could spoof another device's id; the `authenticated_device_id` column is the seam where the §11.2 fix will land.
- **No state_sync round-trip yet on iPad reconnect** — Surface's chunk-B.3 `state_sync` handler is in place but the iPad doesn't yet send `device_hello { last_version_seen }` on reconnect. Reconnect today still relies on PowerSync's eventual consistency.
- **Capture writes are NOT routed through commands** — only subject mutations. capture_images writes still go through the iPad's existing path. That's chunk C-iPad, not yet built.
- **Optimistic UI rollback on rejection** — current code clears + re-applies the overlay around a rejection. Edge cases (multiple in-flight commands for the same subject) may show flicker. Acceptable for chunk-B-iPad MVP.

## Rollback

Flip the flag off. Next mutation reads the flag fresh and uses the legacy path. No code rebuild required for rollback.

If you want to remove the new code entirely, the four files in §1 above are the diff — three are net-new and the fourth has a clearly-marked "Phase 0 sync rewrite" branch.

# Phase 0 iPad migration — chunk B receiver client

This is the iPad side of the Phase 0 sync rewrite. The Mac (FP Production) side is in `~/Desktop/FocalPointProduction/SYNC_ARCHITECTURE_SPEC.md`. This doc covers what's running on iPad and what to verify.

## What's in the build

Three iPad files carry the Phase 0 work:

1. **NEW: `Iconik Employee/Sports Shoot Feature/SubjectCommandTypes.swift`**
   Swift port of the WebSocket `subject_command` envelope per SYNC_ARCHITECTURE_SPEC.md §4. Types: `SubjectCommand`, `CommandAck`, `SubjectCommandError`, plus a `SubjectCommandBuilder.update(...)` helper. Wire shape is locked — keys match the Mac TS counterpart in `src/data/repositories/transports/surface-command-transport.ts`.

2. **MODIFIED: `Iconik Employee/Sports Shoot Feature/FocalPointSyncClient.swift`**
   - State: `pendingCommandAcks: [String: CheckedContinuation<CommandAck, Error>]` (mirrors the existing `pendingImageRequests` pattern).
   - Method: `sendSubjectCommand(_ cmd: SubjectCommand) async throws -> CommandAck`. Sends the wire dictionary, captures a continuation against the command_id, schedules a 30s timeout. Throws on timeout / not-connected / missing gallery.
   - Helper: `isConnectedAndInGallery(_ galleryId: String) -> Bool` for in-shoot detection.
   - Dispatcher case: `case "command_ack":` resolves the matching continuation; drops if no continuation found (timed out, or this iPad isn't the originator).

3. **MODIFIED: `Iconik Employee/Sports Shoot Feature/SubjectSyncService.swift`**
   `updateSubject(_ req, currentSubject)` always tries the command path first when the iPad is in a Surface-connected shoot:
   - **Surface acks `applied` or `dedupe`** → return without writing PowerSync. The Surface is the writer per §11.1; PowerSync's eventual cloud-sync delivers the row to this iPad too, and `reconcileLocalRow` clears the overlay then.
   - **Surface acks `rejected`** → roll back the overlay, fall through to the legacy local-write path so the edit isn't silently lost.
   - **Transport error / timeout / iPad not in shoot** → legacy local-write path runs. Same as before Phase 0. The iPad never loses an edit because the WebSocket wobbled.

No feature flag. The new path is always-on; the legacy path is the fallback safety net.

## Build setup

The Iconik Employee target uses `PBXFileSystemSynchronizedRootGroup`
(Xcode 15+) — every file under `Iconik Employee/` is automatically part
of the build. New `.swift` files are picked up on the next Cmd+B without any manual project edits.

## What to test

You'll need:
- A Surface running FP Production with the chunk-B receiver in place (`origin/main` is fine — receiver is built unconditionally as of commit 39b8112).
- An iPad running this build.
- Both on the same LAN so the iPad can connect to the Surface's WebSocket.

**Happy path**:
1. Connect iPad to Surface, join a gallery.
2. Edit a subject's name on iPad.
3. iPad console (Xcode → Debug Area) should show `[FPSync] Sent subject_command (...)` followed by `[FPSync] Received: command_ack`.
4. Surface's local SQLite has a `command_log` row for the edit (outcome = `applied`).
5. The subject row in Supabase has `last_originating_device_id` equal to the iPad's device id — confirms the write went through the Surface receiver, not direct PowerSync.

**Failure mode (Surface offline)**:
1. Disconnect Surface (close lid, or kill the app).
2. iPad edits a subject.
3. Expected: command times out after 30s. iPad falls through to legacy path. Edit lands in iPad's PowerSync locally; cloud-syncs whenever connectivity returns. No data loss.

## Known limitations (post-MVP work)

- **`originating_device_id` is wire-claimed** — Surface's receiver records both `originating_device_id` (the claim) and `authenticated_device_id` (server-set). Currently both hold the same untrusted wire value because the §11.2 token plumbing isn't done. A malicious iPad could spoof another device's id; the column distinction is where the §11.2 fix will land later.
- **No state_sync round-trip yet on iPad reconnect** — Surface's `state_sync` handler is in place but the iPad doesn't yet send `device_hello { last_version_seen }` on reconnect. Reconnect today still relies on PowerSync's eventual consistency.
- **Capture writes are NOT routed through commands** — only subject mutations. capture_images writes still go through the iPad's existing path. That's chunk C-iPad, not yet built.

## Rollback

If the new path causes problems, roll back via `git revert <commit>` — all the work is in three files (or four counting the runbook). No flag to flip; no half-on/half-off state to reason about.

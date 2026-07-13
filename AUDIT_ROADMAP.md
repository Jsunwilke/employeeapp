# App Audit Roadmap — July 12, 2026

Source: full 5-dimension audit (security, architecture, data/sync, performance, UX/UI) of the app at commit f7e5c67.
Full visual report: https://claude.ai/code/artifact/4ae6e46a-bc04-4307-b589-ef3233f42e41

**How to use this file:** each phase is a checklist. Check items off as they're completed
(`[x]`), and add a dated note under the phase when it's done. To resume in a new session,
say "continue the audit roadmap" or "start phase N" — everything needed is in this file.

Status: **Phase 1 in progress (2026-07-12).** Code done + committed. Claude proxy DEPLOYED and TESTED working on Focal-Point project. NOT YET DONE: (a) lock-down migration must wait until a new app build is live in users' hands — running it now breaks the current app's roster scanning; (b) rotate Anthropic key; (c) revoke Apple keys + Google key restriction + git history purge. See PHASE1_MANUAL_STEPS.md.

---

## Phase 1 — This week (security damage control + dead code)

### 1.1 Rotate & purge committed secrets
- [ ] Revoke in Apple Developer portal: `AuthKey_58S4768CLL.p8` (in `Iconik Employee/`), `AuthKey_FHV9KAR596.p8`, `AuthKey_ZVZ46FYX5T.p8` (repo root), and the `Certificates.p12` signing identity
- [ ] Generate replacement keys; store OUTSIDE the repo (Keychain / CI secret store)
- [ ] Rotate the Captura client secret (hardcoded fallback at `Functions/index.js:1660`) and the rebuild token (`Functions/index.js:203`); remove both inline fallbacks — fail closed if env var missing
- [ ] Purge all of the above from git history (`git filter-repo`), force-push
- [ ] Add to `.gitignore`: `*.p8`, `*.p12`, `*.cer`
- [ ] Restrict the Google API key (`AIzaSy...UJnSE` in `GoogleService-Info.plist` + `Config.xcconfig`) to bundle ID + needed APIs in Google Cloud console

### 1.2 Move the Anthropic key server-side
- [ ] The org `sk-ant` key is readable by ALL employees: `supabase/migrations/008_create_app_config.sql:18` has `USING (true)` RLS on `app_config`
- [ ] Create a Supabase Edge Function proxy for Claude calls; client never receives the key
- [ ] Remove key fetch + UserDefaults persistence from `ClaudeRosterService.swift:97,135-141`
- [ ] Rotate the Anthropic key after cutover

### 1.3 Wipe local data on sign-out
- [ ] `SupabaseAuthService.signOut()` (`SupabaseAuthService.swift:165-182`) currently only purges SubscriptionCache
- [ ] Add: PowerSync DB clear (`PowerSyncManager.clearAndReSync()` / `disconnectAndClear()` exists, only wired to a Settings button), `SportsShootSyncQueue` (`SyncEngine` UserDefaults queue), chat caches, schedule JSON caches, PII `@AppStorage` keys (consider `removePersistentDomain`)
- [ ] Context: shared iPads are handed to non-employees on-site (`PowerSyncManager.swift:353` comment); student roster PII persists across accounts

### 1.4 Delete dead code (~6,000 lines, zero risk — nothing is compiled or called)
- [ ] `backup_firebase_files/` (5 `_OLD.swift` files, not in pbxproj)
- [ ] `StatisticsViewOLD.swift` (repo root, 1,460 lines, not compiled)
- [ ] `Iconik Employee/Sports Shoot Feature/SyncEngine.swift` (738 lines, zero callers — replaced by PowerSyncManager)
- [ ] `LocalSportsRepository.swift` (only referenced by SyncEngine)
- [ ] `NetworkMonitor.swift` (dead legacy poller — verify no live callers first)
- [ ] `Iconik Employee/GoogleService-Info.plist` (orphan Firebase artifact — verify nothing reads it at runtime first)
- [ ] Fix orphaned `Iconik Employee/Sports Shoot Feature/ImageNumbersMergerTests.swift` (in no target — move to test target or delete)

---

## Phase 2 — Weeks 1–2 (quick wins users will feel)

> STATUS 2026-07-12: PHASE 2 COMPLETE except the launch-chain rewrite (deferred — see below).
> Also done beyond batches 1–3: offline clock in/out queue (TimeClockOutbox, user-tested OK),
> unpinGallery fix, chat channel leak fix (ChatManager), UserFacingError helper (wired into
> clock + sign-in), UIImage downsampling on editable upload sites, TimeTrackingService is now a
> shared singleton. NotificationCenter observer-leak item: the one flagged instance is in
> SportsShootListView (PROTECTED — can't touch); the editable FP iPad view didn't have the
> block-observer pattern, so effectively closed. DROPPED (won't do): launch-chain rewrite — reviewed the
> cost/benefit with the owner 2026-07-12. Payoff is only a slightly faster cold launch (no
> correctness benefit), and the owner has never noticed launch being slow. Not worth touching the
> sign-in gate (high blast radius, recent bug eb97c6e) for polish nobody feels. Revisit ONLY if
> users start reporting slow/hanging launches.
> --- original batch 1–3 note follows ---
> Batches 1–3 done + committed + build-verified + USER-TESTED OK on a build. DONE: GPS one-shot,
> Live indicator wired to real network, UUID lowercase sweep (insert sites + FP iPad;
> SportsShootListView skipped — protected), chat @Published main-actor hop, photo-note
> delete confirmation, clock in/out error surfacing, signed-URL image cache. Also
> verified the 3 flagged swipe-deletes already confirm (no change). DEFERRED: launch-chain
> rewrite (high blast radius — startup gate w/ recent bug eb97c6e; do with live verification),
> upload downsampling (partly in protected files), UserFacingError helper, TimeTrackingService
> singleton (touches shared state; verify carefully). Extra work this session: diagnosed the
> Captura image-number save bug (race in protected SportsShootDetailView) and shipped
> always-on logging to catch it (see RosterEditDiagnostics + PHASE1 notes).

- [ ] **Launch chain** (`RootView.swift:25-57`): replace the 50ms busy-poll on `sessionCheckComplete` (up to 10s) with await/continuation; drop the redundant org-ID query (`UserManager.swift:117-142`, fully subsumed by the profile query in `UserProfileService.swift:214-219`); remove up to 1.5s retry sleeps; render optimistically from cached org id
- [ ] **Clock in/out error surfacing + offline queue** (`TimeTrackingService.swift:95-209`): writes throw when offline with nothing queued; the AllFeaturesView clock button (`AllFeaturesView.swift:163-165`) swallows errors with print only. Queue clock events (append-only, conflict-free), reconcile on reconnect, add toast + haptic on failure. This is payroll data.
- [ ] **GPS**: `RoutePlannerView.swift:762-804` starts `kCLLocationAccuracyBest` continuous updates, never stopped anywhere in the codebase. Use one-shot `requestLocation()` (wrapper already exists at `:788`)
- [ ] **UUID lowercase sweep** (per CLAUDE.md rule): `SessionService.swift:513,547,663`; `TimeTrackingService.swift:136,585`; `SupabaseChatService.swift:58,122`; `TemplateService.swift:596`; `ReadCounterService.swift:60`; `presentIds.contains(member.id.uuidString)` at `FPSportsRosterView_iPad.swift:4052-4084` + `SportsShootListView.swift:3367-3399`; lowercase gallery-ID boundaries in `FocalPointSyncClient.swift:725-733,1426-1429` and SubscriptionCache keys
- [ ] **unpinGallery fix** (`PowerSyncManager.swift:1231,1255`): pin inserts random row id, unpin deletes by `userId_galleryId` composite that never matches; also zero callers of unpin → sync scope grows forever. Delete by `user_id AND gallery_id` columns; add unpin/TTL path
- [ ] **Wire the fake Live indicator** (`Schedule/RealTimeSyncIndicator.swift:6`): `isOnline` is hardcoded `true`, connected to nothing — connect to a real network monitor
- [ ] **Delete confirmations**: `MyJobReportsView.swift:109` (one-swipe report deletion), `ClassGroupJobDetailView.swift:56`, `ClassGroupJobsListView.swift:45`, `PhotoshootNotesView.swift:728` (cascades storage deletion)
- [ ] **Human error messages**: one `UserFacingError` helper mapping top ~10 Postgrest errors; ~200 call sites currently show raw `error.localizedDescription`
- [ ] **Image pipeline**: `SupabaseImageView.swift:46,79,113` mints a new signed URL every appearance (defeats all caching — cache by path + NSCache); downsample before upload at `ProfilePhotoView.swift:82`, `PhotoshootNotesView.swift:748`, `LocationPhotoAttachmentView.swift:635`, `SchoolDetailView.swift:362`, `TemplateFormView.swift:916`, `MessageThreadView.swift:329`
- [ ] **Leaks**: `ChatManager.swift:191` — unsubscribe `messagesChannel` before reassigning (also `conversationsChannel` at `:110`); store + remove block-based NotificationCenter tokens at `SportsShootListView.swift:2281,2326,2344,3880` and `FPSportsRosterView_iPad.swift:2931,2977,2988,4664` (current `removeObserver(self)` can't remove token observers)
- [ ] **TimeTrackingService singleton**: it's instantiated per-view at 5+ sites (`MainEmployeeView.swift:567`, `AllFeaturesView.swift:9`, `TimeTrackingButton.swift:105`, `NFC/ManualEntryView.swift:36`, `NFC/JobBoxFormView.swift:14`) — divergent clock-in state, duplicate NWPathMonitors. Make it `.shared`
- [ ] **@Published off main**: `SupabaseChatService.swift:229,232,270,273` — wrap initial-fetch completions in `MainActor.run` (change-stream path at `:241,:282` already does)

---

## Phase 3 — Month 1–2 (structural)

- [ ] **Real TabView navigation** (fixes double back buttons + state loss):
  - Root cause: `MainEmployeeView` wraps everything in `NavigationView` (`:623,668`) + fake string tabs (`TabBarManager.selectedTab` string, 29-case switch at `:872-932`) + fake "< Home" toolbar button (`:944-963`) + `topBarBackOverride` hack (`:938-951`); features open nested NavigationViews (`SportsShootListView.swift:232,293,1095,1344`)
  - Target: `TabView` with 5 role-aware tabs (Today / Schedule / Scan / Time / More), each owning one `NavigationStack` + `NavigationPath`; "More" = searchable grouped grid (26 flat features → ~12 grouped); Hashable route enums + `navigationDestination`; deep links via `onOpenURL` route parser
  - Migrate incrementally: shell first, then feature by feature; replace 102 `NavigationView` uses over time; kill `DoubleColumnNavigationViewStyle` at `SportsShootListView.swift:2018`, `FPSportsRosterView_iPad.swift:2634`
- [ ] **Shared RosterEditingController** (highest-value refactor) — ⚠️ CONSTRAINED: `SportsShootDetailView.swift`, `SportsShootListView.swift` and other Captura roster files are PROTECTED (hook-blocked, used by other photographers in production — see protected-captura-files memory). The original plan (retrofit both device views to call a shared controller) is NOT allowed because it requires editing the protected files. Revised approach: only `FPSportsRosterView_iPad.swift` (not protected) can be refactored; any shared logic must live in a NEW file that the protected files are not modified to use. The iPad/iPhone dedup as originally scoped is effectively off the table unless the user edits the Captura files themselves. Still safe: cache `PoserStationView.filteredSubjects` (`:277`, evaluated ~8x/render — PoserStationView is not protected; verify against hook first)
  - DONE 2026-07-12, build-verified. `PoserStationView` confirmed not protected (deny-list empty; not in the protected set). `filteredSubjects` (3 filter passes + O(n log n) sort) now memoizes on a cheap change-signature (subjects' id/updatedAt/isPhotographed + searchText/sortField/imageFilterType + order-independent hashes of activeFilters & photoCountMap) via a `FilteredSubjectsMemo` reference held in @State. Runs once per input change instead of ~8x/render; signature is recomputed each access so it can't serve a stale list. The rest of the shared-RosterEditingController refactor stays off the table (needs protected Captura files).
- [x] **SessionService refetch storm** (`SessionService.swift:90-101,222-240,726-748`): full-org fetch, no date bound, refetched per-subscriber (~10 views) on every realtime event; `recalculateSessionColorsForDate` = 1 UPDATE per session, each triggering more refetches. Debounce, share one fetch, batch color updates into a single RPC, bound query by date range. Also: cache ignores `includeUnpublished` (`:77-83`) → unpublished sessions leak to employees for up to 5 min
  - DONE 2026-07-12, build-verified. Fixed: (1) `includeUnpublished` cache leak — `sessionsCache` is now scope-tagged (`cachedIncludeUnpublished`) and `cacheSatisfying()` never serves unpublished rows to a published-only caller (online + offline + immediate-cache-display paths all filter). (2) Storm — added in-flight fetch coalescing (`inFlightFetches` keyed by `org|scope`) so N subscribers reacting to the same event collapse to one query, plus a 400ms per-subscription debounce so a multi-row color recalc's event-per-row burst collapses to one refetch. Net: `events × subscribers` fetches → ~1. DEFERRED (needs DB migration): batch color UPDATEs into a single RPC, and date-bounding the shared full-org fetch (would fragment the shared cache / change every caller — higher blast radius, felt problem already solved on the read side).
- [ ] **Design tokens**: one `FeatureTheme` (three conflicting feature-color maps: `MainEmployeeView.swift:1202`, `AllFeaturesView.swift:249`, `BottomTabBar.swift:492`); static `Formatters` cache with `en_US_POSIX` + org timezone (212 `DateFormatter()` allocs, 73 files, timezone-naive "yyyy-MM-dd" everywhere); `cardStyle()` modifier (83x cornerRadius(12), 48x shadow); restore Dynamic Type in 5 worst files (373 fixed font sizes total)
- [x] **Server-side RLS audit** (highest-value security follow-up): all app authorization is client-side (`PermissionsService.swift:30-100` = local dictionary; manager views rendered from tab id with no guard at `MainEmployeeView.swift:915-922`). Verify RLS on `users`, `time_off_requests`, `app_config`, and all org-scoped tables ties `organization_id`/actor columns to the authenticated user; verify `send-notification`, `acquire_lock`, chat RPCs re-authorize the caller rather than trusting `p_user_id` args
  - DONE 2026-07-12 (repo-visible surface): findings + verification SQL in `RLS_AUDIT.md`. Confirmed: `acquire_lock` trusts `p_user_id` (no `auth.uid()` check, no org scope; drafted fix in `supabase/drafts/harden_acquire_lock.sql`); `send-notification` has no caller authz (any employee can push to anyone — spoofing); `app_config` locked down ✓; core-table policies (`users`/`sessions`/`time_entries`/etc.) and chat-RPC bodies live only in the DB → **user must run the §B SQL in the Supabase console to close out**. Nothing deployed.

---

## Phase 4 — This quarter (compounding)

- [ ] **Decompose god files** (start mechanical): `DashboardWidgets.swift` (2,251 lines, 9 unrelated widgets) → 9 files; extract nested views from Sports Shoot monoliths (`SportsShootRow` at `SportsShootListView.swift:2792`, `FilterPanelView` at `:3002`, etc.)
- [ ] **Daily Job Report redesign** (`Misc Features/DailyJobReportView.swift`, 1,946 lines): entry from today's shift card pre-filling 4/8 sections; 3-step wizard; draft auto-save (currently ALL input lost on failure/kill); offline outbox with queued/synced chip
- [ ] **Invite-code onboarding**: replace hand-typed Organization ID (`CreateAccountView.swift:45`); fix silent sign-in-with-empty-profile (`SignInView.swift:168-174` proceeds on profile-fetch failure); blocking-with-feedback bootstrap + Retry; empty-state guidance on first dashboard; in-context permission priming
- [ ] **Tests for money paths**: `TimeEntryValidator` (in `Models.swift`), `PayPeriodService` — zero coverage today; all 5 existing test files cover only Sports Shoot sync
- [ ] **Group images conflict handling** (`PowerSyncManager.swift:586-643`, `FocalPointSyncClient.swift:2008-2044`): dual-path (PowerSync upsert + LAN INSERT OR REPLACE) whole-row last-write-wins; `version` column written, never checked. Route through command/ack like subjects, or version-checking RPC
- [ ] **Data protection**: `.completeUntilFirstUserAuthentication` on `powersync-sports.db`, `subscription_cache.sqlite`, caches; move PII out of UserDefaults; TLS or scoped tokens for LAN photo fetch (`FocalPointSyncClient.swift:1024-1107` sends Bearer over http)
- [ ] **Going-forward rules** (add to CLAUDE.md when adopted): views never touch SupabaseClient (19 current offenders); one `AppSession` env object replacing 32 scattered `@AppStorage("userOrganizationID")` reads; `os.Logger` over print (1,067 prints); one shared error presenter (52 comment-only catches, 203 catch-and-print, 397 try?)

---

## Reference: what NOT to break (verified strengths)

- Firebase migration is 100% complete in live code — no dual-writes anywhere
- Subject sync (CommandQueue + acks + idempotency + optimistic overlay rollback) is solid — don't "simplify" it
- Zero `try!`/`as!`/`fatalError`; keep it that way
- Core services have correct weak-self/timer/channel hygiene
- Newer features (Tasks, Yearbook, Equipment, TimeOff, Chat) follow clean Models/Services/Views — use them as the template

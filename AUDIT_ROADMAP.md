# App Audit Roadmap — July 12, 2026

Source: full 5-dimension audit (security, architecture, data/sync, performance, UX/UI) of the app at commit f7e5c67.
Full visual report: https://claude.ai/code/artifact/4ae6e46a-bc04-4307-b589-ef3233f42e41

**How to use this file:** each phase is a checklist. Check items off as they're completed
(`[x]`), and add a dated note under the phase when it's done. To resume in a new session,
say "continue the audit roadmap" or "start phase N" — everything needed is in this file.

Status: **Phase 1 in progress (2026-07-12).** Code done + committed. Claude proxy DEPLOYED and TESTED working on Focal-Point project. NOT YET DONE: (a) lock-down migration must wait until a new app build is live in users' hands — running it now breaks the current app's roster scanning; (b) rotate Anthropic key; (c) revoke Apple keys + Google key restriction + git history purge. See PHASE1_MANUAL_STEPS.md.

> Phase-level status (which phase is done / in progress) lives in the Phase menu in
> kickoffs/START_A_PHASE.md — that is the status board. This file holds the per-item scope +
> checklists + closeout detail (the equivalent of Focal Grade's docs/REBUILD_PLAN.md).

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

> **CRS.1 CLOSEOUT 2026-07-23** — Captura roster save hardening: all 4 pre-existing loss paths
> from the 6bf00ba post-ship review FIXED (plan: CAPTURA_ROSTER_HARDENING_PLAN.md). W1 own-lock
> entry switch now saves+releases the previous entry (mirrors the normal branch, same ordering);
> W2 sidebar shoot switch saves the in-progress edit against the old roster synchronously in
> onChange(of: shoot.id) then clears editing state (both sidebar set-points verified to funnel
> through that one onChange); W3 capture-mid-typing merges from the live editing text (screen
> can no longer clobber unsent keystrokes; persisted value now always equals what is on screen);
> W4 both files: exhausted save retries now log via RosterEditDiagnostics, alert naming athlete
> + value, and (iPad) revert the optimistic baseline under an entry-identity + attempted-value
> guard so a later blur re-attempts. iPhone twin checks all verified in code as the plan
> predicted (W1/W2/W3 need no iPhone change; W4 is both-files: saveEntry -> @discardableResult
> Bool, lastSavedValues advances only on success at both caller sites). Hook lifted per the
> established procedure with explicit operator authorization mid-session, restored, exit-2
> re-verified on both basenames. BUILD SUCCEEDED (workspace), no warnings from either edited
> file; anchors re-grepped. Two adversarial audits: ZERO critical/high; both independently
> confirmed all 4 paths closed. Residuals recorded (all pre-existing or accepted-by-design,
> report-only): (1) MEDIUM follow-on candidate — a capture landing <=500ms before a sidebar
> shoot switch is still lost for entries NOT being edited (pendingCaptureSaves neither flushed
> nor rescued by W2; same lookup-fails-after-reload mechanism); (2) iPad W4 re-attempt is
> manual (alert) when the failure lands after the user already switched entries — equality
> guard means re-tapping alone won't re-save, user must modify the text; (3) iPhone stopEditing
> ignores the save Bool and clears editing state regardless (value stays on screen via the
> optimistic array write; re-edit + blur re-saves unconditionally); (4) pre-existing off-main
> @State writes on some iPhone failure paths (extends an accepted file-wide pattern). Operator
> smoke pending: the 4 per-item device tests in the plan + the 6bf00ba regression check.
>
> **2026-07-23 operator ruling (post-build):** camera-station capture is NOT used from the
> Captura views in practice — Production Sync is an FP Sports workflow only. The Captura
> views' fpSync/auto-fill code is pre-split legacy (entered both views 2026-03-14, commit
> 1d63bc3, when they were the only sports views; FP Sports later became the real home and
> the Captura copies were frozen in by the protection rule). Consequences: W3's on-device
> test is WAIVED by the operator (the path is double-gated — needs a gallery link + PIN
> connect — and never armed on Captura jobs; fix is correct, build-verified, dormant);
> residual (1) above (capture-vs-shoot-switch debounce loss) lives in the SAME dormant path
> and is downgraded to moot-in-practice — do NOT spend a hook lift on it; stripping the
> Production Sync panel from the Captura views is NOT a standalone phase — it folds into
> the FP Sports parity/retirement deletion of both Captura views whole. Remaining operator
> smoke: W1 (fast entry ping-pong), W2 (shoot switch mid-typing), 6bf00ba regression
> (type, wait 35s, switch, reload).
>
> **2026-07-23 OPERATOR SMOKE PASSED — CRS.1 COMPLETE.** All three device tests passed on
> iPad: W2 (typed digits held across a sidebar job switch), W1 (fast B->A->B entry
> ping-pong, A's digits persisted), and the 35s 6bf00ba regression check. W3 device test
> waived per the ruling above (path never armed on Captura jobs). Also confirmed during
> smoke: the sidebar toggle (top-left of the shoot header) + the sidebar's "< Home" button
> are the working exit path from the iPad shoot view — works as designed, low
> discoverability noted. Awaiting operator push decision.

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

- [x] **Real TabView navigation** (fixes double back buttons + state loss) — NAV.1 SHIPPED
  2026-07-14 (merged + pushed, origin/main 25a16ac) as the foundation; the
  TabView/typed-routes/deep-link modernization stays deferred by plan.
  - Root cause: `MainEmployeeView` wraps everything in `NavigationView` (`:623,668`) + fake string tabs (`TabBarManager.selectedTab` string, 29-case switch at `:872-932`) + fake "< Home" toolbar button (`:944-963`) + `topBarBackOverride` hack (`:938-951`); features open nested NavigationViews (`SportsShootListView.swift:232,293,1095,1344`)
  - Target: `TabView` with 5 role-aware tabs (Today / Schedule / Scan / Time / More), each owning one `NavigationStack` + `NavigationPath`; "More" = searchable grouped grid (26 flat features → ~12 grouped); Hashable route enums + `navigationDestination`; deep links via `onOpenURL` route parser
  - Migrate incrementally: shell first, then feature by feature; replace 102 `NavigationView` uses over time; kill `DoubleColumnNavigationViewStyle` at `SportsShootListView.swift:2018`, `FPSportsRosterView_iPad.swift:2634`
  - NAV.1 CLOSEOUT 2026-07-14 (branch nav-1-restructure, plan NAVIGATION_PLAN.md, family arc
    NAV.1). Fixed the two root causes without the TabView rewrite: removed the shell's global
    NavigationView + the fake "< Home" button + the topBarBackOverride bridge, normalized the
    "" vs "home" router to one canonical "home", and gave every screen exactly one nav bar —
    Home + shell-dependent features each wrapped in one NavigationView(.stack); self-nav features
    (capture, training, unflagUser, tasks, equipment; sportsShoot + focalPointSports on iPad)
    render bare. Profile menu moved off every feature onto Home. HOME REACHABILITY (operator
    decision, three iterations — bottom-bar Home button, then swipe+coach-mark, both rejected):
    FINAL (per-device): iPHONE = no Home in the bottom bar (Scan keeps center); a top-left Home
    button (house.fill) on every feature screen's own nav bar via a shared HomeToolbarButton /
    .homeToolbarItem() (Navigation/HomeToolbarButton.swift) — added once by the shell wrapper for
    shell-dependent features and in-toolbar for the 5 self-nav features (capture, training,
    unflagUser, tasks, equipment). iPAD (no center Scan) = a prominent large center Home button in
    the bottom bar (BottomTabBar.homeCenterButton), top-nav Home omitted there. iPad Sports rosters
    keep their own internal Home + hide the bar (protected file untouched). Drill-in details show
    system Back in that slot. ZERO edits to protected Captura files (SportsShootListView/Detail untouched; only Sports
    edit was removing the 3 override lines in the NON-protected PoserStationView). Build clean,
    self /code-review (high). STILL DEFERRED per plan: TabView shell, Hashable typed routes,
    deep-link onOpenURL, and replacing the remaining ~100 NavigationView uses / the two
    DoubleColumn split-view styles. SHIPPED 2026-07-14: merged + pushed to origin/main (25a16ac).
    Owner verified the iPad Home extensively on-device; a full iPhone nav walkthrough (top-left Home
    on each feature, Back on drill-ins) is a light follow-up if anything surfaces.
- [ ] **Shared RosterEditingController** (highest-value refactor) — ⚠️ CONSTRAINED: `SportsShootDetailView.swift`, `SportsShootListView.swift` and other Captura roster files are PROTECTED (hook-blocked, used by other photographers in production — see protected-captura-files memory). The original plan (retrofit both device views to call a shared controller) is NOT allowed because it requires editing the protected files. Revised approach: only `FPSportsRosterView_iPad.swift` (not protected) can be refactored; any shared logic must live in a NEW file that the protected files are not modified to use. The iPad/iPhone dedup as originally scoped is effectively off the table unless the user edits the Captura files themselves. Still safe: cache `PoserStationView.filteredSubjects` (`:277`, evaluated ~8x/render — PoserStationView is not protected; verify against hook first)
  - DONE 2026-07-12, build-verified. `PoserStationView` confirmed not protected (deny-list empty; not in the protected set). `filteredSubjects` (3 filter passes + O(n log n) sort) now memoizes on a cheap change-signature (subjects' id/updatedAt/isPhotographed + searchText/sortField/imageFilterType + order-independent hashes of activeFilters & photoCountMap) via a `FilteredSubjectsMemo` reference held in @State. Runs once per input change instead of ~8x/render; signature is recomputed each access so it can't serve a stale list. The rest of the shared-RosterEditingController refactor stays off the table (needs protected Captura files).
- [x] **SessionService refetch storm** (`SessionService.swift:90-101,222-240,726-748`): full-org fetch, no date bound, refetched per-subscriber (~10 views) on every realtime event; `recalculateSessionColorsForDate` = 1 UPDATE per session, each triggering more refetches. Debounce, share one fetch, batch color updates into a single RPC, bound query by date range. Also: cache ignores `includeUnpublished` (`:77-83`) → unpublished sessions leak to employees for up to 5 min
  - DONE 2026-07-12, build-verified. Fixed: (1) `includeUnpublished` cache leak — `sessionsCache` is now scope-tagged (`cachedIncludeUnpublished`) and `cacheSatisfying()` never serves unpublished rows to a published-only caller (online + offline + immediate-cache-display paths all filter). (2) Storm — added in-flight fetch coalescing (`inFlightFetches` keyed by `org|scope`) so N subscribers reacting to the same event collapse to one query, plus a 400ms per-subscription debounce so a multi-row color recalc's event-per-row burst collapses to one refetch. Net: `events × subscribers` fetches → ~1. DEFERRED (needs DB migration): batch color UPDATEs into a single RPC, and date-bounding the shared full-org fetch (would fragment the shared cache / change every caller — higher blast radius, felt problem already solved on the read side).
- [~] **Design tokens**: one `FeatureTheme` (three conflicting feature-color maps: `MainEmployeeView.swift:1202`, `AllFeaturesView.swift:249`, `BottomTabBar.swift:492`); static `Formatters` cache with `en_US_POSIX` + org timezone (212 `DateFormatter()` allocs, 73 files, timezone-naive "yyyy-MM-dd" everywhere); `cardStyle()` modifier (83x cornerRadius(12), 48x shadow); restore Dynamic Type in 5 worst files (373 fixed font sizes total)
  - PARTIAL 2026-07-12, build-verified. Created `DesignSystem/DesignTokens.swift` with all three tokens: `FeatureTheme.color(for:)`, cached `Formatters` (POSIX-locale isoDate/isoDateTime/time24 + per-timezone `isoDate(in:)`), and `View.cardStyle()`. **FeatureTheme fully adopted** — the three diverging maps (which disagreed, e.g. dailyJobReport blue-vs-green) now all delegate to it, so the flagged conflict is gone. **DEFERRED as incremental adoptions (not one-shot sweeps):** migrating the 212 `DateFormatter()` sites (changing tz behavior risks shifting day boundaries → wrong-day bugs; adopt file-by-file with verification), adopting `cardStyle()` at the 83 card sites, and restoring Dynamic Type in the 5 worst files (373 fixed sizes — pure layout change, needs per-view visual verification). Infra is in place; these are safe to do incrementally now.
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

## AMB — Ambient design language rollout (arc, registered 2026-07-24)

Per-phase scope and closeouts for the AMB arc. Full plan, decisions D1–D9 and the
lessons carried forward: `AMBIENT_ROLLOUT_PLAN.md`. Status board: the Phase menu in
the start-phase skill (formerly `kickoffs/START_A_PHASE.md`). Family registry row: `~/Brain/projects/registry.md (formerly FocalPointProduction/docs/PHASES.md)`.

This arc is a RESTYLE, not a rewrite — data layers, services, navigation shape and
business rules are out of scope inside a phase (D2). It does not overlap Phase 4's
"decompose god files" item: DEC.1 changes structure, AMB changes presentation. Where
they touch the same file (`DashboardWidgets.swift`), whichever runs first wins and the
other rebases onto it.

- [x] **AMB.1 Schedule** — DONE 2026-07-24, operator smoke PASSED on device (iPhone),
  shipped to `origin/main` (`b3a82e1..97324a4`).
  `ScheduleView` + `ScheduleRows` + `ScheduleStyleKit` replace `SlingWeeklyView`
  (deleted same commit); `ShiftDetailView` restyled with its data layer byte-identical;
  `SessionTypePill` deleted (old detail layout was its only caller). Chosen from five
  prototypes built in a throwaway design lab, which was deleted once the port was
  confirmed (`git show 9d34aea` to recover them).
  **Carried over in full:** realtime session listener, foreground re-subscribe, time off
  + detail sheet, My/All filter, org-wide staffing heat + long-press breakdown,
  publish-a-day, create-session, offline/last-synced state, multi-day day-occurrences,
  job box status, weather, travel planning, coworker + location photos, message crew,
  yearbook, publish, edit, CREW.2 day-pinning on realtime updates.
  **Deliberately dropped:** the week view's per-card weather fetch (keyed off
  `session.location`, hard-coded `nil` in the model — it could never fire; weather still
  works in the detail off school coordinates).
  **Defects fixed that pre-dated the arc:** Yearbook button tested a non-optional for
  `nil` so it showed for school-less sessions; Message crew failed silently when nobody
  had a phone number and looked people up by FIRST NAME rather than user id.
  **Review:** `/code-review` found 8, all fixed — 5 were regressions this arc
  introduced, incl. the org listener never restarting after a pop (froze session-type
  colours and BOTH Publish buttons for the app's lifetime) and `selectDay` chaining
  `with(day:)` onto an already-narrowed occurrence (handed the new day the PREVIOUS
  day's crew, which fed the coworker list and message recipients).
  **Operator-found before that:** dead tap (`navigationDestination` is
  NavigationStack-only; the shell supplies a `NavigationView`), duplicated action
  surfaces, unfindable today marker, scroll stutter (per-cell scans inside a lazy stack
  → per-day index), Message crew, timeline not landing on today.
  **Outstanding:** iPad smoke not run for AMB.1 — D7 (both devices every phase) was
  adopted after this phase shipped. Worth a pass when convenient; not blocking AMB.2.

- [~] **AMB.2 Design system extraction + enforcement gate + the lab** — THREE
  SESSIONS BUILT 2026-07-25, all awaiting the one operator review sitting that
  gates AMB.3. Batch 1 is now complete in the lab: all four surface mockups
  (Equipment, home dashboard, Tasks, Chat) plus the specimen sheet and the
  palette sheet, six entries in the Design Lab gallery.

  **Shipped in session 1:**
  - DesignSystem/ now holds the Ambient vocabulary as app-wide primitives:
    AmbientCard.swift (the one card container, three densities, four edge
    styles, three states), AmbientComponents.swift (badge, pill row, avatar,
    avatar stack, section title, note card, stat tile, empty state) and
    AmbientFoundation.swift (density scale, motion, haptics, the ambient wash,
    deterministic identity colours, flow layout, the iOS 16.6 wrappers).
    ScheduleStyleKit.swift shrank 579 → 218 lines and now holds only what is
    genuinely about a shift: session colour, per-type icons and names, shift
    times, and ShiftStanding.
  - cardStyle() and CardStyle DELETED in the same commit. Verified zero call
    sites app-wide before deleting — the governing fact of this arc.
  - **The gate:** scripts/check_card_drift.py, registered as a PreToolUse hook
    in .claude/settings.json (checked in, travels with the repo). Blocks a
    Write/Edit that would ADD a hand-rolled card; also runs --sweep for phase
    verification and --list to regenerate its allowlist. Starts green BY
    CONSTRUCTION: the allowlist is generated from the rule — 46 files, 101
    cards, zero unlisted. It ratchets (a file may shrink, never grow) so partial
    conversion is never blocked, and non-cards are annotated per site rather
    than exempting a whole file. 30/30 decision-matrix cases pass, including an
    Edit that adds only a shadow line, a card hidden behind a seven-line
    comment, a marker with no reason, and eight fail-open robustness cases.
    31ms on a 5,190-line file. It blocked ME twice during this phase, which is
    the only real proof it works.
  - **The lab (D10):** DesignLab/ — one temporary profile-menu entry, sample
    data, a gallery, a switcher, and AMB.2's specimen sheet. Mounted by PUSHING
    into the Home screen's real NavigationView, never a fullScreenCover with
    its own stack — the L1 correction. Deleted whole at AMB.12.
  - **The specimen sheet** draws every primitive at every density against
    Equipment's REAL row content, and carries a live density switch over a
    24-item list so D5 is decided by scrolling rather than by looking at one row.

  **Four corrections this phase forced on the plan** (detail in
  AMBIENT_ROLLOUT_PLAN.md). The first three came from measuring the codebase,
  the fourth from an adversarial audit of the gate itself:
  1. the stated rule detected the wrong pattern and would have missed the
     shadowless material card — which is the Ambient idiom, and which eight of
     the ten cards this phase converted actually are;
  2. it would have flagged the schedule, the style it exists to promote;
  3. path-level grandfathering alone was too coarse, so there is a per-site
     marker and a per-file count now;
  4. the hook's hardcoded path would have refused EVERY edit on any other
     checkout, because a PreToolUse hook reads exit 2 as BLOCK and python3
     exits 2 on a missing file. Committing the settings file was itself the
     bug. Verified by reproducing it, then fixed.

  **Three deliberate pixel changes in the schedule, all needing operator eyes:**
  time-off rows gained 2pt of padding (14 → 16) to match the shift rows beside
  them; the three stat tiles in the shift detail gained 12pt of inner horizontal
  padding and lost 2pt vertical; and the timeline's "No shifts" chip moved to
  compact (radius 18 → 14, 14 → 12pt horizontal). All three are components that
  now take their spacing from the density scale instead of hand-tuned numbers.

  **Two adversarial audits run before any commit**, one on the extraction and
  one on the gate. The extraction audit confirmed the move is faithful —
  formatters, avatars, pills, standing-to-card-state mapping, the countdown
  card's every number, and the three-file blast radius all verified — and found
  the two padding deviations above, which are kept deliberately. The gate audit
  found the CRITICAL path bug and five real weaknesses; all are fixed or
  recorded. Residuals accepted and named: a shell command that writes Swift is
  not covered by a Write/Edit hook (the sweep is the backstop); a glow that
  varied at runtime would change view identity (documented at the call site, no
  such caller exists); and the ScheduleTimelineRow exception stays hand-rolled
  on purpose, annotated in place.

  **Evidence:** xcodebuild BUILD SUCCEEDED; zero warnings from every new or
  changed AMB.2 file; app installs, launches and renders on the simulator; gate
  sweep clean; old vocabulary re-grepped to zero app-wide.

  **Not verified by me, and only the operator can:** the schedule still looks and
  behaves as it did (it shipped 4 days ago and this phase touched all three of
  its files), and the Design Lab opens from the profile menu and the specimen
  sheet renders. Needs iPhone AND iPad (D7).

  **Raised, not resolved:** the time-tracking surface (~2,540 lines, nine
  screens) is named in no AMB phase. See the Open section of the plan.

  **Shipped in session 2** (2026-07-25): the D11 palette proposed in the lab,
  approved by the operator, and APPLIED to FeatureTheme — all 27 features now
  have a distinct colour where 27 previously shared 11, five of them blue. That
  re-cut is LIVE on three unconverted surfaces the moment it landed: the home
  tiles, the All Features grid and the bottom bar. LabPalette keeps the
  pre-AMB.2 map so the sheet still shows a before and an after. Compact chosen
  as the density for dense lists, settling D5. The home dashboard mockup built
  at a 90% company-blue wash, with its Upcoming Shifts widget using the
  scheduler's colour rather than the position lookup that misses.

  **Shipped in session 3** (2026-07-25): the three remaining batch-1 mockups,
  built from AMB_BATCH1_RESEARCH.md rather than by re-reading the features.

  - **Equipment (AMB.3's D10 gate).** Both tabs, because the app opens on My
    Kits and not on the list — mocking only the list would have gated AMB.3 on a
    screen the photographer never lands on. Kit rows with the tape-colour stripe
    (rainbow included, which a flat `Color(hex:)` renders as garbage), the kit
    detail with its category sections that open COLLAPSED, the equipment list
    with live search and status filters, the real empty state, and the item
    detail. My Kits and the kit detail were NOT in the batch-1 research; both
    were read from MyKitsView, KitCard and KitDetailView before being drawn.
  - **Tasks (AMB.5).** The one surface where Ambient is not a restyle of a card
    but the arrival of one — Tasks has no card, background, radius or shadow
    anywhere today. The mockup draws BOTH and switches between them, so the
    operator decides against the real thing rather than a memory of it. Carries
    a labelled non-restyle proposal: a failure banner, because Tasks has no
    error UI at all and every failure is silent.
  - **Chat (AMB.6).** Conversation list plus the thread, with the three levers
    on scrollback height live: per-message timestamps (what ships today) against
    a stamp only when the conversation paused, grouping a run from one person,
    and a 15pt body against the default 17pt the app rides on. Whose colour
    "mine" is stayed an open question rather than a decision, so it is a switch:
    the company blue against chat's own pink, which under D11 is also the wash
    behind the thread.

  **Two facts found while building session 3, neither of them fixed here:**
  1. Equipment is a SELF-NAV feature (MainEmployeeView.isSelfNavFeature) — it
     builds its own NavigationStack, so the lab's container is not the one the
     real screen gets. Every mockup pushes through `.ambientPush(item:)`, which
     is the one form that works in both, so nothing approved can fail on the way
     out; but AMB.3 still has to decide whether Equipment keeps its own stack.
     Tasks is self-nav too, on a NavigationView — where `navigationDestination`
     is silently ignored, which is the AMB.1 dead-tap shape.
  2. `ambientCard` cannot express a chat bubble: it fills with a material, never
     a solid tint. The bubble is prototyped in the lab (`LabChatBubble`) with the
     gap named at the call site. If bubbles survive review, a tinted fill is
     promoted INTO AmbientCard before AMB.6 converts anything.

  **Evidence for session 3:** xcodebuild BUILD SUCCEEDED; zero errors and zero
  warnings from any DesignLab or DesignSystem file (every warning in the build
  is pre-existing and in other files); card-drift sweep clean; drift audit clean.
  No production screen, service or model was touched — the only file changed
  outside DesignLab/ is AUDIT_ROADMAP.md.

  **Session 3 was then RE-CUT** (10607b0) after the operator's correction: this
  is a redesign, not a restyle, and no feature may be lost. That produced D12,
  which supersedes the plan's opening restyle-only clause.

  - **AMB_BATCH1_PARITY.md** is the re-cut's real deliverable. Every capability
    of the three surfaces, read out of the SOURCE and marked kept / moved /
    added / open. "No feature lost" is worth nothing as a promise; this makes it
    checkable. It caught FIVE things the first mockups had outright wrong, none
    of them stylistic and all of them feature loss: Equipment's CATEGORY filter
    chips missing entirely, its three detail actions drawn as always-present
    when they are conditional on status and ownership, Tasks' Urgent filter
    being "urgent OR OVERDUE" rather than "urgent or high", Tasks' five distinct
    per-filter empty states collapsed into one, and Chat's system messages
    absent altogether.
  - **Equipment** drops the two-tab picker. One screen leads with your gear and
    states how much is out, due and LATE — today the only way to discover
    something is overdue is to read every kit card. The inventory is one row
    behind, or you start typing. The kit detail is a packing list: categories
    open EXPANDED, in the app's own photography workflow order (cameras, lenses,
    lighting, stands, bags), which is real domain logic in the code that an
    alphabetical sort would have destroyed invisibly.
  - **Tasks** groups by WHEN. The sample data carries the proof: a medium-priority
    task that is late, which under today's priority sort lands below four urgent
    ones that are not. All five filters, their live counts, the deliberately
    absent count on All, the status row and the in-group sort all survive; the
    four-tab detail becomes one scroll with every tab's content intact.
  - **Chat** adds date separators and run grouping behind switches, and restores
    system messages, the "No messages yet" italic, and delete-on-groups-only.
  - **Two defects found in my own work before committing:** the conversation list
    is a List rather than a LazyVStack, because `.swipeActions` is List-only and
    on a stack row it compiles, renders and silently does nothing — dead swipes,
    the same class as AMB.1's dead tap; and LabEquipmentRow keeps the assignee at
    compact, since AllEquipmentView passes showAssignee: true.

  **ARC LESSON:** a scope rule about CODE became a ceiling on the DESIGN. Drawing
  today's rows beside the proposal turns an approval into a referendum on the
  status quo. Read the source before redesigning a surface — the research doc
  described how the screens LOOK, which is not what a redesign can drop.

  **Operator approved the batch-1 designs 2026-07-25** ("those all look good,
  lets go with it").

  **Device approval CONFIRMED by the operator 2026-07-25** — the batch-1 mockups
  were reviewed running on iPhone AND iPad. That satisfies D10 and D7, so the
  AMB.2 gate is closed and AMB.3 was cleared to start.

**Batch 1** — mocked in AMB.2, reviewed in one sitting, then converted:

- [x] **AMB.3 Equipment** — BUILT 2026-07-25. One screen replaces the two-tab
  container: your gear leads, with a standing line saying how much you have out,
  how much is due back and how much is LATE (which the app could only tell you by
  reading every kit card), and the whole inventory one row down or one keystroke
  away. Kit detail is a packing list that opens EXPANDED, in the app's own
  photography workflow order. The item detail leads with status, holder and due
  date rather than a 250pt photo.

  **Delete-first, same commit:** EquipmentTabView, MyKitsView, AllEquipmentView,
  KitDetailView, KitCard.swift and EquipmentCard.swift are gone, along with the
  seven badge components their deletion orphaned. Verified by grep: no live
  reference to any deleted symbol remains. Both AMB.3 entries deleted from the
  card-drift allowlist; sweep clean.

  **Three bugs fixed that the redesign made unavoidable rather than optional:**
  tapping an item under "Other Equipment" ran an EMPTY COMMENT and did nothing;
  the empty state's "Browse Equipment" button posted a `SwitchToAllEquipment`
  notification that NOTHING in the app observed, so it was equally dead; and a
  malformed user id fell back to a fresh random UUID, which queried for a user
  that cannot exist and reported "no equipment" instead of a problem.

  **Three feature losses caught in my own work by walking the parity inventory
  against the SOURCE rather than against the approved mockup** — the per-item
  menu on a kit item, the serial number on a packing list, and the year in
  assignment history. All three were absent from the mockup the operator
  approved, and all three would have shipped green. Recorded in
  AMB_BATCH1_PARITY.md, which is the reason they were found at all.

  **Two places the mockup promised more than the data carries** — naming who
  holds an inventory item, and naming people in assignment history — are named
  rather than faked. Both need a new query, and a restyle phase does not change
  the data layer.

  **Known behaviour difference, deliberate:** flipping the old segmented control
  recreated the My Kits view and so refetched. One screen has no tab to flip, so
  the counts no longer refresh as a side effect of navigating. Pull to refresh is
  preserved on every list and is the sanctioned path; adding a reload-on-return
  would be new behaviour, which D2 puts outside a style phase.

  **Evidence:** BUILD SUCCEEDED, zero warnings from any Equipment or DesignSystem
  file; card-drift sweep clean; app installs, launches and stays up on the
  simulator; old-path grep clean.

  **Independent review gate RUN by the operator 2026-07-25, before any push
  (0e24e68).** Four findings, each checked against source before acting:
  - FIXED "0D OVERDUE" — `KitDueState` defaulted `daysOverdue` with `?? 0`, and
    that value is 0 on the due date itself and nil for a status-flagged
    assignment with no return date. The badge it replaced guarded `days > 0` and
    drew NOTHING, which is its own bug. Now optional: a sub-day overdue reads
    "OVERDUE" with no number, and "1 days overdue" is fixed too.
  - FIXED a blank Details card — `specs(for:)` always drew its card and gated
    every row, so an item with only a name rendered a card containing the word
    DETAILS. Mine: the app's section always had content because the status and
    condition badges lived in it, and this redesign moved them to the headline.
  - FIXED `loadMyKitsData` orphaned by the deletion of its only caller. Deleted;
    delete-first covers what a deletion orphans, not only the replaced file.
  - **NOT FIXED, deliberately:** overdue fires at 00:00 on the due date, because
    `EquipmentAssignment.isOverdue` compares against
    `startOfDay(expected_return_date)` — so an item due today is late from
    midnight AND is excluded from "due back". The finding is correct, but it is a
    BUSINESS RULE on the model, it predates this arc, the old kit card turned the
    same rule red, and four things read it. D12 keeps business rules out of a
    style phase; what the app calls "late" is the operator's decision, not one a
    restyle smuggles in. **Follow-on candidate.**

  Also addressed, from the reviewer's flagged uncertainty rather than a finding:
  this screen stacked TWO `NavigationLink(isActive:)` (the deprecated API
  `ambientPush` must use) on one view, and Equipment is the first Ambient surface
  running inside a real `NavigationStack` — two live links competing for one
  stack is the shape of the AMB.1 dead tap. Collapsed to one
  `EquipmentDestination` enum and a single link.

  **OPERATOR SMOKE PASSED on iPhone AND iPad, 2026-07-25 ("all works", "both are
  good") — D7 satisfied.** Exercised: kit card opens the packing list, the
  per-item "…" menu, an item row inside a kit, Browse all equipment, an item in
  the inventory, and the QR button. The push paths work inside a real
  `NavigationStack`, which was the open risk. **AMB.3 is DONE and PUSHED per D8.**

  Two things the smoke turned up, neither a regression:

  - **"Manage Kits" implies a tap it does not have.** Verified PRE-EXISTING:
    `AdminKitTemplatesView`'s rows have never carried a tap target, there is no
    kit-template detail screen in the app, and git confirms AMB.3 never opened the
    file. Operator's call: "leave it, note it". Filed against AMB.12 above.
  - **"Also checked out to you" absent, and correctly so.** The operator has 62
    items out across two kits of 20 and 42 — an exact match, so nothing is left
    over for a section that only ever listed gear belonging to no kit. But
    diagnosing it exposed a real hole, fixed in 87bb442: the counts come from
    ASSIGNMENTS and the rows from matched EQUIPMENT records, and
    `groupAssignmentsByKit` drops an item silently when it is not in the fetched
    inventory — so a total match failure rendered as three numbers above blank
    space. It now says what happened. Same lesson as PUB.1's O5.

    **Consequence worth recording: the dead-tap fix on that section is UNVERIFIED
    on device**, because the operator has no gear outside a kit to exercise it.
    The same code path is covered by the in-kit and inventory item taps, which
    both pass.
- [x] **AMB.4 Home dashboard + the bottom tab bar** — DONE 2026-07-26, operator smoke PASSED on iPhone AND iPad. Original scope (`MainEmployeeView` + `DashboardWidgets`, ~3,600 lines) —
  highest traffic, and its Upcoming Shifts widget currently disagrees with the
  already-converted schedule.

  **iPHONE HALF BUILT 2026-07-25 (`53eac3f`), NOT pushed. Blocked on two operator
  actions: approving the iPad mockup on an iPad (D10), and the smoke (D7).**

  **The finding that reshaped the phase: the iPad dashboard is a DIFFERENT
  SCREEN.** `loadWidgetOrder` picks the widget set by device — iPhone gets Hours,
  Mileage, Upcoming Shifts and Tasks; iPad gets Sports Rosters, Group Jobs and
  Photoshoot Notes. Not a superset; three widgets sharing nothing with the four
  the operator approved in AMB.2. So D10 was unmet for three of the surface's
  seven widgets and a D7 iPad smoke would have smoked an unconverted screen.
  Resolved by D10's own procedure rather than by asking: the three are now mocked
  in the lab (`DashboardIPadMockup`, gallery entry "Home Dashboard — iPad") and
  wait on approval. Found by reading the source for the parity inventory — a
  device-conditional widget list is not something a screenshot can show.

  **Parity: `AMB4_DASHBOARD_PARITY.md`.** Batch 1's inventory never covered the
  dashboard. Writing the missing half found **seventeen capabilities in the app
  and absent from the approved design**, all restored and each verified present
  rather than claimed: the Hours offline indicator, the overtime split and the
  percentage readout; Mileage's month and year dollar figures and its
  "enter via Daily Job Reports" caption; the shift date, weather, refresh button
  and View-all; the Tasks create button, a working checkbox, the detail sheet and
  five rows not three; every loading and empty state; and widget drag-reordering.
  **The inventory itself missed one and the audit caught it** — the Mileage
  pay-period caption, because the line was written about the NUMBER and what went
  missing was its LABEL. An inventory is a check, not a guarantee.

  **Three defects fixed because the conversion made them unavoidable:** nearly
  every shift was drawn BLUE regardless of the scheduler's colour
  (`positionColorMap[session.position]` looked up a session TYPE in a table keyed
  by job TITLES, always missed, fell through to blue — now
  `ScheduleStyle.accent`, so home and the schedule finally agree); pull-to-refresh
  was attached inside the scroll view where a `RefreshAction` cannot reach it;
  and three live `NavigationLink(isActive:)` on one screen collapsed to one
  `HomeDestination` enum behind one `ambientPush`.

  Deleted same commit: `CompactShiftRow`, `CompactSessionRow` (120 lines, zero
  callers) and `PositionColorMap.swift`, orphaned by their removal.
  `MainEmployeeView`'s drift row deleted (2 → 0); `DashboardWidgets` 8 → 3, the
  three being exactly the iPad widgets.

  **THREE audits, and the third — aimed at the fix round — found the phase's
  worst defect, exactly as PUB.1 warned.** The first refresh fix reintroduced a
  permanent spinner through another door (a refresh reached the loading flag, and
  there are paths where the listener never calls back), ignored cancellation so a
  cancelled refresh became a main-actor busy loop, and could orphan a realtime
  channel; and the hours bar drew its "still running" marker over hours already
  banked. The meter is now three consecutive segments, verified numerically over
  fifteen states.

  **Recorded, not fixed:** a size-class watcher that fixes the iPad's stale widget
  set was built and then REVERTED — crossing that boundary swaps four widgets for
  three and those widgets open realtime channels in `onAppear`, trading cosmetic
  staleness for channel churn on the shared DB. Also `ChatManager.cleanup()` has
  never run (`onChange`'s condition compares the already-updated value against
  itself) — **AMB.6 owns Chat**; and the three iPad widgets have weak lifecycles
  (a fresh realtime channel per construction; one with no teardown at all).
  **CLOSEOUT 2026-07-26. Both device smokes passed ("those widgets are fine", "very
  good, it all looks good"); the phase owns NO drift-allowlist rows (MainEmployeeView
  2 -> 0, DashboardWidgets 8 -> 3 -> 0) and its three mockups are deleted.**

  **THE SCOPE GREW BY ONE SURFACE MID-PHASE, and how it was found is the arc lesson.**
  The operator asked why the BOTTOM TAB BAR had not been redesigned. It belonged to no
  phase: the arc's list is organised by FEATURE and the bar is nav-shell furniture on
  every screen, so it matched no entry — and the card-drift gate could not catch it
  either, because a full-width bar is not a rounded filled container. Two independent
  mechanisms for finding unconverted surfaces, both blind to it by construction.
  Operator ruling (D13): it joins AMB.4, with the main screen, before any other
  feature. **Before AMB.5, enumerate the remaining SHELL deliberately — the profile
  toolbar, the theme picker, the toast — rather than waiting to be asked again.**

  **The bar is now a floating glass capsule** ported from the operator's own KeepUp
  app after their first-cut rejection ("hate it, not really any different" — it had
  swapped an opaque slab for a material and changed nothing else). Real Liquid Glass on
  iOS 26 with a custom-glass fallback below it, frost settled at 50% on a slider in the
  mockup, cells that divide the width, a hand-built sliding pill (a material cannot
  animate its position, so the system cannot produce one), and Scan/Home dead centre at
  every item count — which the OLD bar never was on an odd count. Swipe it right to
  tuck it away behind an edge handle; any navigation brings it back. Hide-on-scroll was
  built first and dropped on the operator's own reasoning that navigation matters more.

  **It also closed a three-phase-old mistake.** D11 claimed the AMB.2 palette re-cut
  changed this bar. It had not: FeatureTheme appeared in the file once, inside the
  CUSTOMISE screen, while the bar coloured from a FOURTH hardcoded map that defaulted
  most features to blue. The tile you tapped and the item you landed on disagreed for
  nearly every feature.

  **SPORTS, with explicit operator authorization.** Both rosters stopped hiding the bar
  on iPad, where it had been removed "to maximize vertical space" — leaving the app's
  largest iPad tool with no bottom navigation at all, and on iPad the bar is the ONLY
  route home because HomeToolbarButton is iPhone-only. That is why the roster had grown
  its own Back-to-Home button. The space is still available, now by the user's swipe.
  `CapturaSportsView` is hook-protected: the hook was lifted for that one basename and
  RESTORED, verified byte-identical against a pre-lift backup and a recorded SHA-256,
  then re-tested to confirm it blocks again.

  **Seventeen capabilities were in the app and absent from the approved design**
  (`AMB4_DASHBOARD_PARITY.md`), all restored. An eighteenth — the Mileage pay-period
  caption — was missed BY the inventory and caught by the review, because the line was
  written about the NUMBER and what went missing was its LABEL. An inventory is a check,
  not a guarantee.

  **Defects fixed that the conversion made unavoidable:** nearly every shift on the
  dashboard was drawn BLUE regardless of the scheduler's colour (a session TYPE looked
  up in a table of JOB TITLES, always missing); pull-to-refresh was attached where a
  RefreshAction cannot reach and hid a latch that could strand a permanent spinner;
  three live `NavigationLink(isActive:)` on one screen; a shift detail keyed by session
  id so a multi-day job reused day 1's state on day 2; an orphaned repeating timer; and
  `ChatManager.cleanup()` recorded as never having run (AMB.6's).

  **FOUR OPERATOR SMOKES FOUND FOUR THINGS I COULD NOT SEE**, and the pattern is worth
  keeping: the safe-area inset applied outside a NavigationView did nothing; the same
  applied to self-nav features I had knowingly left for "their own phase"; a parent drag
  gesture losing to child Buttons; and the tucked handle colliding with the iPad
  keyboard's own dismiss key. **I cannot run this surface — the design lab needs a
  signed-in session against the shared Supabase project — so every untested guess spends
  the operator's time. When I cannot see it run, instrument or reason it through BEFORE
  shipping, and never defer a known regression to a later phase.**

  **Review gate: five findings, four fixed, one handed to OFF.1** (home's refresh latch
  releasing on a disk-cache replay — dormant until that arc switches the cache on, and
  every available fix was worse than the bug).

- [x] **AMB.5 Tasks** (18 views, 3,167 lines) — **DONE + PUSHED 2026-07-26. Operator
  smoke PASSED, `/code-review` run before the push.** Its mockup and its sample-data
  block are deleted, matching what AMB.4 did at its own close; the lab keeps the shared
  time helper, which Chat still uses.

  **The review found seven, six fixed, one refused with a reason — and the worst was
  again in the FIX round.** `Save` was writing the sheet's opening snapshot over the
  whole live row, so it reverted any concurrent web-app edit and reliably knocked
  `commentCount` backwards (adding a comment bumps it server-side while the snapshot
  keeps the old number). Save now re-reads and applies only the five fields the screen
  can edit. **This is the same hazard the subtask toggle had already been routed around
  — I fixed one path and left the other**, which is the "fixing the instance is not
  fixing the class" lesson AMB.4 wrote about the safe-area inset, repeating one phase
  later. Also: Save exited edit mode without awaiting, so a failed save looked like a
  successful one (it now stays in edit mode and reports inside the sheet, because the
  list's banner sits behind it); **the failure banner's own Retry was erasing the
  failure it existed to report** — it always re-fetched, and a successful fetch cleared
  the error, so a create that never happened was announced and then silently
  un-announced (failed writes now record a retry closure, and a good read no longer
  clears the banner while a write is outstanding); a subtask double-tap could settle the
  database and the screen opposite each other; a status chip hidden under All was still
  being applied; and `TaskDateFormat` built a DateFormatter per row per keystroke
  instead of using the app's shared `Formatters` cache. REFUSED: chips rendering a
  literal "0" where the old screen hid a zero — that is the approved mockup's behaviour
  and it is informative.

  **A correction to this phase's own evidence, worth keeping because it will recur:** my
  first "zero warnings from changed files" was measured against an already-compiled
  build, so nothing was re-emitted and the check was vacuous. Re-run by touching every
  changed file to force recompilation, which surfaced a real warning. **An incremental
  build is not a warnings check.**

  **THE STRUCTURAL CHANGE: the list is GROUPED BY WHEN.** Overdue, Today, This week,
  Later, No date, inside whatever filter is active, with the app's real sort (priority
  descending, then due date, then newest) kept inside each band. Before this, the list
  was one flat priority-sorted run, so the only way to discover something was LATE was
  to drive the chip bar over to Urgent — which is defined as "urgent priority OR
  overdue", so an overdue medium task sorted below four urgent ones that were not late.
  **The Completed filter is deliberately NOT banded**: a done task with a due date last
  month would sit under a header reading "Overdue".

  **Delete-first, same commit:** `TasksMainView.swift` gone, along with the seven helper
  types it defined (`SearchBar`, `LoadingView`, `TaskRowView`, `TaskListView`,
  `EmptyTasksView`, `TaskFilterChip`, `StatusChip`) and the six the old detail defined.
  Old-path grep clean — the only surviving mentions are prose in comments. `TaskDetailView`
  and `CreateTaskView` keep their TYPE names on purpose: the AMB.4 home dashboard presents
  both, and renaming would have pushed churn into a surface this phase has no business
  touching. Tasks never had a card-drift allowlist row (it had no cards at all); sweep clean.

  **Parity: `AMB5_TASKS_PARITY.md`,** written from the eight source files inward rather
  than from the mockup outward. It caught **four things the approved mockup could not
  carry**, and the first is the AMB.3 lesson repeating exactly:
  1. **Edit mode had lost three of its four editors.** The mockup moved priority and
     status up into header badges and drew only the description editor in its editing
     state, so the priority segmented picker, the status menu picker and the
     estimated-hours stepper all read as display-only. All three restored.
  2. **The toolbar was absent from the mockup** — the lab supplies its own nav bar, so it
     could not show one. Home, the create plus and the Refresh / Clear Cache overflow all
     survive. A mockup scope artifact and a dropped feature look identical at conversion.
  3. **The session NAME is not reachable, so it is not drawn.** `TaskItem` carries only
     `sessionId` — an opaque uuid, no name on the model, no join in `TaskService`. The
     workflow half of "Belongs to" ships real (`workflowName` / `workflowStepName` were
     on the model and rendered nowhere); the session half is named, not faked. Same call
     AMB.3 made about the equipment assignment join.
  4. **Assignee names resolve through `TeamService`** — which already exists, already
     reads users filtered by `organization_id`, and is already used by other screens. A
     presentation join over a service the app owns, NOT a new data path: no schema, RLS
     or PowerSync change, nothing that touches the web app or Captura. Falls back to the
     model's own `assignmentDisplayText`, so the line degrades to "3 assignees" or
     "Unassigned" rather than going blank.

  **Three defects fixed that the redesign made unavoidable rather than optional:**
  a subtask ticked OUTSIDE edit mode was silently thrown away (the checkbox was not gated
  on `isEditing` and mutated a local copy that only Save persisted, and Save only existed
  in edit mode — the four-tab layout hid this behind a tab, the single scroll puts it in
  front of everyone); every refresh added ANOTHER subscription to `TaskService.$tasks`, so
  ten checkbox toggles left eleven live sinks each re-running the merge and rewriting the
  whole disk cache on every realtime delivery; and a new task was created with an
  UPPERCASE UUID, against this repo's own hard rule.

  **TWO ADVERSARIAL AUDIT PASSES, nine findings accepted and fixed, two rejected with
  reasons. THE WORST WAS IN MY OWN FIX ROUND** — which is exactly where PUB.1 and AMB.4
  each found theirs, and the pattern is now three for three. My subtask fix routed through
  `onTaskUpdated`, which writes the ENTIRE task row from `editedTask`, a snapshot taken
  when the sheet opened. So a casual checkbox tap would have silently reverted any title,
  status, priority or assignee change somebody else made in the meantime, **on a database
  shared with the web app** — and the comment directly above the code named
  `TaskService.toggleSubtask`, the targeted call it was not making. **A fix that
  introduces a data-loss path is worse than the dead control it replaced.**

  Also found: the band tested `isDateInToday` BEFORE the past test, so a task due at 09:00
  read at 17:00 filed under a "Today" header while its own date rendered red with a warning
  triangle — the screen contradicting itself about what is late; cached chip counts went
  stale at midnight because two of the four read the clock; the failure banner never
  cleared on a successful load; the comments shown could belong to the PREVIOUS task
  (`CommentService` is a singleton with one shared array — pre-existing, but the redesign
  puts a COUNT on it, turning a flicker into a wrong number); two `Task` blocks wrote
  `@State` off the main actor; priority went completely invisible in the Completed filter
  (the mockup gated the glyph on not-done, which compounded with the approved spine
  removal); "Created" vanished on tapping Edit; the task title vanished on scroll; and the
  subtask plus was decoration rather than a button.

  **Numeric UI verified ARITHMETICALLY, not by eye** — AMB.4's lesson. Two throwaway Swift
  harnesses ran 22 date/count cases, including the proof that the band and
  `TaskItem.isOverdue` now agree on every single one, so the "Overdue" header and the red
  styling can no longer disagree. Both harnesses deleted at the end of the phase.

  **ONE FIX REVERTED ON PURPOSE, and it was mine.** I changed `ToastView` to clear the
  floating tab bar on the strength of arithmetic that was wrong: its 50pt padding and
  `TabBarMetrics.clearance` of 84pt are not measured from the same datum (plain padding on
  an overlay versus a safe-area inset), and the toast grows upward from it. The audit then
  found the part that settles it — two of the three call sites are shell-wrapped features
  that ALREADY receive the shell's 84pt inset, so the change would have double-counted for
  them. `ToastView` is now behaviourally identical to HEAD with a comment recording exactly
  what is and is not known. **Shipping an unverified layout change to app-wide chrome is
  the precise mistake AMB.4 made four times, and every wrong version of it built cleanly.**

  **Deliberate deviations from the approved mockup, named rather than silent:** the
  priority glyph is NOT hidden on completed rows (see above); the navigation title is the
  task's own title rather than a static "Task", because the header card scrolls away; the
  type badge shows only when the type is not `.general`, since every task the app creates
  is general and a badge reading "General" on all of them is noise; the mockup's 96pt
  bottom padding is replaced by `tabBarClearance()` inside the screen's own container,
  because the two would have doubled; `StackNavigationViewStyle` is pinned, matching the
  shell's own convention and the mockup's detail; and the mockup's sort was shorthand
  (priority then id) where the app's real three-key sort ships.

  **`CreateTaskView` is RESTYLED, not redesigned** — it was never mocked, and D10 is a hard
  gate. It gets the wash, a transparent Form background and the feature tint; every
  section, control, binding and validation is untouched. Real input design is AMB.7's.

- [x] **AMB.6 Chat** (20 views, 4,655 lines) — **CONVERTED + DATA LAYER REPAIRED
  2026-07-26. Commits de1eed5..58c4299 (9). NOT PUSHED — see the two unmet criteria
  at the end of this entry.**

  **THE PHASE FOUND A FEATURE THAT HAD NOT WORKED SINCE SEPTEMBER 2025, and the
  operator authorised repairing it rather than restyling over the top.** The
  screens are converted; the bigger half of the phase was underneath them.

  **THE ROOT CAUSE, and it is not the one I first proposed.** The conversations
  query could NEVER succeed: `.contains("participants", value: [userId])`
  interpolates a Swift array's raw value, which is a POSTGRES ARRAY literal
  `{uuid}`, sent against a JSONB column — so Postgres answered `invalid input
  syntax for type json` every single time. Verified live: that form errors, and
  the correct `["uuid"]` returns six real conversations. The SAME malformation
  was in the realtime filter, where `cs` is not even an operator Realtime
  supports, so no conversation change ever arrived either.

  **It was invisible because the failure was reported as an EMPTY LIST.** The
  subscribe path caught the error and published `[]`, so the screen said "No
  conversations" with only a console print. It surfaced the moment this phase
  made a failed fetch say so — the operator's smoke showed the real error, and
  the fix followed from it. **A failure that is presentable as an empty state
  will hide for a year.**

  **Ten other data-layer defects fixed** (full list in the commit for de1eed5):
  the thread showed the HUNDRED OLDEST messages and a message you sent never
  appeared; "Load earlier" paged the wrong direction; a realtime event discarded
  paged history; opening a conversation showed the PREVIOUS one's messages (the
  CommentService shape AMB.5 told this phase to look for — it was there); a
  failed send destroyed the message and the typed text; `cleanup()` had never run
  once, and once its call site was fixed it turned out not to unsubscribe
  anything either; image and file upload were hard-coded to fail AND their caller
  discarded the result; iOS never raised anyone's unread count.

  **`last_message` was a real bug but a SECONDARY one** — execution never reached
  the decoder. It is a TEXT column, and the two apps write different shapes into
  it; every production row holds a stringified LEGACY FIREBASE object with
  `senderId` in camelCase and a Firestore `{_seconds,_nanoseconds}` timestamp,
  which no `Codable` path could read. Now parsed by hand for both key spellings
  and three timestamp shapes, proved with a throwaway harness over the real
  production strings and deleted.

  **TWO LIVE SHARED-DB CHANGES, applied and verified 2026-07-26:**
  `chat_unread_increment.sql` and `chat_attachments_bucket.sql` (no chat bucket
  existed in either app; scoped per CONVERSATION so a private DM's files are not
  readable company-wide). **The RPC's first version contradicted its own header** —
  it argued against the web app's read-modify-write and then did one; it is a
  single statement now. Its negative test also found the guard was `<>` against
  `auth.uid()`, which yields NULL and therefore SKIPPED the check rather than
  failing closed. **All five pre-existing chat RPCs share that flaw — reported,
  not changed.**

  **A MISTAKE WORTH THE RECORD: I tested a mutating RPC against a REAL
  conversation and incremented three people's unread counts.** Undone by
  decrementing exactly that delta and confirmed back to zero.
  `fix_chat_rpcs.sql`'s own header says its behavioural test was "rolled back so
  nothing persisted" — that precedent was in front of me. Later tests ran inside
  a transaction that rolls back.

  **THE FIX ROUNDS THEMSELVES NEEDED THREE PASSES, and each pass introduced
  something.** Round one shipped a critical (an attachment filed against the
  wrong conversation, and a cache write that poisoned another thread's history).
  Round two "fixed" the cache write by testing a value captured BEFORE the
  network round trip — fixing the instance, not the class, for the fourth time in
  this arc — and introduced a MESSAGE-LOSS path by restoring failed text only if
  the composer was still empty. Round three fixed both and the unread badge.
  **Auditing my own fix round found the worst defect every single time, five for
  five now** (PUB.1, AMB.4, AMB.5, and twice here).

  **Parity:** `AMB6_CHAT_PARITY.md`, read from the source. The mockup-is-not-an-
  inventory lesson held for the FOURTH straight phase — four losses, the worst
  being that `AmbientEmptyState` has no action slot, so Chat's "New Conversation"
  button silently ceased to exist while the inventory recorded it as kept. Fixed
  in the shared component, so every future surface gets the slot.

  **Step 3b earned its place again:** every GIF was forced to a 250x250 square
  ("Square aspect ratio for most GIFs"), which stretches every landscape GIF.
  Restored to the mockup's 200x140.

  **AmbientCard gained `AmbientCardFill` and an `AmbientDensity.bubble`** (12/8/16,
  the mockup's numbers verbatim). `.bubble` is excluded from `allCases` so it
  cannot be chosen as a list density. Chat now owns NO drift-allowlist rows.

  **TWO ACCEPTANCE CRITERIA ARE NOT MET, and the phase is closed with them named
  rather than quietly:**
  1. **iPad smoke NOT RUN.** D7 is explicit that a phase is not done when only
     the iPhone passes. iPhone passed 2026-07-26 (conversations load).
  2. **BATCH-2 MOCKUPS NOT BUILT.** D10 assigns Reports family + Time off to this
     phase. They move to the START of AMB.7, which needs them before it may touch
     a real screen anyway. **AMB.7 must build them first, or D10 blocks it.**
  Consequently the batch-1 mockup and `AMB_BATCH1_PARITY.md` / `AMB_BATCH1_RESEARCH.md`
  are **NOT deleted** — a validation reference outlives the port it validated, and
  the iPad half of that port is unconfirmed (the GRP.6 lesson).

  **CHAT NEEDS A DATA-LAYER REBUILD, and it is a MULTIPLATFORM one:
  `CHAT_REBUILD_NOTES.md`.** Every defect above is two clients disagreeing about
  the same column — participants as a jsonb blob with no foreign keys, unread as a
  stored number both apps read-modify-write, message type guessed from the message
  text. The fix is to move truth INTO the database (a participants join table,
  unread DERIVED from a per-person `last_read_at`, writes through RPCs) so no
  client can contradict another. It needs its own arc, the architecture gate, and
  the web app read properly first — plus a real answer on whether Captura touches
  chat, which is currently an inference and not a fact.

**Batch 2**

- [x] **AMB.7 Reports family** — SHIPPED + PUSHED 2026-07-27. **OPERATOR SMOKE PASSED ON
  iPHONE AND iPAD ("all works"), closing D7 and D10 for batch 2.** Seven screens converted, TEN files deleted in the same commit:
  DailyJobReportView, MyJobReportsView, EditDailyJobReportView, CustomDailyReportsView,
  TemplateFormView, PhotoshootNotesView, LocationPhotoAttachmentView, the ORPHANED
  TemplateReportListView, plus UIComponents.swift and JobNotesView.swift, which the
  conversion orphaned. Nothing runs in parallel.

  **THE DESIGN IS IMPORTED, NOT MATCHED — and that is the answer to the operator's
  question about building it exactly as designed.** Every converted screen draws with
  `Reports/ReportFormKit.swift` and runs `ReportRules.swift`, `ReportSchoolLink.swift`
  and the new `ReportOptions.swift`: the SAME files the lab's mockup uses. There is no
  copying step, so there is nothing to drift. The lab's private copies of the 22 job
  descriptions and 12 extra items are deleted — `DesignLabSampleData` forwards to
  `ReportOptions` — so the mockup and the real screen cannot disagree about what a
  photographer may tick. `scripts/test_report_rules.sh` compiles and RUNS those real
  files: **104 checks**, up from 44, with every new rule fix proved to FAIL without it.

  **THE ORPHANED SCREEN'S CAPABILITIES MOVED INTO THE LIVE ONE.** TemplateReportListView
  was 558 lines, compiled, shipped and unreachable, and it held the search, date filter,
  grouping, badges, empty state and retry that MyJobReportsView — the list a photographer
  can actually open — did not have. All of it is in ReportsHomeView now, which also leads
  with the question the surface never answered: have I filed today's report yet.

  **THE PARITY WALK RAN NINE TIMES**, 103 capability checks against the NEW screens,
  once after every round, before showing the operator anything. That is the standing
  rule and it held: nothing in the inventory was lost across eight rounds of churn.

  **THE CONVERSION ITSELF WAS STABLE FROM THE FIRST COMMIT.** Worth separating from the
  churn above: seven screens, ten files deleted, the executable rules and the shared
  components have not needed a correction since b5679dc. Every one of the eight fix
  rounds was data-layer plumbing on ONE screen, and five of the eight were one loop.

  **TEN AUDITS, EIGHT FIX ROUNDS, RUN UNTIL ONE CAME BACK CLEAN.** Three adversarial passes (correctness/
  concurrency, data integrity, design fidelity) found 40+ real findings. The audit of
  the FIX round found a CRITICAL one the fix itself had introduced: the report's
  note-photo list derived from the thumbnails that had downloaded, so a failed download
  dropped a photo silently and submitting before they landed dropped all of them — and
  submit deletes the note, so they had nowhere else to be. The audit of the SECOND fix
  round found a DIFFERENT photo-loss path in the same code: the attached note can leave
  the shared blob it was being resolved through (submitted or deleted on the notes
  screen), and its photos went with it, unsaid.

  **AND THEN IT KEPT FINDING THEM.** Eight fix rounds. Rounds four through eight were
  ALL in one feedback loop — the warning that tells a photographer when a route could
  not be measured — and each one fixed the instance rather than reasoning through the
  state machine. The low point: a round whose commit said it cleared state "in both
  early returns" had put the clear on the UNCONDITIONAL path, which made the branch it
  was protecting unreachable and turned an accurate 9.1 into a submitted 0.0 on the
  exact sequence the round was named for. **The lesson is not "be careful": it is that
  a fix must be judged by reading what the code DOES, not by trusting the edit — and
  that a feedback loop is a STATE MACHINE, to be enumerated once rather than patched
  five times.** The tenth audit walked every transition and came back clean.

  **REGRESSIONS THE CONVERSION INTRODUCED AND FIXED:** a session resolved its school by
  NAME only (the deleted form preferred `school_id`, deliberately) so a renamed school
  put no school on the report and mileage silently went to 0.0; a failed refresh in the
  school picker EMPTIED the school list the report resolves ids through, erasing every
  school on the report; a required template `file` field became satisfiable by zero
  photos; the photo-loss message was raised on a screen the shell was tearing down; and
  the picker built a `SchoolItem` from a DIFFERENT column than the report screens,
  degrading the address a route is measured from and caching it.

  **DEAD OR LYING CONTROLS FIXED, because the redesign made them unavoidable:** a
  required file field and an untouched optional number field each made a template
  permanently unsubmittable; multiselect and radio ignored readOnly; a field that was
  both basic and smart rendered twice; a date field snapped back to today; the custom-
  reports empty state was unreachable and a transient failure hid templates the user
  already had; the editor rewrote `your_name` from AppStorage on every update — the
  column the manager drill-down queries by; the editor invented three scan answers on
  load; Update could write defaults over a record that failed to load; a failed delete
  was invisible; and editing a template report rewrote `report_type` to "standard" on
  the shared table.

  **RECORDED AND DELIBERATELY NOT FIXED**, each named in the file that carries it, all
  needing the data layer: an edit cannot clear a field (R10); the submitted-notes fetch
  cannot succeed and would drop every row if it could (R1/R2/R3/R8); a location-photo
  upload can wipe a school's existing photos (R7); the two mileage engines disagree
  (R22); the already-reported lookup is keyed on FIRST NAME (R25).

  **THE EDITOR WAS NEVER MOCKED**, and that is named rather than slipped in — the
  mockup's rows pushed nowhere. It gets the approved components applied to the same
  fields, and no structure the operator has not seen. Its vehicle now takes the two-step
  the create form always had.

  Card-drift sweep clean, all five AMB.7 rows deleted (MileageReportsView and
  RoutePlannerView were mislabelled AMB.7 by the generator and are retagged AMB.9 —
  **the route planner belongs to no phase in the list at all**, the same shape as the
  bottom tab bar in AMB.4). `/security-review` found no new HIGH or MEDIUM.

  **`/code-review` RAN (operator, 2026-07-27) AND FOUND TWO REAL REGRESSIONS AFTER TEN OF
  MY OWN AUDITS** — the session link derived from a live array instead of held, so a
  refresh filed `session_id` as NULL; and `ReportSchoolLink.set` reordering the route when
  a source was re-pointed at its own school, which changes the mileage. Both were in the
  seam where three screens' duplicated logic was consolidated: my audits kept checking the
  logic I had WRITTEN and never asked what the deleted code HELD that the new code merely
  computes. Fixed, plus the four the review named without formally reporting (a required
  toggle blocking Submit while showing a valid "off"; a Delete button reading its report
  from state the alert may have cleared; future-dated reports under "This Week"; an
  in-flight lookup not invalidated). The audit of THAT round then found the toggle fix had
  opened a data gap, and the audit after it found the repair was UNREACHABLE on every
  template the web app builds — a JavaScript/Swift truthiness mismatch found only by
  reading the OTHER repo. **The audits that found the most left this repo.**

  **THE LAB SCAFFOLDING IS DELETED** now the smokes have passed — both Reports mockups,
  286 lines of their sample data, and their registry entries. The TIMING is the rule: a
  validation reference outlives the PORT it validates, not the phase that built it, so it
  is kept while the port is still being checked and removed the moment it is not (GRP.6
  deleted a lab while its port was still pending and had nothing left to diff against).
  Nothing real went with it — the 22 job descriptions and 12 extra items live in
  `Reports/ReportOptions.swift`, which the APP builds and the lab merely forwarded to.
  The lab keeps AMB.2's specimen sheet and palette and AMB.8's Time Off set; the whole
  harness goes at AMB.12.

  One question the phase did not need but the roadmap flagged: whether the org's
  `session_types` match the 22 job descriptions. The approved v3 design prefills nothing
  from them, so nothing depended on the answer.

- [x] **AMB.8 Time off** (8 views, 3,763 lines) — SHIPPED 2026-07-27, fifteen commits
  88d01a1..fb46e32. **OPERATOR SMOKE PASSED ON iPHONE AND iPAD**, closing D7. Mockup
  built + approved on iPhone 2026-07-26; `/code-review` run TWICE by the operator.

  **NINE FIX ROUNDS, TWELVE AUDITS, AND EVERY SINGLE AUDIT FOUND A REAL DEFECT.** Four
  of the worst were payroll bugs I introduced while converting: a deleted double-submit
  guard (96 hours debited for a 48-hour request), a PTO field frozen at zero for every
  web-created request (paid days off, nothing deducted), a deny confirmation lost and
  then fired stale on an unrelated sheet, and a FAILED approval reporting "Request
  approved successfully". The recurring shape was fixing the instance an audit named
  rather than sweeping the class — three of four call sites, four of five presentation
  surfaces — and each round the next audit found the one left behind.

  ⚠️ **BATCH-3 MOCKUPS NOT BUILT.** The source inventories for Mileage/Stats and
  Groups/Yearbook were gathered in this session but are not yet a repo document.
  Named as unbuilt rather than half-done, the same call AMB.6 made.

  **FIVE SURFACES CONVERTED:** My Time Off, the approvals queue, the request form
  (create and edit, one form), the detail sheet, and the PTO balance.

  **THE DESIGN LIVES IN PRODUCTION CODE AND THE LAB IMPORTS IT** —
  `TimeOff/TimeOffKit.swift` owns the shared card, the balance lead, the chips, the
  rows, the failure banner and panel. The mockup's own 145-line copy of the card is
  DELETED, along with the lab's private `LabTimeOffStatus` / `LabTimeOffReason`
  vocabularies. AMB.7's mechanism, applied again: there is no copying step, so
  there is nothing to drift. `TimeOff/TimeOffRules.swift` is SwiftUI-free and
  `scripts/test_timeoff_rules.sh` compiles and RUNS it — **121 checks**, and every
  rule was proved to fail when broken (nine mutations, each reverting one rule in a
  scratch copy). `scripts/parity_timeoff.sh` is the parity walk as one command:
  **144 checks against the NEW screens**, re-runnable every fix round, and itself
  proved able to detect a loss.

  **THE AUDIT THAT LEFT THE REPO FOUND THE MOST, for the second phase running.**
  Reading the web app's time-off code turned up three defects invisible from either
  side alone: the two clients share **ZERO reason strings** (web writes "Vacation",
  iOS writes "vacation", so every web-created request drew a grey "Other" — and the
  approved card design leans on the reason icon as its fastest read); **web denials
  stamp the APPROVAL columns** and leave `denied_by`/`denied_at` NULL, so the card's
  `if let name, let date` dropped the denial reason with the attribution; and
  `partially_approved`, which the web really writes, rendered as an orange
  **"Pending"** badge with live Edit and Cancel on an already-decided request.

  **AUDITING MY OWN WORK FOUND THE WORST DEFECTS — EIGHT PHASES RUNNING, and this
  time BOTH were payroll bugs I introduced.** (1) I deleted the double-submit guard
  without noticing: the old screen swapped the list for a spinner on `isLoading`, I
  changed the test to `isLoading && requests.isEmpty`, which is never true on a
  screen that has rows. `usePTOHours` is a read-modify-write over a 300-second
  cache, so two taps on a 48-hour request debit 96 hours. (2) My edit-mode seeding
  froze the PTO hours field at zero, because **the web app always writes a number,
  never null**, so `isUserEdited: ptoHoursRequested != nil` was always true —
  editing a web-created request submitted `pto_hours_requested: 0`, and approving
  it granted paid days off with nothing deducted. The old rule tested the VALUE and
  was memoryless; my state machine replaced it with a sticky flag and lost the zero
  case.

  **RECORDED AND DELIBERATELY NOT FIXED — TOF.1 owns all of it**, because a style
  phase must not move an authorization boundary in either direction:
  the approvals screen still has no permission check; a PTO shortfall still does
  not block submission; `TimeOffDetailView`'s ownership test still reads a
  `UserDefaults "userID"` key nothing writes, so a photographer cannot cancel their
  own time off from the calendar and a manager who sees the button gets a 403.
  **Consequence for the smoke: a missing Cancel button on the detail sheet is
  PRE-EXISTING, not a regression from this phase.**

  **FURTHER NON-STYLE FINDINGS, recorded not fixed** (each needs the data layer or
  a cross-client change, and several are new to this phase's research):
  - `organizations.pto_settings` — the web writes **snake_case** keys, iOS decodes
    **camelCase**. Only `enabled` matches, so every accrual rate, cap and rollover
    an admin configures is silently ignored on iOS, which falls back to hardcoded
    defaults that happen to equal the web's seeded ones. Invisible until an org
    changes a value.
  - **Approving or denying on the WEB never releases `pending_balance`** — the web's
    entire PTO write surface is dead code (zero callers), so an iOS-submitted PTO
    request actioned on the web leaves the hours reserved permanently.
  - `pto_balances.used` is written by nobody — iOS drops it on every update and the
    web never touches it. The "Used This Year" tile was REMOVED rather than pointed
    at it, because that would swap a wrong number for a differently wrong number
    that looks authoritative on a payroll screen.
  - iOS writes `"underReview"`; the web only ever matches `'under_review'`. An iOS
    "Put in Review" request disappears from the web calendar and from every tab of
    the web approval queue.
  - `TimeOffService` inserts `UUID().uuidString` — **uppercase** — as the row id,
    against the project's lowercase-UUID rule.
  - Sign-out does not clear `TimeOffService.currentUserId` / `currentOrgId`, so
    signing in as a different user in the same app run can subscribe to the
    PREVIOUS organization.
  - `checkForConflicts` declares an empty array, loops the date range doing
    nothing, and returns it — the whole "Schedule Conflicts" section was
    unreachable and is deleted. `blocked_dates` exists on the web and iOS never
    honours it; these are the same unbuilt idea.

  **Card-drift sweep clean, both AMB.8 rows deleted.** Worth keeping: PTOBalanceView,
  TimeOffRequestView and TimeOffDetailView carried four hand-rolled containers
  between them and had NO allowlist rows, because the gate matches a rounded FILL
  and they used `.background(Color…)` + `.cornerRadius(…)`. An empty allowlist row
  still means nothing about whether a surface is converted.

**Batch 3**

- [x] **AMB.9 Mileage + Stats (+ Route Planner)** — SHIPPED + PUSHED + CLOSED
  2026-07-30 (origin/main c7ffc42..ccb0716). Smoke PASSED both devices;
  /code-review run: 8 findings, 7 fixed, 1 reasoned won't-fix (web-side date
  convention). The three mockups deleted at close; MileageKit/RoutePlannerKit/
  StatsKit + the two executable rules scripts are the living design.
  **2026-07-29 — BATCH-3 MOCKUPS BUILT (all five: Mileage, Route Planner, Stats,
  Class Groups, Yearbook), in the lab on iPhone AND iPad, awaiting the operator's
  review sitting (D10 blocks conversion until then).** The inventory is
  `AMB_BATCH3_PARITY.md`, written source-inward BEFORE the mockups. Its headline,
  VERIFIED live on the signed-in simulator and against the live DB: **the
  Statistics screen has never rendered** — it selects `daily_job_reports.start_time`
  / `end_time` and `schools.value`, none of which exist, so every tab hides behind
  "Error Loading Data"; the Weather chart is hardcoded fake data; total mileage is
  double-counted; the trends chart only knows the literal names John/Sarah/Mike.
  Open for the operator at the sitting: (1) approve/reject each design; (2) where
  the ROUTE PLANNER lands (tagged AMB.9 by the drift-gate generator, belongs to no
  phase); (3) whether AMB.9 may repair the two broken stats queries + the
  double-count so the redesigned screen ships REAL numbers (data-layer, needs the
  D12 exception the way AMB.6's chat repair got one).
  **2026-07-29 LATER — DESIGNS APPROVED, CONVERSION BUILT AND ON MAIN (2fff568),
  NOT PUSHED; awaiting operator smoke.** The sitting approved all five designs,
  folded the Route Planner into AMB.9, and sanctioned the stats repair. Mileage
  (root + toolbar-edit detail), Route Planner (pushed preview, honest failures,
  surfaced skips), and Statistics (REBUILT — first render in the screen's
  existence, live-verified on the simulator) all converted; the design lives in
  MileageKit/Rules, RoutePlannerKit, StatsKit/Rules, which the lab imports.
  Executable rules: test_mileage_rules.sh (101 checks/12 sabotage-proofs),
  test_stats_rules.sh (104/14). Drift rows deleted, sweep clean. THREE
  adversarial audit rounds + three fix rounds to convergence; headline finds all
  fixed pre-ship: a lowercased id turning ~98% of payroll edits into silent
  no-op 200s (every write in DailyJobReportService now proves a row changed or
  throws), rates pinned to defaults after one failed fetch, a lowercased org-id
  lookup against the mixed-case Firebase org id, chip-tap races, the silent
  zero-row delete. STILL OPEN to close the phase: operator smoke both devices
  (the trip-edit persistence check matters most — only a device can prove it),
  operator-run /code-review before push, then mockup deletion (validation
  reference outlives the port). Named, not changed: Manager Mileage's own
  period anchor AND its four hand-rolled currency spellings (both AMB.12's
  screen — `Formatters.currency` is the one spelling, and the dashboard widget's
  copy of it was deleted in the review round), monthly day-29/31 anchors (no live
  org is monthly), the section-level stats gate, and the web app's 177
  evening-instant report dates (a WRITE-side fix in the web repo — see
  AMB_BATCH3_PARITY.md §6).
  **2026-07-30 — /code-review ROUND: 8 findings + 7 cleanups fixed, 4 reasoned
  won't-fix.** The UTC-midnight one-day class is now FIXED rather than named: the
  app has ONE date convention — the STORED DAY (the UTC prefix of
  `daily_job_reports.date`) — held by `MileageMath.storedDayCalendar` and the
  `Formatters.storedDay*` formatters, so a trip stored 2026-08-01T00:00:00Z reads
  "Fri 1", lands in August's tile, and Mileage agrees with Statistics. Also fixed:
  the period query's GMT-formatted bounds (one trip counted under two chips), the
  widget cache persisting never-fetched zeroes, a failed pay-period load silently
  drawing the hardcoded 2/25/2024 grid, the home widget's spinner with no failure
  exit, and the vehicle label's `?? .personal` round-trip on the save path.
  Reasoned won't-fix: promoting chips/failure cards/loading states into the design
  system and the route enum round-trip (both AMB.12's consolidation), the
  prove-can-fail perl regexes, and re-concurrency of Mileage's load chain.
  **2026-07-30 — WRITE-GUARD SWEEP CLOSED (f9200cc, smoke passed).** The follow-on
  the review round named: `YearbookShootListService` case-folded ids against
  all-mixed-case Firebase ids (50/50 live rows), so every yearbook item toggle,
  note and image-number save was a silent zero-row 200 — folds dropped, and the
  `requireRowsWritten` guard now covers every update/delete in
  YearbookShootListService, TimeTrackingService, PTOService, TimeOffService and
  SessionService (live column case verified per table; all hold mixed
  populations, so no fold can be right). Deliberate exceptions: the offline
  clock-out outbox drops a gone-row op loudly instead of wedging the FIFO queue;
  the session color-recalc loop stays unguarded (concurrent delete harmless).
- [x] **AMB.10 Groups + Yearbook** (17 views, 4,504 lines) — closes batch 3 and mocks
  batch 4. **Mockups already built 2026-07-29 (see AMB.9 note above)** — AMB.10
  starts at conversion once its designs are approved in the same sitting.
  **2026-07-30 — BUILT, COMMITTED, pending operator smoke + /code-review before any
  push.** Both features converted to the approved batch-3 designs; the design lives in
  `ClassGroupsKit.swift` / `YearbookKit.swift` (the lab imports them, so the mockups
  and the screens cannot diverge) and the logic in `ClassGroupsRules.swift` /
  `YearbookRules.swift`, run by `scripts/test_classgroups_rules.sh` (66 checks / 15
  prove-can-fail) and `scripts/test_yearbook_rules.sh` (93 / 23). Delete-first:
  `AddClassGroupView.swift` (both duplicate forms → one `ClassGroupFormView`) and
  `YearbookItemRow.swift` (row → kit, sheet → `YearbookItemDetailView`) deleted; the
  dead recursive `fullScreenSlate()`, the placeholder yearbook create sheet, the
  empty "Mark All Required Complete", the global `EmptyStateView`, and the
  tap-anywhere slate dismissal are gone; old-path greps clean; drift sweep clean.
  **Approved fixes shipped:** the year on job cards; the session date + job-level
  notes on the detail; note bodies on rows; whole-row tap; slate keeps its school
  name from the form path; failed loads/deletes/saves/toggles all SAY SO (the
  empty-state-hides-a-failure law applied to both features); yearbook filters
  compose with search; category counts are of the whole category; the 0% bar is no
  longer red; the REQUIRED chip inverted to a quiet Optional badge; the raw session
  UUID dropped; the un-scrollable year picker scrolls; the session-entry sheet
  distinguishes "no list" from "couldn't load".
  **FIVE audit rounds to convergence (rounds 1–4 all found real defects; round 5
  clean-but-cosmetic).** The fix-round law hit again — my own round-1 fixes
  produced the worst finding (a stale toggle that would have stamped a fabricated
  photographer attribution) and round 3's count guard inverted round 2's. The
  terminal shape: `toggleItemCompletion`/`updateShootListItem` now RETURN what they
  wrote (flag + stored count) and the VM mirrors the observed values — inference
  replaced by observation — plus a per-item in-flight guard. Two deliberate
  one-line service exceptions, recorded: `ClassGroupJobService.error` clears on
  successful fetches (it gained its first reader and had no exit), and the yearbook
  org subscription's failed fetch publishes NOTHING instead of an empty list (it
  could clobber a good list with []). Delete confirmations resolve rows at swipe
  time against the rendered array (an IndexSet held across an alert gap deletes the
  wrong job after a realtime re-sort). Reasoned won't-fixes: hero shows STORED
  counters (matches root card + web; live drift 0/50); checklist still never
  subscribes to realtime (pre-existing, recorded); cache-first staleness under the
  new Retry (service cache, D12); haptic-before-write on the checkbox
  (pre-existing shape).
  **Batch-4 mockups BUILT and registered** (JobBox 1725 / Settings 925 / Manager 634
  / Training 676 lines; gallery grouped Foundations / Batch 3 / Batch 4; sample data
  +386 lines incl. the live job-box status distribution). 50 PROPOSED captions; the
  operator's review sitting owns TWO new rulings: job-box "Flag for Attention"
  (writes to three columns that DO NOT EXIST — grow the schema or delete the
  affordances) and the iOS↔web `StatusColors` contract (three disagreeing colour
  maps). ManagerMileageView deliberately NOT re-mocked (its inventory is batch 3's;
  see the mockup's caption). `AMB_BATCH4_PARITY.md` (2,469 lines, live-DB verified)
  is the parity contract for AMB.11/12; headline findings include the phantom
  `records.photographer` column (four dead SD-card capabilities), the dead
  `FlaggedStatusView` (a flagged photographer cannot respond), sign-in proceeding on
  a failed profile fetch, and the time-tracking surface (10 screens) still owned by
  NO phase — operator decisions, not design ones.
  **Verified:** clean-derived-data builds green throughout; zero warnings from any
  file this phase wrote; both simulators driven signed-in (iPhone: Groups
  list/detail + Yearbook root/checklist on live data; iPad: dashboard-widget →
  create-sheet contract, Yearbook root, batch-4 gallery).
  **2026-07-30 — SIMULATOR SMOKE RUN (operator-directed), including the WRITE
  paths, all self-reverting and DB-verified clean afterward (0 test rows left):**
  yearbook toggle round-trip (attribution "Jason Wilkey · Jul 30" stamped
  immediately, hero 9→10→9 of 26, ring 35→38→35% — the observed-count mirror
  proven both directions); filters+search compose live (typed "Cross" survived
  the Incomplete tap; composed no-matches state with Clear Filters); Groups
  create→add-row→delete-row→delete-job round trips in TWO vocabularies (a
  Candids job and a Groups job): per-type badge icons live (camera on CANDIDS),
  "1 group"/"1 CLUB" singulars, grade chips fill the field, the whiteboard shows
  the school name from the form path, survives a center tap, and the typed note
  survives the whiteboard round-trip; the saved row appears instantly (the
  reload fix) with the note body on it and no dangling dash; both delete
  confirmations carry the preserved copy. **ONE DEFECT FOUND BY THE SMOKE, FIXED
  (81ac9ce): a deleted job's card stayed on the list** — the write landed (DB
  verified) but the success path trusted realtime, and Supabase DELETE events
  never reach a column-filtered subscription (payload carries only the PK), so
  the refetch never fired. Success now refetches; re-verified live
  (create→delete→card gone at the confirm). NOT simulatable, left for the
  operator's device smoke: the Airplane-Mode failure states, haptics/feel, and
  the batch-4 design review sitting.
  **2026-07-30 — OPERATOR /code-review ROUND (d3f4b76): 8 finder angles, 13
  deduped candidates, 1-vote verification — 8 CONFIRMED findings, ALL FIXED.**
  The worst was this session's own smoke fix (fix-round law, again): rebuilding
  the org subscription on delete success re-joined the SAME channel object while
  its leave-ack was in flight, which supabase-swift resolves by de-registering
  the instance — org realtime permanently deaf until screen re-entry (verified
  against the vendored SDK source). Deletes now remove the row from the
  service's published array; no channel is touched. Also fixed: the group row's
  missing .contentShape (the yearbook row's own on-device fix, unapplied to its
  sibling); zero-row write guards + a throwing miss on the three class-group
  row writers (AMB.9's sweep provably SKIPPED this service — not among
  f9200cc's five files, not a recorded exception); the failure-banner +
  empty-state double render; job cards restored to real Buttons (VoiceOver /
  Switch Control could not open a job at all); the yearbook root's double
  full-org fetch per appearance (now first-appearance-only); reloadJob now
  fetches ONE row by id (new fetchClassGroupJob(byId:)) and surfaces
  job-not-found; Cancel stays live during saves in both sheets. REFUTED by
  verification, for the record: the "checklist torn down mid-edit by a failed
  refetch" claim (the realtime catch publishes nothing). Deferred to AMB.12
  with the existing consolidation list: the chip / failure-card / loading /
  search-field / primary-button duplications the review's reuse angle
  enumerated across the six converted kits, and a shared prove-can-fail
  harness for the six rules scripts. Verified after the fix round: build
  green, 66+93 rule checks, sweep clean, create→delete round trip re-run live
  on the signed-in simulator, zero test rows left in the shared DB.

**Batch 4**

- [x] **AMB.11 Job box / NFC** (18 views, 5,373 lines) — **SHIPPED + PUSHED + CLOSED 2026-07-31.** *(History below: the progress meter
  slice is DONE, SHIPPED and PUSHED 2026-07-29.** The rest of the surface is untouched, so
  the phase stays open.

  Closed out of order because the operator looked at the shift detail and said the job box
  bar read "funky". It did — the connector was positioned with constants
  (`.padding(.leading, 20).offset(x: 24)`) inside columns that flex to fill the width, so on
  a 402pt iPhone the line started at the dot's CENTRE and ended 6pt short of the next, and on
  an iPad it detached from the dots entirely (both measured, the iPad one on device).

  **But the cosmetic bug was not the real one.** `job_boxes` is an APPEND-ONLY SCAN LOG —
  every scan INSERTs a row, there is no update-status path in either client — so the rows for
  a box ARE its history. Both screens ignored that: each took ONE row, turned its status into
  a number, and ticked every stage below it. Live counts over the 351 boxes carrying a shift:
  199 Packed-only, 47 Packed+PickedUp, **35 walking all four**, 31 going Packed straight to
  Turned In, 22 skipping one, 11 more across six shapes including four never packed at all.
  **Ten per cent walk all four stages**, so a box scanned twice was drawn with four ticks —
  the screen asserting two scans that do not exist.

  Shipped: `JobBox/JobBoxProgressRules.swift` (SwiftUI-free, 60 checks via
  `scripts/test_jobbox_progress_rules.sh`, six rules each proved to fail without their fix)
  and `JobBox/JobBoxProgressMeter.swift` (the scrubber). **Two old bars deleted in the same
  commit** — the shift detail's stepper plus four helpers and three `@State` fields, and the
  manager tracker's private copy with a DIFFERENT colour map, which is why two screens
  described one box differently. Old-path grep clean.

  Two rules make a meter honest and both are tested: **position is not completeness** (fill
  shows where the box IS; each stage's notch shows whether a scan exists), and **a box is a
  reused object so progress means the CURRENT TRIP** (cut the log at the last Packed, because
  the manager tracker groups by box number across all time and June's trip would otherwise
  merge with October's).

  Also fixed: the crew card credited "Has the job box" to whoever scanned LAST, so it kept
  crediting the person who had RETURNED it (now `holder`, nil for packed and turned-in); a
  second box on one job is no longer silently hidden; PUB.1 redaction moved to reading-BUILD
  time so every consumer is redacted by construction.

  **THE PROCESS LESSON, and it cost three rounds: a rejection tells you the DIRECTION, not
  the DISTANCE.** Round 1 offered four variations on the existing stepper and led with one
  captioned "smallest change from today" — rejected as "almost identical to what i have that
  looks wonky", which is D12 for the third time in this arc and the same failure the bottom
  tab bar had in AMB.4. I over-corrected in round 2 and deleted the meter entirely — "not
  really liking any of those. I do want some sort of progress meter though." Round 3's four
  real meters (ring / block bar / filling crate / scrubber) landed; the operator chose the
  scrubber. **Never lead a set of options with the status quo** — AMB.2 already recorded that
  trap and I walked into it anyway.

  Fix-round audit of my own diff caught two before commit: the notification handler read
  `userInfo["boxNumber"]`, which `notify_job_box` deliberately stopped sending (the PSH.1
  defect class, verified against the live trigger source); and the manager tracker built each
  box's HISTORY from the search-FILTERED rows, so searching a photographer's name dropped the
  photographer-less Packed row and drew Packed as "never scanned" because of what was typed
  in a search field.

  Operator smoke PASSED 2026-07-29 ("works perfect"); iPhone and iPad both driven in the
  simulator against live data first. The lab mockup and its gallery entry were DELETED at
  this close. **Left unverified and recorded rather than claimed:** the push-notification TAP
  handler's optimistic append — push DELIVERY was verified, but the tap gesture could not be
  driven reliably from the simulator tooling. The primary live-update path is Supabase
  realtime and is unchanged. `/code-review` was NOT run; the operator chose to close without
  it, and this work touches no schema, RLS, auth, PowerSync or Captura path.

  **2026-07-30 — THE REST OF THE SURFACE BUILT (0d8c43d, committed NOT pushed).** All 18
  views converted to the approved batch-4 design per `AMB_BATCH4_PARITY.md` Part One; both
  batch-4 sitting rulings implemented: **Flag for Attention built for real** (additive
  `flagged`/`flag_note`/`flagged_at` in `supabase/drafts/20260730_amb11_jobbox_flag_columns.sql`
  — the classifier blocked live DDL, so the OPERATOR APPLIES IT; writes prove rows matched,
  a box reads flagged from its current trip via `JobBoxFlagRules` (25 checks), tracker shows
  badge + note + unflag) and the **one job-box color contract** (packed periwinkle #6B7FD7 —
  no grey — green reserved for Turned In; StatusColors' disagreeing job-box map DELETED,
  `JobBoxTripStage.meterTint` authoritative, `STATUS_COLORS_DOCUMENTATION.md` rewritten as
  the iOS↔web contract; web follow-on owed, incl. the stale root `status-colors.json`).
  One chrome (rail + 3 nested NavigationViews deleted), registered scan color, tappable
  alert banner → Search deep link, honest no-NFC/no-writer states, real
  loading/empty/failure+retry everywhere, in-sheet titles/validation/error surfaces, session
  choice unified WITH a No-session row (D12 kept the old "None" capability),
  `NFCRoutingRules` centralizes 3001/rings/12h-threshold (50 checks; both SD advance
  variants modeled explicitly — unifying them needs an operator ruling).
  **Two adversarial audits + a fix round + follow-ups: 30 findings, 24 fixed, 6 reasoned
  won't-fix** (global stats empty state per mockup; duplicate supplementary history fetch;
  WriteNFC success-invalidate alert race — pre-existing, device-only; single "Manual Entry"
  title; per-section→global empty coherence; F3 kept deliberately: Photographer Activity now
  obeys the Time Frame chips, documented at the call site). The worst finds: sheet write
  failures surfaced NOTHING (the dismiss-reload erased the only error channel — in-sheet
  cards now), and the searchable school picker could display one school while saving another
  (component-level resync; "Iconik" verified a real active school row live).
  **Simulator smoke (live data): iPhone full pass** — all five tabs, tracker, edit sheet's
  record-scan → observed-row mirror → Search swipe-delete round trip, DB read back clean
  (0 test rows); deep link + its un-stick fix verified; iPad reach via All Features
  confirmed to the feature list (the Scan ROW's dispatch did not fire in the simulator —
  shell device-conditional territory, §0.18/§0.19, AMB.12's; verify on the operator's iPad).
  **2026-07-31 — flag SQL APPLIED by the operator and read back (all three columns live).
  Operator /code-review ROUND (f7a2c94): 8 finder angles, ~40 candidates, 11 verified,
  8 findings (6 CONFIRMED correctness, 1 efficiency, 1 PLAUSIBLE edge) — ALL FIXED.**
  The worst was this phase's own flag feature one layer deeper: under an active TEXT
  search the tracker picked each box's summary row from the search-FILTERED rows while
  flag read/unflag cut the current trip from the full log — a flag could land on a
  pre-trip row, invisible and unclearable (the search now decides only which boxes are
  LISTED, never which row represents one). Also: Manual Entry's session pre-select
  silently re-packing a mid-trip box (pre-existing, the sibling form's guards
  replicated); the failure card hiding a loaded list; the 30-day copy lying under Today
  + the number-search promise made TRUE (server-side box_number filter, unbounded —
  VISIBLE CHANGE: number search reaches past 30 days); refresh bypassing cancellation
  (publish generation token); the whitespace-note dead-but-live flag CTA; the
  settings-only dismissal reload; nil flagged_at copy. Cleanups: the copied users.id no
  longer lowercased on the tracker insert (the UUID-case rule), the org-blind "Iconik"
  comment corrected, stale columns-don't-exist comments updated. Review surfaced two operator questions;
  ONE IS NOW RULED AND BUILT (2026-07-31, 8434aa8): flags are visible to EVERYONE —
  red warning card + badge on the job-box scan sheet, Manual Entry and Search rows,
  same current-trip read as the tracker via a shared helper; full lifecycle verified
  live (flag → warning → unflag → 0 flagged rows). Still parked for AMB.12: flag/unflag has
  no server-side permission gate (org-RLS only — the same posture as the whole surface,
  TOF.1's class). Deferred consolidations recorded for AMB.12: primary-button/list-row/
  session-section/pickup-orchestration duplication, jobBoxStatusRing deriving from
  JobBoxTripStage, JobBoxStatsRules extraction, JobBoxDTO retirement, refcounted
  listener store replacing the generation token, settings-slider publish debounce.
  **2026-07-31 — OPERATOR SMOKES PASSED BOTH DEVICES ("smokes pass"). SHIPPED +
  PUSHED (origin/main 3b97d36..12c5a45); AMB.11 CLOSED.** The mockup, its gallery
  entry and its 181-line sample-data block were deleted at the close per the AMB.7
  rule; the design lives in `NFC/JobBoxKit` + `JobBox/JobBoxProgressMeter`/`Rules`/
  `JobBoxFlagRules` + `NFC/NFCRoutingRules`, with 154 executable rule checks
  standing in for the awkward states the mockup used to show.

  **THREE OPERATOR RULINGS ARRIVED DURING THE CLOSE, and all three are the same
  lesson — the operator asked for the ACTION, not the view of the problem:**
  (1) *"anyone should be able to see that so that everyone knows not to use it"* —
  flags went from manager-only to app-wide (scan sheet, Manual Entry, Search rows),
  one shared current-trip read; (2) *"why cant i do it by hitting the alert and
  having an option?"* — the Job Box Alert banner stopped being a filtered-Search
  shortcut and became a "Left-behind boxes" sheet with **Mark Turned In** per box,
  which immediately did real work (the operator's two months-old strays, unscannable
  because the boxes had been reused, were cleared — one from his device, one live
  from mine, both DB-verified); (3) *"im not a big fan of this tab bar and how it
  wraps"* — the five pills went to ONE line, selected-shows-its-name, wrapping now
  impossible by construction. **Generalizable: an alert that names a problem should
  carry the fix.** Decision cards in `~/Brain/decisions/` (2026-07-31 ×2).

  **A PROCESS FAILURE WORTH THE SAME WEIGHT:** the operator's smoke file still said
  "run AFTER applying the flag SQL" hours after he had applied it, and its items were
  plain bullets he could not tick. I swept the roadmap and the code comments when the
  gate cleared and skipped the ONE file whose only audience is him. **When a gate
  clears, sweep every file that mentions it — operator-facing first, not last.**

  NFC hardware paths (reader/writer tag branches, the TAG-vs-NDEF entitlement
  question) remain device-only checks, now covered by the operator's passing smoke on
  real tags. Still parked for AMB.12: server-side permission gating on flag writes
  (org RLS is the only boundary today, the whole surface's posture — TOF.1's class),
  the web app rendering job-box flags + adopting the colour contract (and the stale
  root `status-colors.json`), and the consolidation list above.
- [x] **AMB.12 Settings, Manager, Training + the shell** (~7,700 lines) — the tail, converted per D9.
  Closes the arc and deletes the lab harness + its menu entry.

  **THE SHELL, enumerated at the start of AMB.5 as D13 required: `AMB_SHELL_INVENTORY.md`.**
  Five surfaces belong to NO phase and carry no allowlist row, so both discovery
  mechanisms read clean over them: `ToastView`, the home profile toolbar
  (`MainEmployeeView.homeProfileToolbar`), the appearance picker (`themePickerSheet`), the
  whole sign-in surface (`SignInView` / `ForgotPasswordView` / `ResetPasswordView` — which
  EVERY user sees first), and the launch state (`RootView`'s bare `ProgressView`, on screen
  for up to its own ten-second deadline). Where these land is the operator's call, exactly
  as D13 was. **The generalisable part: an empty allowlist row means nothing about whether
  a surface is converted** — the allowlist answers "which files hand-roll a card", and
  Tasks had no row because it had no cards, not because it was done. And the gate is
  structurally blind to a Capsule, which is what the toast is.

  **Carried in from AMB.3's smoke (operator, 2026-07-25): "Manage Kits" implies a tap
  it does not have.** `AdminKitTemplatesView`'s rows are a plain `HStack` —
  no `onTapGesture`, no `NavigationLink`, no `Button` anywhere in the file except
  the toolbar's Done and the alert's OK — sitting in an `.insetGrouped` List, which
  is what makes them read as tappable. Nothing is broken and AMB.3 never touched
  the file: there is no kit-template detail screen anywhere in the iOS app for a tap
  to reach, and `EquipmentService` has no kit-template write method at all (only
  `getKitTemplates`), because templates are authored in the web app — which the
  screen's own empty state says. **Operator decision: leave it, note it.** When this
  phase restyles the screen, the cheap fix is a footer stating templates are managed
  in the web app, so the list stops implying an action. Making kits genuinely
  tappable is a FEATURE (a detail screen, and write methods against the shared DB if
  editing is wanted) and belongs to its own phase, not to a restyle.

  **SCOPE SETTLED 2026-08-01 BY OPERATOR RULING (plan D15), at this phase's kickoff.** The
  two surfaces that had belonged to no phase since AMB.2 were both put in front of him,
  because AMB.12 was the last phase in which they could be answered:

  - **THE FIVE SHELL SURFACES FOLD IN HERE.** `ToastView`, the home profile toolbar, the
    appearance picker, the whole sign-in surface and the launch state are AMB.12's. His
    reason was the recommended one: they inherit most of their look from the primitives, and
    leaving them out would have left THE FIRST SCREEN EVERY USER SEES as the only unconverted
    screen in the app.
  - **THE TIME CLOCK DOES NOT.** Ten screens, 2,662 lines, seven payroll write paths with one
    confirmation between them — it becomes **AMB.13**, running after this phase, so payroll
    gets its own design sitting and its own smoke instead of sharing the tail's.
  - **THEREFORE THE LAB DOES NOT DIE HERE.** D10 had the harness deleted "at the close of
    AMB.12" — written when AMB.12 was the last phase. AMB.13 needs the harness to design the
    clock screens against. The lab, its menu entry, its sample data and every surviving mockup
    die at the close of AMB.13 instead. **The generalisable part: a deferral moves the end, so
    anything scheduled to die "at the end" has to be re-checked in the SAME change as the
    deferral** — not discovered later by the phase that needs the deleted thing.

  Full card: `~/Brain/decisions/2026-08-01 the time clock gets its own phase, the furniture
  ships with the tail.md`.

  **CLOSED 2026-08-01 — OPERATOR SMOKE PASSED ("smoke passes"), shipped + pushed
  (origin/main 52ee152..).**
  /code-review RUN and closed before the push (see the review round at the end of this entry). Settings (13 screens incl. the four auth screens), Manager Features
  (flag, unflag, employee detail, ManagerMileageView), Training (2 screens + its components),
  and the five shell surfaces. Build clean, zero new warnings; drift sweep clean and every
  AMB.12 allowlist row deleted. Both simulators driven on live data.

  **THE DESIGN.** Built to the batch-4 mockups the operator approved 2026-07-30. Design lives
  in production kits — `SettingsKit`, `AuthKit`, `ManagerKit`, `TrainingKit` — plus the arc's
  consolidations, which is the half AMB.9 and AMB.10 both deferred here: `AmbientControls.swift`
  now owns the loading row, failure card, chip, button, stat line, search field and nav row.
  All three approved mockups had privately redeclared the SAME four of those, which was the
  third independent signal after two review rounds asked for it.

  **WHAT WAS BROKEN AND IS NOW FIXED** (the tail's headline is that almost none of this was
  cosmetic):
  - **Sign-in proceeded when the profile fetch failed** (G1) — empty org id, role defaulted,
    no permissions loaded, every org-scoped screen then guarding out to blank, which reads as
    an app with no data rather than a failed sign-in. It now refuses, says so, and signs the
    half-session back out. The LAUNCH path had the same hole and is fixed the same way.
  - **ENTRY HAD TWO DECIDERS, and that is the lesson.** `RootView` entered the app whenever a
    Supabase session appeared, so the sign-in fix could be overruled by the shell mid-flight:
    the user would land in the dashboard for an instant and be bounced back to a BLANK sign-in
    screen with the explanation destroyed. Entry now has exactly one owner per path. It also
    fixed a copy lie nobody had connected to it — `signUp` flips the same flag, so "Account
    created successfully. Please sign in." described something that never happened.
  - **A bad password-reset link produced no UI at all** (G3) — the error was set and the sheet
    was never presented, so tapping a dead link did nothing. Verified live on the simulator
    via `simctl openurl`.
  - **Opening Settings started a second realtime subscription** (G16). `TabBarConfigurationView`
    took an `@ObservedObject MainEmployeeViewModel` to read ONE constant array, so Settings
    constructed a second copy of the app's main view model — whose init registers a foreground
    observer that re-subscribes the session listener. The list is `static` now and nothing is
    injected.
  - **The toast sat ON the floating tab bar** at one of its two call sites, swallowing taps for
    three seconds — and the bare site is the one that fires on every successful daily report.
    Its padding was measured from the host's bottom edge and the two hosts do not have the same
    one. It no longer depends on its host. Also: the first toast's timer used to dismiss the
    second toast's message.
  - **Log out had no confirmation, no destructive role and no error path** — the failure was
    swallowed to a `print`, so a sign-out that did NOT happen looked exactly like one that did,
    while `signOut()` is what purges local PII. On a shared iPad that is a retention failure.
  - **Training was blank on iPad** — a bare `NavigationView` splits at regular width and the
    whole screen collapsed into a hidden sidebar. Pre-existing; found by driving the iPad.
  - **A failed fetch rendered as an empty state** on six screens, three of them manager- or
    payroll-critical. `AmbientFailureCard` exists because of that, and every converted screen
    now distinguishes "nothing here" from "we could not ask".
  - Training's Save/Share **crashed on legacy rows** with an empty image list; the counter and
    thumbnail strip read a column that defaults to 0, so genuinely multi-image critiques drew
    as single photos; "Image saved to Photos" reported the DOWNLOAD finishing, not the save.
  - `SchoolDetailView` re-queried the **half-typed school name** on every keystroke (G7), and
    renaming a school still silently orphans its history — now warned, in the words the join
    actually implies.
  - Photo delete **removed the row from the UI before the write** — a failed delete lost the
    photo from screen and kept it in the database.
  - The 1Hz timer leak in `AllFeaturesView` (K5), four hoisted reducers over a 5,000-entry
    buffer running per body pass (G19), and Metrics' Export handing the share sheet a path
    whether or not the file existed (G13).

  **CONSOLIDATIONS DONE:** three identical `UIActivityViewController` wrappers under three
  names became `Components/ActivityShareSheet.swift` — the important one was `ShareSheet`,
  declared in YEARBOOK and consumed by TRAINING, a cross-feature dependency that a rename in
  someone else's phase would have broken at compile time. Two copies of `applyAppTheme()` with
  different bodies became `Utilities/AppTheme.swift`, and the two dead statements one of them
  carried (an "AppleInterfaceStyle" UserDefaults write and a system-looking notification that
  nothing reads or observes) went with the merge. Three verbatim copies of the coordinate
  validator became `Utilities/CoordinateString.swift`. The photoshoot-notes org flag's
  three-id list had three hardcoded homes and now has one.

  **NAMED, NOT FIXED, and deliberately:** three `parseCoordinateString` copies in
  `TemplateService`, `ShiftDetailView` and `RouteOptimizerService` are LOOSER than the shared
  validator (no finite or range check), so repointing them would change behaviour on shipped
  travel and route code — that needs its own change, not a consolidation sweep. `CreateAccount`
  still inserts the users row with a user-typed `organization_id` and a client-supplied role
  (G2/G4) — server-side concerns. `ForgotPassword` still sets "sent" on both branches, which
  is an enumeration-safety posture, not a layout. `ManagerMileageView` keeps its own 2/25/2024
  fortnight anchor; the window is now LABELLED rather than reconciled, because making the two
  engines agree is a data-layer change (AMB.13's, with the clock).

  **`NSPhotoLibraryAddUsageDescription` was missing from `Iconik-Employee-Info.plist`**, so the
  add-only Photos request presented the full-library prompt with the full-library description.
  Added — and at first this closeout recorded that the fix could not travel, because the file
  was gitignored with no template.

  **THE OPERATOR ASKED WHETHER THE KEYS SHOULD BE THERE AT ALL, AND THE ANSWER WAS NO — THE
  IGNORE RULE WAS WRONG (2026-08-01).** The plist has never held an API key. Every sensitive
  entry in it is a BUILD VARIABLE — `$(SUPABASE_ANON_KEY)`, `$(GOOGLE_PLACES_API_KEY)`,
  `$(CLAUDE_API_KEY)` — resolved at build time from `Config.xcconfig`, which is the file that
  holds the real values, is correctly ignored, and has a committed template beside it. **Every
  version of the plist in the repo's history was checked: none ever contained a literal secret**,
  so nothing leaked and nothing needed purging. It had been tracked until a cleanup commit swept
  it up alongside `Config.xcconfig`, and the ignore rule was written from the file's NAME rather
  than its contents ("Info.plist with API keys" — the keys are labels).

  **It is tracked again.** What ignoring it cost is the general point: that file is not
  configuration, it is app BEHAVIOUR — every permission prompt a photographer reads, the
  `iconik://` scheme the password-reset deep link depends on, background modes, orientations,
  ATS exceptions. Unlike `Config.xcconfig` it had no template, so a fresh clone could not
  reconstruct it and no change to it ever appeared in review. `GoogleService-Info.plist` stays
  ignored — that one was checked too and DOES hold literal values.

  **Generalisable: an ignore rule is a claim about a file's CONTENTS, and it decays.** This one
  was true of a sibling file and was never true of this one; it went unquestioned for months
  because nothing forces an ignore rule to be re-read. Verify the claim, not the filename.

  **DESIGN-SYSTEM SHARP EDGE FOUND ON A DEVICE, documented at the source:** `AmbientFlowLayout`
  bare inside an `HStack` is measured with an unspecified width, reports a single long line,
  then wraps below the frame its parent reserved — so it EATS ITS NEIGHBOUR'S TAPS. On Training
  the layout toggle beside the filter chips opened a critique instead of switching to a list.
  Every production call site was checked; all the others sit in a VStack. The warning is at the
  layout because the failure is silent and presents as a dead tap, not as a wrong picture.

  **THE SECTION-HEADER MISS, worth recording because only the simulator caught it:**
  `.listStyle(.plain)` PINS a `Section` header, so the converted heading in All Features floated
  over the cards scrolling under it. The build was clean, the sweep was clean, the code read
  fine. Titles are rows now.

- [ ] **AMB.13 The time clock** (10 screens, 2,662 lines) — added 2026-08-01 by the ruling
  above. Closes the AMB arc and deletes the lab harness.

  `TimeTrackingMainView`, `TimeEntryListView`, `SessionSelectionView`, `NotesInputView`,
  `CustomClockOutView`, `ActiveClockInEditView`, `ManualTimeEntryView`, `EditTimeEntryView`,
  plus the two DEAD ones (`TimeEntryDetailView`, `TimeTrackingButton` — zero call sites,
  and `TimeTrackingButton` nonetheless holds 2 drift-allowlist rows, so the gate is guarding
  dead pixels). Inventory, states, literals and the K1-K22 defect list are already written:
  `AMB_BATCH4_PARITY.md` §2.4. **Needs a lab mockup and an operator design sitting first** —
  it is the one surface in the arc that never got one.

  **Why it is not a restyle.** The seven payroll write paths have exactly ONE confirmation
  between them (Delete). `AllFeaturesView`'s toolbar capsule creates or closes a payroll
  record in one nav-bar tap with no session, no notes and no confirmation. `HoursWidget`
  swallows both its clock-in and clock-out errors to a bare comment, on the path the source
  itself calls the app's primary way in and out of a shift. A fetch failure renders as "No
  time entries for pay period" — payroll appearing to be zero. And there is a real ceiling
  conflict: manual creation caps at 16h, editing at 24h, and the server enforces 16h, so an
  edit the form accepts is rejected on Save.

  **Carried in from AMB.12:** the four AMB.12 drift-allowlist rows that are actually
  time-tracking files (`SessionSelectionView` 1, `TimeEntryListView` 2, `TimeTrackingButton` 2,
  `TimeTrackingMainView` 2) stay allowlisted through AMB.12 and must reach zero here. The
  hardcoded `2/25/2024` 14-day pay-period anchor is shared with `ManagerMileageView`; AMB.12
  labels the window rather than changing the arithmetic, and reconciling the two engines is a
  data-layer change that needs its own ruling.

### FLG.1 — FLAGGING A USER HAS NEVER WORKED (FIXED 2026-07-28 — OPERATOR SMOKE PASSED
2026-07-28, "it all worked": manager flag delivered end to end on device)

- [x] **The defect.** `TeamService.flagUser` wrote `is_flagged`, `flag_note` and `flagged_by`
  to the SHARED `public.users` table. **Only `is_flagged` existed.** PostgREST rejects a
  statement naming unknown columns, so the UPDATE failed *as a unit* — `is_flagged` was never
  set either. No user has ever been flagged, on any build. The iOS app was fully built to
  consume all three: `MainEmployeeView` selects them for the signed-in user and renders a red
  wash plus a banner naming who flagged them, and both the banner and the inline card require
  `flag_note` to be non-empty — so even a working `is_flagged` alone would have produced a red
  screen with no explanation.

- [x] **Scope note, from the operator mid-session.** This is NOT PSH.2. That heading is eight
  unrelated items parked at the end of PSH.1 and is not a phase scope; it is left untouched
  above and stays reserved for the notification-coverage work (six push types that still
  cannot fire: chat, clock-in, clock-out, daily report, photo critique, job box).

- [x] **Fixed:** `20260727_flg1_user_flag_columns.sql` (additive `flag_note` + `flagged_by`)
  and `20260727_flg1_user_flag_notification.sql` (`trg_user_flagged_notification`). Both
  APPLIED LIVE and read back. Blast radius checked rather than assumed: **the web app has no
  user-flagging feature at all** — every `flag` in its `src` is an unrelated boolean — so the
  columns are iOS-only and additive.

- [x] **PSH.1's flag trigger could not be "recovered".** The operator asked for it to be
  restored from `36fdf3f^` rather than rewritten. It is not there, at that path or any other:
  `git log --all -S"trg_user_flagged_notification"` and `-S"notify_user_flagged"` return no
  migration in either repo, and d61d475's own message says "The migration is deleted rather
  than left to be applied by someone else." It was applied live and never committed. What WAS
  recovered is the payload PSH.1 intended, from the `sendFlagNotification` function deleted
  from `FlagUserView.swift` in that commit — same title, type and data, same note as the body.

- [x] **The trigger was verified by FIRING it** — the lesson PSH.1 paid for, since plpgsql
  does not validate field references until run time. In rolled-back transactions: ordinary
  profile write queues **0** http requests, a genuine flag **1**, re-touching a flagged row
  without changing the note still **1**, a re-flag with a new note **2**, a 5000-char note
  capped to exactly **300**, title read back as `You've Been Flagged`, and a deliberately
  raising trigger body left the flag write intact — proving the `EXCEPTION WHEN OTHERS`
  handler. **That does NOT prove delivery**: the rollback discarded the queued requests, so
  reaching a real device is the operator's smoke test.

- [x] **Three adversarial audits. The fix-round audit again found the phase's worst defect —
  eighth phase running.** Narrowing `SELECT *` on `users` (needed because the moment the
  columns existed, every employee's flag note began shipping to every employee's device) had
  been applied to `TeamService` and **not** to `SupabaseChatService.getOrganizationUsers`,
  which runs on chat init for everyone. Fixed at both sites. The same audit caught a false
  claim in my own comment — that the column list was the only control. **It is not a security
  boundary**: any signed-in employee can still read `flag_note` straight from PostgREST. The
  column list only stops the app routinely broadcasting it. Corrected in place.

- [x] **A bug I nearly shipped applying this repo's own rule.** I added `.lowercased()` to the
  flag write per the lowercase-UUID rule, then checked the live data: of 40 users, one is a
  28-character mixed-case legacy Firebase uid. Lowercasing would have matched zero rows, and
  a PostgREST UPDATE matching zero rows *succeeds*. Reverted, with the reason written into
  the code. The rule is about uuids; `users.id` is `text` and is not all uuids.
  (CORRECTED by the FLG.2 audit: I called that row "an active admin". Its stored values do
  say role=admin/is_active=true, but it has **no auth.users row** — an orphan duplicate of
  the accounting account that cannot sign in. It can be a flag *target*, never an actor. The
  do-not-lowercase rule stands, and no regression either way, but the dramatic framing was
  wrong.)

- [x] **`flagUser`/`unflagUser` now throw when no row was updated.** Before FLG.1 the missing
  columns produced a 400 and a red error; making the columns exist would otherwise have
  converted that loud failure into a green "flagged successfully" for every case that changes
  nothing. This is not hypothetical — see the RLS finding below.

**TWO THINGS FOUND THAT NEEDED AN OPERATOR DECISION — both decided and FIXED 2026-07-28
(operator: "can you fix both of those? allow managers to flag people"):**

- [x] **AUD.2 — the cross-tenant `audit_log` read is CLOSED.** All ten partitions now have
  RLS **enabled with no policy** (default deny on direct access); reads through the parent
  keep using `audit_log_select` unchanged. Proven live as a real non-admin before applying,
  in a rolled-back transaction: parent orgs 1→1 (legitimate access unchanged), direct
  partition orgs 2→**0** (leak closed). The audit WRITE path was proven too — the trigger is
  SECURITY DEFINER as `postgres`, which has `rolbypassrls`, and an authenticated write grew
  `audit_log` by exactly one row with all partitions secured. **The part without which this
  reopens monthly:** `ensure_audit_log_partition()` (the cron's partition creator) now
  enables RLS on each partition it creates — Supabase default privileges grant
  `authenticated` SELECT on new tables, which is how ten partitions came to be readable.
  The fix-round audit added two corrections, both applied: the ALTER is guarded on
  `relrowsecurity` + a 5s `lock_timeout`, because an unconditional ALTER takes an ACCESS
  EXCLUSIVE lock on the CURRENT month's partition at every monthly run as `postgres` (no
  timeout), behind which every audited write would queue; and the "catastrophic write
  failure" framing was wrong — the audit trigger swallows insert errors at NOTICE, so the
  real risk was silent audit loss, not write failure. Migration:
  `20260728_aud2_audit_log_partition_rls.sql`, applied live.
- [x] **FLG.2 — managers can flag.** NOT by widening `users_update_org` (rejected: that
  policy governs the WHOLE row, so users-edit managers would also gain the ability to rewrite
  any colleague's email, address and apns_token). Instead two SECURITY DEFINER RPCs,
  `flag_user(p_user_id, p_note)` / `unflag_user(p_user_id)` — the same shape as the five chat
  RPCs — checking permission (`is_user_admin() OR has_permission('users', 2)`), same-org,
  self, non-empty note, and row count internally. `flagged_by` is now recorded from
  `auth.uid()` server-side, unspoofable. The iOS direct-write path was DELETED in the same
  change. Proven live: manager ALLOWED (row written, push queued), plain employee DENIED,
  cross-org DENIED, self DENIED, empty note DENIED, ghost user DENIED, flag→unflag round trip
  clean. **The fix-round audit found the round's worst defect — ninth phase running: the
  permission guard failed OPEN on NULL.** `is_user_admin()` returns NULL (not false) for a
  JWT with no `users` row, and inside RLS `USING` NULL denies while inside plpgsql
  `IF NOT (...)` NULL skips the RAISE — the helper moved from a fail-closed context to a
  fail-open one, masked only by the org check behind it. Fixed with `coalesce(..., false)`
  and re-proven: a ghost JWT now hits the permission error itself. Migration:
  `20260728_flg2_flag_user_rpc.sql`, applied live.

**Recorded, not changed (pre-existing, each its own decision):**
- [ ] The audit triggers (`phase_o_audit_log_trigger`, `record_audit_read_event`) swallow
  failed inserts at `RAISE NOTICE`, which `log_min_messages` (warning) discards — a failing
  audit write is invisible. Same NOTICE-vs-WARNING mistake FLG.1 fixed in
  `notify_user_flagged`, but on a live shared audit trigger, so it is not a rider on AUD.2.
- [ ] Four more RLS-off tables with `authenticated` SELECT and no policy
  (`_recurring_tasks_backup_2026_05_28`, `access_code_pricing`, `_w12_repeats_backup_2026_05`,
  `archive_step_legacy_fields`) — same shape as the partitions, all currently 0 rows or
  non-PII, already named in `RLS_AUDIT.md` §181. The backup tables repopulate, so worth
  closing.
- [x] Policy note from FLG.2 — **DECIDED by the operator 2026-07-28: "anyone should be
  flaggable."** A users-edit manager can flag an org admin and clear a flag an admin set;
  that is intended behaviour, not an oversight. No code change; recorded so nobody
  "fixes" it later.
- [ ] **`FlaggedStatusView.swift` is dead code carrying the same defect this fix is named
  after.** No mount point anywhere in the app, and its `requestUnflag()` writes
  `unflag_request_note` and `is_unflag_requested` — **neither column exists** (verified live).
  It is the flagged person's only route to respond to a flag. Either delete it or build it;
  leaving a second copy of the bug is the worst of the three. Not decided unilaterally.

### PSH.1 — PUSH NOTIFICATIONS DO NOT WORK (RESEARCHED 2026-07-27, build gated)

> ⚠️ **THE ORIGINAL ENTRY BELOW IS WRONG ON ITS DECISIVE POINT. Read
> `PUSH_NOTIFICATIONS_PLAN.md` instead — it supersedes everything under this heading.**
> It was written from the two repositories without checking what is DEPLOYED, and it
> concluded "both ends are built, the middle is not." That is false for the one path
> that matters. **The sessions path is complete and live:** `trg_session_notification`
> on `public.sessions` (web repo `20260714_sec1_session_notification_vault.sql:66`)
> POSTs to the `session-notification` edge function, which **IS deployed** (verified by
> `supabase functions download` + byte-identical diff) and reads `users.apns_token` —
> the exact column iOS writes. All five `APNS_*` secrets are set.
>
> **It delivers nothing because of an APNs ENVIRONMENT mismatch**, not a missing middle:
> `APNS_PRODUCTION` is `true` so the sender targets Apple's production service, while
> the app is signed `aps-environment = development` in BOTH Debug and Release
> (`project.pbxproj:475`, `:522`). The operator installs from Xcode, so his device holds
> a sandbox-only token that the production endpoint rejects as `BadDeviceToken` — and no
> failure is recorded anywhere, because there is no
> `didFailToRegisterForRemoteNotificationsWithError` handler and both token writes
> swallow their errors with a `print`.
>
> **Do NOT "fix" this by flipping the flag.** One token column plus one global switch
> cannot serve a dev build and a TestFlight build at once. The plan records the
> environment per token instead.
>
> The findings below about undeployed functions, the dead queue, the `fcm_token` stray
> write and the broken flag call all still hold and were re-verified. What changed is the
> diagnosis and therefore the shape of the fix. Two further facts the original missed:
> **`send-notification` is not deployed at all** (nor `chat-notification`, nor
> `clock-reminder`), and **two different functions in two repos share that slug**, so the
> canonical one must be chosen before anyone deploys.
>
> **UPDATE 2026-07-27, after the live-DB read ran and the fix shipped.** The probe
> (`scripts/psh1_probe.sql`) confirmed every link healthy: `trg_session_notification`
> present and ENABLED, the vault secret `service_role_key` present, 22 users holding valid
> 64-char tokens. Apple then confirmed the diagnosis directly — sending to a real token
> returned `error: "BadDeviceToken", statusCode: 400`. **Fixed and verified end to end:**
> `sent: 1, failed: 0`, operator confirmed the notification arrived on the device.
> Steps 1–4 of `PUSH_NOTIFICATIONS_PLAN.md` are done, including a `time_off_requests`
> trigger that pushes to approvers on submit and to the requester on a decision.
>
> **Two more roadmap claims were wrong, both corrected by the live read:**
> `public.notification_queue` DOES NOT EXIST, so `daily-workflow-check` had been FAILING
> its hourly insert rather than filling a queue nobody drained; and `users.fcm_token` does
> not exist either (only an orphaned `fcm_token_updated_at`), so the stray iOS writer had
> been erroring on every launch. `DATABASE_SCHEMA.md` still lists `fcm_token` and is stale.

#### PSH.2 — NOTIFICATION COVERAGE — SHIPPED 2026-07-29, everything live

Scope confirmed by the operator 2026-07-28. Everything below is applied to the LIVE
database and deployed unless marked open. Each trigger was FIRED against a real row in a
rolled-back transaction (counting `net.http_request_queue`), and the transport's
exception handler was sabotage-tested (a raising transport did not roll back the write).

- [x] **One row per DEVICE: `public.user_devices`** (token PK, user_id FK, environment).
  Replaces `users.apns_token`/`apns_environment` — an iPhone+iPad user is now reachable
  on both devices; every sender fans out over the table and REAPS rows Apple pronounces
  dead (410 Unregistered / BadDeviceToken). 22 tokens backfilled, then the old columns
  (and the orphaned `fcm_token_updated_at`, operator sign-off 2026-07-28) were DROPPED.
  Registration goes through the `register_push_device` SECURITY DEFINER RPC ("push" in
  the name because `public.register_device` already belongs to the hardware registry —
  found live at apply time) so a handset changing users can evict the stale owner's row;
  RLS: own-row SELECT/DELETE only, anon revoked at creation (the AUD.2 lesson).
  Also fixed: the environment write had NEVER succeeded (all 40 rows NULL) because the
  only flush hook was the `.signedIn` event, which a warm launch never emits — the app
  now also flushes on `.initialSession`.
- [x] **Chat pushes wired**: `trg_chat_message_notification` AFTER INSERT ON `messages`
  (system rows excluded) → `chat-notification`, which got THREE fixes before wiring:
  it read `record.message_text` (the column is `text` — every body would have been
  empty), it had NO caller-auth gate (now service-role only, like `send-notification`),
  and it read the dropped users columns. One trigger covers both clients — web and iOS
  insert into the same table.
- [x] **Photo critique pushes wired**: insert-published + draft→publish transition
  triggers on `photo_critiques` → target photographer; self-critiques stay silent.
- [x] **Job box pushes wired**: `trg_job_box_notification` AFTER INSERT ON `job_boxes` →
  the shift's crew minus the scanner; payload carries BOTH `scannedBy` (the handler's
  required key) and `photographer` (the key JobBoxService actually reads).
- [x] **Session pushes were DEAD AGAIN and are repaired.** The MD7 arc moved crew off
  `sessions` onto `session_days`; `session-notification` still read
  `record.photographers`, so every fire since the move exited "No assigned employees".
  Now: crew resolves from `session_days` (or `crew_ids` captured by a new BEFORE DELETE
  trigger — an AFTER trigger finds the day rows already cascade-deleted); UPDATE fires
  only on is_published/school_name transitions (the old any-write trigger would have
  spammed "Session Updated" on every job-box scan once recipients resolved again);
  publish-transition renders as "New Session Assigned"; and a statement-level
  `session_days` INSERT trigger sends the assignment push when the crew actually lands
  (both clients insert the sessions row BEFORE the day rows, so an INSERT trigger on
  `sessions` can never see the crew — that path never once had a recipient and was
  removed rather than kept looking wired).
- [x] **Clock-in / clock-out / daily-report reminders — LIVE (applied 2026-07-29 on the
  operator's direct instruction, clearing the earlier classifier block).** Three cron
  jobs verified in cron.job (psh2-clock-in-reminders */30, psh2-clock-out-reminders and
  psh2-report-reminders hourly); all three dispatchers fired once in a rolled-back
  transaction with zero errors, and the hour-gated branch queries proven standalone
  against the live schema. The old
  `clock-reminder` edge function was unbuildable-on (four defects: `clock_in_time` /
  `clock_out_time` columns that do not exist, the removed `sessions.photographers`,
  UTC-vs-local wall-clock comparison, no auth gate) and was DELETED, repo and remote.
  Its replacement is three SQL dispatchers + `cron.schedule` in
  `supabase/migrations/20260729_psh2_reminder_crons.sql` (org-local timezones via
  `organizations.preferences->>'timezone'`, the daily-workflow-check convention;
  half-hour-grid windows so a late cron can neither skip nor double-remind). The
  auto-mode classifier initially blocked the live apply (reported in-session); the
  operator directed it through on 2026-07-29 and the earlier text claiming it was
  still pending was itself a review finding — this bullet is now the single truth:
  the three jobs are LIVE and verified in cron.job.
- [x] **A tapped push now navigates.** `PushNotificationManager` routes through
  `TabBarManager` pending ids (the `selectedClassGroupJobId` consume-and-clear shape):
  chat → the conversation, session/job box → the shift, critique → the critique sheet,
  clock reminder → time tracking, report reminder → daily report, time-off submitted →
  approvals, time-off decided → your requests, workflow step → tasks. The zero-observer
  `NotificationCenter` posts were deleted; the one real observer
  (`didReceiveJobBoxNotification`, ShiftDetailView live-refresh) is kept.
- [x] **Time-off reasons are OFF the lock screen** (privacy decision, decided
  deliberately per the flag-trigger precedent): bodies now carry the decision and dates
  only; the reason lives in the app behind the tap. Verified by firing a denial with a
  sentinel reason and reading the queued payload — not present.
- [x] **The two web-app `task_notifications` writers** (equipmentNotifications.js,
  workflowNotificationService.js) were ALREADY FIXED in the web repo (in-file comments
  credit PSH.2 2026-07-27); this checkbox was stale.
- [x] **`~/Desktop/Focal-Point-Supabase/.env.local`**: the three dead direct-DB
  credential keys removed (host unresolvable, both passwords failed, zero readers —
  grepped); a comment points at the Management API recipe.
- [ ] Still not built, recorded not claimed: per-type notification preferences (no
  settings surface exists; PSH.1's scope note stands); pushes for day DATE MOVES and
  for crew REMOVAL ("your session moved" / "you're off this session" notify nobody).
  Crew ADDITION is covered from both directions — the day-INSERT statement trigger and
  the fix round's crew-added UPDATE trigger (the dominant assignment path in both
  clients); notifying on removal/moves is the remaining gap.

**Security fix round (2026-07-29) — an adversarial audit that left the repo found and
PSH.2 closed, live-verified:** `session-notification` had NO caller gate (proven live:
a forged webhook signed with the public anon key returned 200 and would push arbitrary
"session cancelled" text to arbitrary crew_ids — now 403, same service-role gate as its
siblings). The gate itself now lives in ONE shared module (functions/_shared/gate.ts)
after a lesson the fix round paid for in full: the audit flagged the unverified
decoded-claims branch, the fix removed it leaving a literal-only comparison, and a live
end-to-end probe then showed the VAULT SERVICE KEY ITSELF getting 403 — this project
carries both key families, the runtime env holds the new-format sb_secret key while
verify_jwt forces callers to present the legacy JWT, so a literal-only gate is
unsatisfiable and would have silently killed every trigger push at once. Final gate:
literal match OR claims role=service_role on a bearer the platform has already
signature-verified; ⚠️ NEVER deploy these three functions with --no-verify-jwt — the
claims branch is sound only while verify_jwt stays on. Verified both ways live: vault
key via pg_net → 200, anon-key forgery → 403 on all three.
Also: `notify_photo_critique` required no actor at all on a table whose RLS
is `WITH CHECK (true)` for anon (now: no authenticated actor → no push; actor and
target must both belong to the row's org); `notify_job_box` resolved crew for ANY
`shift_uid` as SECURITY DEFINER (now: the shift must belong to the row's org);
`user_devices` lost its inert authenticated INSERT/UPDATE/TRUNCATE grants. Each guard
fired both ways in rolled-back transactions (attack path 0 requests, legit path 1).

**Operator-run /code-review round (2026-07-29) — 8 finder angles, 21 verified findings,
all fixed same session except the declined list below.** Fixed and live-verified:
case-folded id comparisons in every SQL recipient/suppression filter (341 report rows +
6 time-entry users verifiably carry uppercase ids); the sessions UPDATE trigger gained
its missing draft/time-off gate (a draft rename pushed to crew PUB.1 redacts drafts
from); unpublishing a published session now reads as a CANCELLATION (it was "Session
Updated" with a dead-end tap, and an unpublish-then-delete told the crew nothing);
clock-in windows flipped to (start, end] so an on-grid 09:00 session is reminded at
08:30, not 09:00; the reap loop closed (every BadDeviceToken now earns one try on the
other Apple endpoint, so a mis-recorded environment self-heals instead of permanently
silencing the device); the notes-only org excluded from report reminders; time-off push
dates render in org-local time (evening submissions said the wrong day); the manager's
job-box correction INSERTs a new scan event (it mutated history in place and was the
one status change that never pushed); the legacy record.photographers fallback deleted
(delete-first; a replayed pre-MD7 payload would have pushed a years-stale crew); chat
banners suppressed over the thread being read; notify_user_flagged migrated onto the
shared transport; the three deep-link consumers consolidated into ONE
TabBarManager.consumePendingDeepLink with a 120-second tap expiry; plus perf fixes
(@ObservedObject over-subscription, guard ordering, parallel lookups, shared
formatters) and both false doc claims corrected (this file's crons bullet; the
job_boxes realtime migration's "no web subscription" — SessionDetailsModal.js:255 had
a dormant one this change deliberately activates).

**Review findings DECLINED, with reasons (evaluated, not ignored):**
- The photographers-jsonb crew extraction appears in ~7 SQL bodies; a shared helper was
  declined this round — all seven copies are live-verified working and rewriting seven
  SECURITY DEFINER functions at phase close risks more than it saves. Candidate for the
  next phase that touches crew shape.
- The tolerant ISO8601 decode exists in Session.swift and JobBox; a shared Swift helper
  was declined for the same reason (Session's copy has shipped for weeks).
- Set-based dispatcher rewrites (vs per-org loops): declined — the loop's per-org
  exception isolation is deliberate and org count is small.
- The tracker's card-number search operates on a permanently empty field (Firebase-era
  ghost) — dead feature, recorded for a cleanup phase rather than surgically removed at
  1am.
- The gate's in-function JWT signature verification (vs the verify_jwt dependency):
  already on the SEC.* list.
- The user_devices backfill's arbitrary owner pick on duplicate tokens: unfixable
  retroactively (source columns dropped) and self-healing on next launch via
  register_push_device.

**Recorded, deliberately not changed in PSH.2:**
- `photo_critiques` RLS is `WITH CHECK (true)` / `USING (true)` for anon AND
  authenticated — a pre-existing hole, now on the SEC.* candidate list (the trigger
  refuses to amplify it, but the table itself is world-writable with the anon key).
- Bulk publish (`publishMultipleSessions`, web Schedule.js) legitimately sends one push
  per session per crew member — publishing a large backlog is a push burst by design;
  revisit only if the operator reports it as noise.
- `scripts/firebase-sync-app` (archived web-repo Electron tool) upserts historical
  `messages`/`job_boxes` rows; RE-RUNNING IT NOW WOULD REPLAY HISTORY AS LIVE PUSHES.
  Do not run it without dropping the PSH.2 triggers first.
- `register_push_device` evicts a stale owner silently (possession-of-token design is
  sound; an audit_log write on the eviction branch is a recorded low-priority
  improvement).
- A tapped deep link whose target has not loaded yet stays pending until it resolves —
  so if the person meanwhile opens something else IN THAT TAB, the requested navigation
  can arrive late and swap what they are looking at. Deliberate trade (fourth-round
  audit): the alternative — dropping the id on a no-match list — dead-ended the
  canonical new-conversation push against cache-first list emissions. The navigation
  that fires is always exactly the one the person tapped, bounded by app-process
  lifetime, and sign-out (both the explicit and the SDK-event path) clears it.
- Web `syncSessionDays` was fixed in the web repo (one INSERT statement for new days,
  so adding N days to a published session sends one push, not N).
- `notify_photo_critique`'s actor guard requires auth.uid() to match an in-org users.id
  — it FAILS CLOSED (drops the push, never over-sends) for the 9 legacy rows whose
  users.id is not their auth uid. Checked live: zero existing critiques were authored
  by such a row, and the one active mismatched admin resolves through a duplicate
  in-org row; recorded because it is the id-equality fragility the FLG lesson names.
- `daily-workflow-check` → send-notification (workflow_step_scheduled pushes): the gate
  passes its bearer via the literal branch only if the runtime env key equals what
  functions.invoke sends — expected true (same injected env), but not provable from
  this machine. VERIFY on the next hourly run, and verify the POSITIVE signal only:
  send-notification 200s in the function logs. Absence of "refused a non-service-role
  caller" warnings is NOT a pass — if the env key is the non-JWT sb_secret form, the
  invoke dies at the platform's verify_jwt (401) BEFORE the function runs and no gate
  log line ever appears; a gateway 401 or silence is the other failure mode.

#### Original entry, 2026-07-27 (superseded — kept for the record)

Found while answering an operator question during AMB.8: "I denied it on the iPhone.
I should always get a push notification for those." They were right to expect one, and
right that it is broader than time off — **on the evidence in both repos, almost no push
notification in this app can ever be delivered.** Both ends are built. The middle is not.

**THE CHAIN, END TO END, with what is verified at each link:**

- [ ] **Nothing fills the queue.** `send-notification` (the edge function that actually
  sends) polls `notification_queue` for `status = 'pending'`. Across the whole backend
  **exactly one thing writes to that table**: `daily-workflow-check`, with a single type,
  `workflow_step_scheduled`. No migration creates a trigger on any table that queues a
  notification. The iOS app never writes it. The web app never writes it.
- [ ] **The web writes a DIFFERENT table.** `timeOffNotificationHelper.js` inserts into
  `task_notifications` — which `send-notification` never reads and which **iOS never reads
  either** (zero references in Swift). So a web denial creates a record nobody delivers.
- [ ] **THE TOKEN COLUMNS DO NOT MATCH THE TRANSPORT.** `send-notification` reads
  `users.fcm_token` and sends via FCM. `PushNotificationManager` writes **`apns_token`**.
  The only writer of `fcm_token` anywhere in iOS is a stray call in
  `Manager Features/JobBoxStatus.swift:189`, which stores a raw **APNs** device token under
  the FCM column name. An APNs token is not an FCM token; FCM would reject it.
- [ ] **Ten types are wired at both ends and none of them can fire.** The sender handles
  `proofing_approval`, `chat_message`, `session_new`, `session_update`, `clock_reminder`,
  `report_reminder`, `photo_critique`, `pto_processed`; `PushNotificationManager` handles
  those plus `flag`, `jobbox`, `session_delete`. Somebody wired both ends and the middle
  never landed.

**THE ONE WAY THIS COULD BE WRONG, stated rather than glossed:** this is read from the two
repos, not from the live database. A trigger created by hand in the Supabase console would
not appear in `supabase/migrations/` and is invisible from here. The operator independently
reports that session changes do not notify either, which is consistent with the reading but
is not the same as a query. **CHECK THE LIVE DB FIRST** — `pg_trigger`, and whether
`notification_queue` has ever held a row that was not `workflow_step_scheduled`.

**SCOPE, and why it is its own arc rather than a line under TOF.1:** it is cross-client and
server-side, it touches every feature that ever wanted to notify, and the first question is
not "which types do we add" but "what was the intended trigger and was it ever built". The
right shape is almost certainly a DATABASE TRIGGER on the source tables so that neither
client can forget — the same reasoning CHT.1 reached about moving truth into the database.

**A NOTE ON HOW THIS WAS NEARLY MIS-SCOPED.** Asked for a denial push, I first sized it as
"a few hours: queue a row, add a case, add the iOS type." That would have added a ninth type
to a queue nothing fills, verified the row appeared, and shipped something that still never
reaches a phone. Fixing the instance without asking whether the mechanism works at all is
the exact failure this arc has been punished for repeatedly.

---

### TOF.1 — Time off authorization + PTO integrity (NOT STARTED, found 2026-07-26)

Found while inventorying batch 2 at AMB.6's close. **Payroll-adjacent and NOT design
work** — recorded as its own item deliberately, because a style phase must not be the
thing that quietly closes an authorization hole. Full file references in
`AMB_BATCH2_PARITY.md` (findings 1, 2, 3, 8).

- [ ] **`TimeOffApprovalView` has NO permission check at all.** Approve, Deny and
  Put-in-Review are gated only by whether a row is VISIBLE in `AllFeaturesView`, and
  that row checks `Permissions.has("users", .edit)` — **a different area code from
  `timeOffApprovals`**. Anything that sets the selected tab to `timeOffApprovals`
  reaches live approve/deny buttons on every employee's requests.
  `TimeOffService.canManageRequests()` already exists, does the right check, and is
  **never called**.
- [ ] **PTO shortfalls are swallowed.** `reservePTOHours` throws "Insufficient PTO
  balance"; the caller catches it and only prints a warning, so **the request is
  created anyway**. Same swallow on release and on deduct at approval. And
  `updateTimeOffRequest` never adjusts an existing reservation, so editing the hours
  leaves the old reserve in place.
- [ ] The ownership check in `TimeOffDetailView` reads `UserDefaults "userID"`, **a key
  nothing in the app writes**, so it is always false and the buttons appear only for
  holders of `timeOffApprovals` edit.
- [ ] "Delete Time Off" is shown only for **approved** entries and calls a function
  that rejects approved — every press is a 403. **AMB.8 DELETED THE BUTTON** (a
  control whose every press fails is not a capability to preserve); what remains
  for TOF.1 is whether a real delete should exist at all.

**Added by AMB.8's research, 2026-07-27 — all cross-client, none fixed:**

- [ ] **`organizations.pto_settings` key casing does not match.** The web writes
  snake_case (`accrual_rate`, `max_accrual`, `rollover_policy`); iOS decodes
  camelCase and every field is optional, so the decode SUCCEEDS with all nils and
  substitutes hardcoded defaults. Only `enabled` matches. Invisible at default
  configuration because the two default sets coincide — it appears the moment an
  admin changes a number.
- [ ] **Approving or denying on the web never releases `pending_balance`.** The
  web's PTO mutators (`reservePTOHours`, `usePTOHours`, `releasePTOHours`,
  `adjustPTOBalance`) have ZERO callers, and its approve/deny paths touch only
  `time_off_requests`. iOS is the only client that moves PTO hours, so a request
  it reserved for and a manager actioned on the web leaves the hours reserved for
  the life of the account. No reconciliation path exists in either repo.
- [ ] **`pto_balances.used` is maintained by nobody.** `PTOBalance.useHours()`
  increments it in memory and `usePTOHours` writes only `balance`,
  `pending_balance` and `updated_at`. The web never reads or writes it.
- [ ] **`"underReview"` vs `'under_review'`.** iOS writes camelCase; the web only
  ever matches snake_case, in its calendar projection and all three approval tabs.
  An iOS "Put in Review" request is invisible to the web app.
- [ ] **The web writes `'partially_approved'`**, which no iOS enum case covers.
  AMB.8 stopped it rendering as "Pending", but it still matches no filter chip and
  is excluded from the iOS calendar fetch's status list.
- [ ] **Uppercase row ids.** `TimeOffService` inserts `UUID().uuidString` as the
  primary key, against the project's lowercase-UUID rule.
- [ ] **Sign-out leaves `TimeOffService.currentUserId` / `currentOrgId` set**, so a
  second sign-in in the same app run can fetch and subscribe for the PREVIOUS
  organization on a shared multi-tenant database.
- [ ] **The PTO projection is computed on a different base from everything
  displayed.** `PTOService.calculateProjectedBalance` projects `totalBalance` (the
  raw column) while every screen shows `availableBalance`
  (`balance - pending_balance`), and its `pendingRequests:` parameter defaults to
  empty so nothing is subtracted. AMB.8 converted the projection to an
  available-equivalent at the two display sites so the numbers beside each other
  are measured the same way, and labelled the balance screen's figure "Projected
  total balance". **The underlying inaccuracy is untouched and cannot be fixed
  client-side:** `pending_balance` is itself unreliable, because a request iOS
  reserved hours for and a manager approved ON THE WEB never releases the
  reservation (see the item above). Any real fix is a cross-client one.
- [ ] **`blocked_dates` is honoured by the web and ignored by iOS** — an employee
  can request time off on a blocked date from the phone. Same unbuilt idea as the
  dead "Schedule Conflicts" section AMB.8 removed.

Server-side auth goes through `role_permissions` + `has_permission()`; read the
rls-remediation memory before touching it.

---

**Out of scope, permanently (D1):** Sports Shoot Feature (53 views, 36,352 lines) — the
hook-protected Captura files plus a live iPad shoot tool where a restyle risks work in
progress.

---

## PUB — draft visibility on the iOS schedule (arc, registered 2026-07-25)

Plan and the six decisions P1–P6: `DRAFT_VISIBILITY_PLAN.md`. Family registry row:
`~/Brain/projects/registry.md (formerly FocalPointProduction/docs/PHASES.md)`. One phase.

Deliberately NOT part of the AMB arc, whose D2 forbids behaviour changes inside a
phase. Sequenced against AMB.3 because both touch `ScheduleView`'s per-day index.

- [x] **PUB.1 Draft visibility** — DONE 2026-07-25. **Operator smoke PASSED 2026-07-25.**
  Committed to `main` (`4fb5ce1` + `42d2ef6`); push is the operator's call.

  **What changed.** The schedule now fetches unpublished sessions for everyone
  (`includeUnpublished: true`, was `canEdit`), so a photographer can see what work is
  coming. A draft never shows who is on it — not other people's assignment, not the
  viewer's own — for anyone without schedule-edit rights. Drafts sit in their own
  bucket under a "Not published yet" heading in BOTH layouts, carry a dashed border
  and the existing Draft pill, and are kept out of the countdown card, the ambient
  tint, the day's hours and the shift count. The staffing temperature is gone for
  everyone: heat dot, breakdown popover, and the long-press that never fired (a
  gesture on a Button inside a horizontal ScrollView). `HeatMapUtils.swift` deleted in
  the same commit that orphaned it.

  **One redaction point (P4).** `DraftCrew.swift` empties the crew — including every
  `session_days` row's crew, because `Session.with(day:)` rebuilds an occurrence from a
  day-row and would otherwise put it straight back. Applied where a session crosses
  into the view layer: the schedule's index, the array handed to the detail, and the
  detail's OWN realtime listener (a second store that would otherwise un-redact within
  a second of opening a draft).

  **Found by audit and fixed in the same phase (none of these were in the plan):**
  - permissions load asynchronously, so an index built before they landed kept a
    scheduler's drafts redacted while the detail's live permission check offered Edit —
    which seeds its crew picker from exactly that emptied array, a roster-loss path on
    the shared DB. `ScheduleView` rebuilds on permission change; the detail carries a
    `crewHidden` fact about the data it holds rather than re-deriving it, AND restarts
    its listener on a permission change — without that last part the guard became a
    permanent Edit/Publish LOCKOUT for a scheduler, because the view's identity
    (`.id(dayOccurrenceKey)`) does not change when permissions do, so a re-passed init
    value never lands. Caught by the third audit, on the second fix round.
  - the job box's "Last scanned by <name>" is keyed on session id, not crew — the one
    place a name reached a draft without going through `photographers`.
  - a past draft read as a struck-through "DONE" job in Timeline while Day view drew it
    as provisional. Both rows now refuse the finished treatment for a draft.
  - the offline cache was one unlabelled file shared by callers with different scopes,
    so a published-only fetch landing last would DELETE every draft from it. The cache
    now records two separate facts — whether it carries drafts, and whether those
    drafts are a complete current snapshot — and a narrower save keeps drafts it was
    never told about without claiming they are up to date. **This code is currently
    DORMANT: see the pre-existing bug below.**

  **PRE-EXISTING BUG FOUND, DELIBERATELY NOT FIXED HERE — the offline schedule cache
  has never worked, since 2026-02-11 (`7289909`).** `ScheduleCacheManager.saveSessions`
  encodes metadata with `.iso8601`, but `loadMetadata()` decodes with a bare
  `JSONDecoder()` (`.deferredToDate`, which expects a Double). Verified by running the
  round trip: `typeMismatch ... Expected to decode Double but found a string instead`.
  `loadMetadata()` therefore always returns nil, so `loadSessions` bails at its first
  guard and NO offline schedule data is ever served — no instant cached first paint, no
  "Offline · last synced" state, and `loadFromOfflineCache` throws instead. The fix is
  one line (`decoder.dateDecodingStrategy = .iso8601`). Left for the operator to
  schedule because it switches on a persistence path that has never once run in
  production, for every user, and that deserves its own smoke rather than riding along
  inside a phase about draft visibility. It also means this phase's cache work is
  correct but unexercised, and the "drafts vanish offline" risk it was written against
  could not actually have occurred.

  **Unchanged and verified so:** the shared Supabase database (no schema, policy, RPC
  or write change — one `.eq` dropped from one client query); `EditSessionView`;
  publishing; every other session consumer (dashboard, time tracking, ICS export,
  reports), all still published-only.

  **Evidence.** Build clean, zero new warnings (the one warning in a changed file was
  proved pre-existing by stashing and rebuilding). Card-drift gate green. THREE
  adversarial audits — two on the build, one on the fix round, which found a CRITICAL
  and a HIGH in the fix round itself and was worth its cost. Plus `/security-review`:
  no HIGH or MEDIUM findings, org predicate intact, server-side writes still
  independently enforced. `/code-review` was not available as a skill in this session.

  **Lesson for the next phase: audit the fix round too.** The second round of fixes was
  where the worst defect of the whole phase lived — a permanent Edit/Publish lockout for
  schedulers, introduced by a guard added to prevent a roster wipe. Fixes written under
  audit pressure are not safer than the original code, and nobody had reviewed them.

  **Two open questions raised during the build, both ruled on by the operator
  2026-07-25 and built accordingly:**
  - **Drafts appear in ALL SHIFTS ONLY, never in My Shifts** — for anyone, scheduler
    included. This SUPERSEDES the plan's P6, which had them in both on the reasoning
    that an unassigned draft cannot belong to "mine". The premise was right and the
    conclusion backwards: it filled the one view that answers "what am I doing" with
    the whole org's planned work. Whether a day carries unpublished work is now tracked
    unfiltered, so the manager's publish-a-day button does not vanish with the filter.
  - **Notes stay on a draft** (`session.notes`, `session_days.day_notes`). Raised
    because a free-text note can name people, which is what P2 withholds. Ruled fine:
    notes describe the WORK, which is what a draft exists to tell you. Recorded as P7.

  **Recorded, not fixed — for the operator:**
  - Redaction is client-side only and always was un-enforced server-side (P3): every
    authenticated employee could already read draft crew directly. Not new, recorded so
    it is never mistaken for a control.

---

## Reference: what NOT to break (verified strengths)

- Firebase migration is 100% complete in live code — no dual-writes anywhere
- Subject sync (CommandQueue + acks + idempotency + optimistic overlay rollback) is solid — don't "simplify" it
- Zero `try!`/`as!`/`fatalError`; keep it that way
- Core services have correct weak-self/timer/channel hygiene
- Newer features (Tasks, Yearbook, Equipment, TimeOff, Chat) follow clean Models/Services/Views — use them as the template

  **/CODE-REVIEW ROUND, 2026-08-01, before the push — 6 findings, ALL FIXED (`2fd4cf8`).
  TWO OF THEM ONLY SURFACED BY DRIVING THE APP**, which is the round's real finding: this
  phase had been reported "verified on both devices" on the strength of screens RENDERING.
  Both had a clean build, a clean drift sweep, and code that read correctly.

  - **All Features drag-to-reorder, broken by this phase's own section-title row.** `onMove`
    reports offsets into the **ForEach**, not into the enclosing `Section`, so the `-1` added
    to "account for the title" moved the row ABOVE the one being dragged and swallowed any
    drag of the FIRST row entirely (index 0 filtered out, then an early return). Reproduced
    by dragging "Time Off Requests" to the top and watching "Scan" move instead; fixed and
    re-verified, with the persisted `employeeFeatureOrder` matching the screen. The fix also
    closed a PRE-EXISTING divergence: the ForEach is over the FILTERED list while the view
    model mutates the unfiltered one, so on an org with `usePhotoshootNotesOnly` a drag could
    reorder hidden features.
  - **Every disabled button drew white text on `Color.secondary.opacity(0.4)`** — near-white
    on near-white in light mode, across Flag User's submit, Training's Save, Add School's Save
    and Sign In. Invisible in review, obvious in a screenshot.
  - **`schools` UPDATEs had no zero-row proof**, so "Photo deleted." and "School info updated!"
    were reported for writes that may have matched nothing (PostgREST returns 200 on a no-op).
    `SchoolService` now carries the same `requireRowsWritten` guard as `DailyJobReportService`
    and `TimeTrackingService` — a service the earlier sweeps had skipped.
  - A rationale comment in `SignInView` asserting that `RootView` enters the app whenever a
    session appears — **made false by the RootView change in the SAME commit**, and
    contradicted by a second comment twenty lines below it.
  - The profile-failure card said "Try again" even when the cause was an account with no
    resolvable organization, where retrying can never succeed. The two causes now get
    different advice and the Retry button is hidden on the futile one.
  - The toast's repositioning was unverified and absent from the smoke list; a check was added
    rather than a claim.

  **THE DURABLE LESSON: "it renders" is not "it works", and a clean build plus a clean gate
  plus code that reads right still proves neither.** Every phase of this arc has a defect class
  its automation cannot see; for the tail it was INTERACTIONS — drags, taps, disabled states.
  Exercise the CONTROLS on a converted screen, not just its pixels.

  **CLOSED 2026-08-01, operator smoke PASSED.** Six mockups deleted at the close per the
  AMB.7 rule — Settings, Manager Tools and Training (this phase's), plus Time Off (AMB.8),
  Class Groups and Yearbook (AMB.10), **which had outlived their own closes and had simply
  been left behind**. Their sample data went with them (995 lines → 377). A mockup is a
  VALIDATION REFERENCE: it outlives the port it validated, not the phase — and data that only
  ever fed a deleted screen is not scaffolding, it is a fossil that still compiles, so nothing
  complains and the next person has to work out which of it is live.

  **THE HARNESS SURVIVES, and that is the D15 ruling working as intended.** The gallery, the
  sample data and the two FOUNDATION mockups (specimen sheet, palette) stay for AMB.13, which
  needs somewhere to design the time clock. Verified after the deletions: build clean, sweep
  clean, and the lab opens on the device showing exactly the two foundations.

  **A CUT THAT WENT ONE BLOCK TOO FAR, caught by the build:** deleting the dead sample data
  took `LabKitEdge` with it — the kit-colour band the SURVIVING specimen sheet draws. Restored.
  The lesson is small and repeatable: when deleting by region rather than by symbol, the
  compiler is the only thing that knows what the region was still holding up.
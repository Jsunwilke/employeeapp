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
`kickoffs/START_A_PHASE.md`. Family registry row: `FocalPointProduction/docs/PHASES.md`.

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

  **Still open, and only the operator can settle it:** whether that approval was
  given ON A DEVICE. D10 turns on the device specifically because approving an
  approximation manufactures confidence that was never earned, and D7 wants
  iPhone AND iPad. Until that is confirmed, AMB.3 does not start and the D8 push
  does not fire.

**Batch 1** — mocked in AMB.2, reviewed in one sitting, then converted:

- [ ] **AMB.3 Equipment** (34 views, 5,583 lines) — first dense list; proves the compact
  variants in use and folds any corrections back into the design system.
- [ ] **AMB.4 Home dashboard** (`MainEmployeeView` + `DashboardWidgets`, ~3,600 lines) —
  highest traffic, and its Upcoming Shifts widget currently disagrees with the
  already-converted schedule.
- [ ] **AMB.5 Tasks** (18 views, 3,167 lines)
- [ ] **AMB.6 Chat** (20 views, 4,655 lines) — long scrollbacks, the real test of the
  compact set. Closes batch 1 and mocks batch 2.

**Batch 2**

- [ ] **AMB.7 Reports family** (Misc Features, 8,695 lines) — daily job report, custom
  reports, my reports, photoshoot notes. Form-heavy; first real input styling.
- [ ] **AMB.8 Time off** (8 views, 3,763 lines) — closes batch 2 and mocks batch 3.

**Batch 3**

- [ ] **AMB.9 Mileage + Stats** — number-heavy; stat tiles and charts.
- [ ] **AMB.10 Groups + Yearbook** (17 views, 4,504 lines) — closes batch 3 and mocks
  batch 4.

**Batch 4**

- [ ] **AMB.11 Job box / NFC** (18 views, 5,198 lines)
- [ ] **AMB.12 Settings, Manager, Training** (~6,600 lines) — the tail, converted per D9.
  Closes the arc and deletes the lab harness + its menu entry.

**Out of scope, permanently (D1):** Sports Shoot Feature (53 views, 36,352 lines) — the
hook-protected Captura files plus a live iPad shoot tool where a restyle risks work in
progress.

---

## PUB — draft visibility on the iOS schedule (arc, registered 2026-07-25)

Plan and the six decisions P1–P6: `DRAFT_VISIBILITY_PLAN.md`. Family registry row:
`FocalPointProduction/docs/PHASES.md`. One phase.

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

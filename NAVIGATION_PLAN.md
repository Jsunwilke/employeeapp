# Navigation Restructure — Plan (Phase 3.1, done correctly)

Status: PLANNED — awaiting operator sign-off on the decision gate below. Nothing built yet.
Written 2026-07-13 from a full, code-verified research pass (two research agents + direct
verification of the one point they disagreed on). Supersedes the shell-suppression patch on
branch nav-single-stack, which will be deleted-first when this is built.

## What the app does today (verified, not assumed)

- Entry: EmployeeAppApp -> RootView (auth gate) -> MainEmployeeView (the shell) or SignInView.
- The shell wraps EVERYTHING in ONE NavigationView (StackNavigationViewStyle) and renders
  VStack { mainContent ; BottomTabBar }.
- The router is a single string, TabBarManager.selectedTab, written from 13 places in 7 files.
  Empty string and "home" both mean Home. mainContent shows the home dashboard or one feature
  via a 27-case switch (featureView).
- The shell's top bar provides the ONLY Home button ("< Home", top-left) plus the profile menu
  (Settings / Appearance / Logout, top-right).
- The BottomTabBar has NO Home — it is a customizable row of feature shortcuts plus the center
  Scan button (iPhone). Home exists only as the shell's top button or a programmatic jump.
- Min iOS is 16.6, so real NavigationStack / NavigationPath are available. The app uses none
  today — it is all NavigationView.
- No notification tap or deep link routes to a feature (only password-reset is wired).

## The two root causes (everything else is a symptom)

1. NO PERMANENT HOME. Home lives only on the shell's top bar. So the moment that bar is hidden
   to remove a doubled nav, the only way back to Home disappears (this is what stranded Tasks).
2. THE SHELL OWNS A NAV BAR THAT EVERY SELF-NAV FEATURE THEN DOUBLES. Features that bring their
   own NavigationView get the shell's bar stacked on top of theirs (the "double back button").

The fake "< Home" button, the selfNavFeatureIDs allowlist (the patch), the topBarBackOverride
closure that reaches into the capture flow, and the "" vs "home" dual sentinel are all symptoms
of those two.

## Verified feature inventory (the facts the fix must respect)

- 7 features own their nav bar (root NavigationView/Stack): capture, training, unflagUser,
  tasks, equipment on BOTH devices; sportsShoot and focalPointSports on iPad ONLY (their iPhone
  paths are bare VStacks that borrow the shell's nav).
- 20 features are shell-dependent (no root nav): timeTracking, chat, scan, photoshootNotes,
  dailyJobReport (corrected — its body is a ScrollView), yearbookChecklists, classGroups,
  customDailyReports, myDailyJobReports, mileageReports, schedule, locationPhotos,
  timeOffRequests, timeOffApprovals, flagUser, managerMileage, stats, galleryCreator,
  jobBoxTracker, routePlanner.
- Only 3 features can currently reach Home on their own, and only barely: sportsShoot (iPad),
  focalPointSports (iPad), dailyJobReport (only after a successful submit).
- 3 features are protected or depend on protected files: sportsShoot, focalPointSports, capture
  (they hard-depend on SportsShootListView / SportsShootDetailView / LockManager /
  MultipeerRosterSync). The mid-shoot back lives in PoserStationView, which is NOT protected.
- 2 features use the iPad split view (DoubleColumnNavigationViewStyle): sportsShoot,
  focalPointSports — both in protected / protected-dependent files.
- Manager-only features (7) are gated in AllFeaturesView by Permissions.has("users", .edit).
  That gate is independent of navigation and must be left exactly as-is.

## The correct fix (recommended): fix the foundation, then delete the symptoms

Give the app a permanent Home and make every screen own exactly one nav bar. Concretely:

1. PERMANENT HOME in the BottomTabBar. A fixed Home button (always present, not part of the
   customizable set) that selects Home. Home is reachable from every screen, always. This is
   the change that makes everything else safe.

2. THE SHELL STOPS OWNING A NAV BAR. Remove the outer NavigationView from MainEmployeeView and
   the fake "< Home" toolbar button.
   - The Home dashboard gets its OWN NavigationStack and carries the profile menu
     (Settings / Appearance / Logout) — profile/settings belongs on Home, not stacked on top of
     every feature.
   - Self-nav features render as-is, with no shell bar on top (single bar, by construction).
     This means ZERO edits to the protected Sports files — their own nav is already correct;
     the only reason they looked doubled was the shell bar we are removing.
   - Shell-dependent features are each wrapped by the shell in ONE NavigationStack that shows
     their title. They already work inside a nav container today; this just makes it their own.
   - The two split-view features are self-nav on iPad (render bare) and shell-wrapped on iPhone
     (their iPhone path is a bare VStack) — a per-device wrap decision for exactly those two.

3. DELETE THE SYMPTOMS (delete-first, same change):
   - selfNavFeatureIDs / isSelfNavFeature — gone (no shell bar to hide).
   - The fake "< Home" button — gone (Home is in the bottom bar).
   - topBarBackOverride — gone. In the capture flow, PoserStationView is pushed inside
     CaptureGalleryListView's own NavigationView, so it gets a normal back button; the closure
     bridge is unnecessary. (Edit is in PoserStationView, which is not protected.)
   - Normalize the router: one real Home identity, remove the "" vs "home" dual sentinel.

4. LEAVE ALONE (out of scope, not deferred work — separate concerns that already function):
   - isFullScreenOverlayActive (kiosk / photo-viewer hides the bottom bar) stays; still read by
     the shell to hide the bottom bar during a full-screen kiosk.
   - The cross-feature payload bus (selectedSportsShoot etc.) stays — it carries data on a
     widget-to-feature jump; it is not a nav-bar problem.
   - Notification / deep-link routing to features is a genuine gap, but it is a new feature, not
     part of fixing the double-nav + stranding bugs. Called out, not silently dropped.

Net result: one nav bar on every screen, Home always one tap away, no allowlist, no fake back
button, no closure bridge — and the protected production files are not edited.

## Architecture decision gate (plain English)

- Immediate fix or forward architecture? This IS the forward-correct foundation: it removes the
  root causes and the hacks, not a screen-by-screen patch. It stops short of a full rewrite to
  typed routes (a NavigationPath enum for every screen) because that is a much larger change,
  changes the feel more, and is not required to fix the reported bugs. Typed routes + deep-link
  routing can be a later, separate step on top of this clean base.
- Does it survive the real constraints? Yes: protected Sports files are not edited (they render
  as-is); iPhone and iPad are both handled (per-device only for the two split-view features);
  the manager permission gate is untouched; the kiosk full-screen behavior is preserved.
- Cost to undo if wrong? Moderate and reversible — it is a shell rework plus a bottom-bar
  addition on a branch; git revert restores today's behavior. Not a one-way door.
- Validated or assumed? The design is built on the verified research map above. The visual
  result must be confirmed by the operator running it on iPhone AND iPad — that is the sign-off,
  not a diff review.

## The one thing that is genuinely the operator's call

Doing this correctly requires two small, deliberate UI changes (there is no correct fix without
them, because the missing permanent-Home IS the bug):
- A permanent Home button appears in the bottom bar.
- The profile menu (Settings / Logout) lives on the Home screen instead of on top of every
  feature screen.
Everything else keeps its current look. If those two are acceptable, this is the plan. If they
must be preserved exactly, a clean fix is not possible and we would be back to trade-offs.

## Build order (once approved) — one coherent change, verified before merge

1. Add the permanent Home to the BottomTabBar; normalize the Home router identity.
2. Rework the MainEmployeeView shell: remove the outer NavigationView + fake Home button; give
   Home its own NavigationStack with the profile menu; wrap each shell-dependent feature in one
   NavigationStack; render self-nav features bare (per-device for the two split-view features).
3. Remove topBarBackOverride and fix the capture back via the inner nav's natural back button
   (PoserStationView).
4. Delete selfNavFeatureIDs / isSelfNavFeature and the branch's patch commits (delete-first).
5. Build-verify (xcodebuild). Then the operator runs it on iPhone AND iPad and walks every
   feature: one bar, Home always reachable, capture mid-shoot back works, kiosk still hides the
   bar, manager features still gated.
6. Independent /code-review (high) run by me as the final step (this touches the shell every
   feature hangs off — high-stakes). Fix findings. Then commit, and advise merge vs hold.

# Start a Phase — Iconik Employee

Reusable kickoff. Paste this whole file into a new session, write ONE line under
START HERE, and the agent runs the phase end to end. One phase per session.

Iconik Employee is the iOS app of the Focal Point family: SwiftUI (iPhone + iPad),
Supabase backend shared with the Focal Point web app + Captura, PowerSync
offline-first for the Sports roster. Same building/research standards, same
phase-naming registry as the rest of the family.


# 🚀 START HERE  (you, the operator)

      WHAT TO BUILD:

  An arc id (e.g. TOF.1) or just describe the item in plain words. That is the only
  line you fill in — the agent works out the exact phase and scope.

  KEEP THIS BLOCK EMPTY unless there is something the roadmap does not already say.
  It went stale during AMB.3 — it still described mockup work that had been built and
  approved two sessions earlier, which sent that session hunting for finished work.
  It went stale AGAIN before FLG.1: it still said psh.2 from the prior session, which
  pointed that session at a parked heading the operator had to re-scope mid-build.
  The phase list below and AUDIT_ROADMAP.md are the sources of truth; this line is not.


# 📋 Phases

  Named by arc code (ARC.N) per the family registry, FocalPointProduction/docs/PHASES.md.
  Full per-item scope + closeouts live in AUDIT_ROADMAP.md.

  🎨 AMB — Ambient design language rollout   (REGISTERED ARC: 1–8 ✅ shipped, next 9)
      IT IS A REDESIGN WITH A PARITY CONSTRAINT (D12, operator 2026-07-25). IN scope:
      layout, hierarchy, information architecture, the reading order of a list, states
      that should exist and do not. OUT of scope, unchanged: data layers, services,
      loaders, caching, business rules and permissions, the shared Supabase
      schema/RLS/PowerSync. NO FEATURE MAY BE LOST, and that is checkable rather than
      promised — inventory the surface's capabilities FROM THE SOURCE before
      redesigning it, including parts of a design the operator already approved.
      Every phase SHOWS A RUNNING SWIFTUI MOCKUP FOR OPERATOR APPROVAL BEFORE THE
      REAL SCREENS ARE TOUCHED (D10 — hard gate), approval ON A DEVICE. The mockups
      live in ONE lab harness built in AMB.2, kept for the arc and deleted at AMB.12;
      a phase's own mockup views are deleted only after BOTH smokes pass — a
      validation reference outlives the port. Smokes on iPhone AND iPad (D7); ships
      to main as it lands (D8). Plan + locked decisions D1–D13: AMBIENT_ROLLOUT_PLAN.md.
      THE MECHANISM THAT KILLED DESIGN DRIFT (AMB.7/AMB.8 — use it every remaining
      phase): the design lives in PRODUCTION components the lab IMPORTS, so there is
      no copying step and nothing to drift; the display rules are SwiftUI-free and a
      script COMPILES AND RUNS them; the parity walk is a re-runnable SCRIPT against
      the NEW screens, run every fix round.

      ✅ AMB.1   Schedule             DONE + PUSHED 2026-07-24
      ✅ AMB.2   Design system + build gate + THE LAB   DONE + PUSHED 2026-07-25.
                 DesignSystem/ primitives, the card-drift gate, the D11 palette
                 (27 distinct feature colours), density D5, six batch-1 mockups
                 approved on device, iPhone AND iPad.
      ✅ AMB.3   Equipment            DONE + PUSHED 2026-07-25, smoked both devices.
                 LESSON: an approved mockup is a design decision, NOT a capability
                 inventory — the parity walk caught three feature losses inside the
                 approved design. RULE: one .ambientPush per view; two push targets
                 means an enum destination.
      ✅ AMB.4   Home dashboard + the bottom tab bar   DONE + smoked both 2026-07-26.
                 LESSON: SHELL surfaces (bars, toolbars, toasts) belong to no feature
                 phase and both drift-finding mechanisms were blind to them —
                 enumerate the shell deliberately, don't wait to be asked.
      ✅ AMB.5   Tasks                DONE + PUSHED 2026-07-26
      ✅ AMB.6   Chat                 SHIPPED + PUSHED 2026-07-26, both smokes PASSED.
                 Chat had NOT WORKED SINCE SEP 2025 — the conversations query could
                 never succeed and the failure rendered as an EMPTY LIST. A FAILURE
                 PRESENTABLE AS AN EMPTY STATE WILL HIDE INDEFINITELY. Ten more
                 data-layer defects fixed; two live shared-DB changes.
      ✅ AMB.7   Reports family       DONE + PUSHED 2026-07-27. Seven screens, TEN
                 files deleted in the same commit. Origin of the lab-imports-
                 production-code mechanism, the compiled rule checks (76) and the
                 scripted parity walk (103 checks, run three times before showing
                 the operator).
      ✅ AMB.8   Time off             SHIPPED 2026-07-27 (88d01a1..fb46e32), OPERATOR
                 SMOKE PASSED iPHONE AND iPAD, /code-review run twice.
                 Five surfaces converted; TimeOffKit owns the shared components and
                 the lab imports them; TimeOffRules has 121 compiled-and-run checks
                 (every rule proved to fail when broken — nine mutations); the
                 parity walk is a script, 144 checks.
                 NINE FIX ROUNDS, TWELVE AUDITS, EVERY AUDIT FOUND A REAL DEFECT.
                 Four payroll bugs were INTRODUCED by the conversion and caught
                 before ship — a deleted double-submit guard (two taps debit 96
                 hours for a 48-hour request) and PTO hours frozen at zero for
                 web-created requests were the worst. Recurring shape: fixing the
                 instance an audit named instead of sweeping the class.
                 The audit that LEFT THE REPO found the most, second phase running:
                 the two clients share ZERO reason strings; web denials stamp the
                 APPROVAL columns; partially_approved rendered as a live "Pending".
                 Everything payroll/authorization it surfaced was RECORDED, NOT
                 FIXED — TOF.1 owns it; a style phase must not move an authorization
                 boundary in either direction.
                 ⚠️ CARRY-FORWARD: BATCH-3 MOCKUPS NOT BUILT. The source inventories
                 for Mileage/Stats and Groups/Yearbook were gathered in-session but
                 are not a repo document. AMB.9 starts by writing the inventory doc,
                 then mocks — named as unbuilt rather than half-done, AMB.6's call.
        ── batch 3 ── to be inventoried + mocked at the start of AMB.9 ──
      ⬜ AMB.9   Mileage + Stats      + mocks batch 3 (inventory doc FIRST — above)
      ⬜ AMB.10  Groups + Yearbook    (17 views)  + mocks batch 4
        ── batch 4 ──
      ⬜ AMB.11  Job box / NFC        (18 views)
      ⬜ AMB.12  Settings, Manager, Training — the tail (D9). Closes the arc and
                 DELETES the lab harness + its menu entry.
      ⛔ Sports Shoot Feature is PERMANENTLY out of scope for this arc (D1) — protected
         Captura files + a live iPad shoot tool.

  🔔 PSH — push notifications that reach a phone   (REGISTERED ARC: PSH.1 ✅, PSH.2 ⬜)
      ✅ PSH.1   SHIPPED + PUSHED 2026-07-27, verified end to end on a real device
                 (sent: 0, failed: 1 before → sent: 1, failed: 0 after; operator
                 confirmed arrival). Push works for the FIRST TIME. The bug was an
                 APNs sandbox-vs-production environment mismatch — fixed by
                 recording the environment WITH each token (users.apns_environment)
                 and routing per token; NEVER fix it by flipping the global flag,
                 which cannot serve a dev build and a TestFlight build at once.
                 One canonical send-notification (service-role ONLY — it accepts
                 arbitrary recipients and text on a multi-tenant DB, and deploying
                 dormant code is a behaviour change); triggers live IN THE DATABASE
                 (trg_session_notification, trg_time_off_notification) because the
                 one path that ever worked was built that way; the dead
                 notification_queue/FCM machinery is deleted.
                 THE LESSON THAT GENERALISES: FOUR mechanisms had never been wired,
                 every one invisible from the repo because the code looked correct
                 while targeting a column or table that DOES NOT EXIST. Grep the
                 DATABASE, not the repo. Memory: psh-push-notifications — which
                 also carries the live-DB query recipe.
      ⬜ PSH.2   NOTIFICATION COVERAGE — scope confirmed by the operator 2026-07-28.
                 (The old AUDIT_ROADMAP "PSH.2" heading was eight unrelated items
                 parked at PSH.1's close, NOT a phase scope; the flag feature and
                 the two broken web notification writers from that list were already
                 fixed as FLG.1. What the name covers now:)
                 - SIX push types still cannot fire: chat message, clock-in
                   reminder, clock-out reminder, daily report reminder, photo
                   critique, job box. The senders exist — chat-notification and
                   clock-reminder are DEPLOYED (v2, code corrected in PSH.1) — but
                   NOTHING CALLS THEM: no trigger, no cron. Turning each on is a
                   deliberate behaviour change per type, wired in the database per
                   PSH.1's architecture decision.
                 - ONE apns_token column per person: an iPhone+iPad user is
                   reachable only on the last device that registered. Real fix: a
                   user_devices table keyed by token, carrying the environment;
                   every sender fans out over it.
                 - A tapped push does not navigate anywhere — of every notification
                   name the app posts, only didReceiveJobBoxNotification has an
                   observer (ShiftDetailView).
                 - Time-off reasons (can be medical/family detail) land on the lock
                   screen. Needs a decision; the lever is per-type notification
                   preferences, which do not exist. The flag trigger already
                   answered this conservatively for its own type (note kept
                   in-app, off the lock screen) — decide deliberately, not by copy.
                 - Cleanups: drop the orphaned users.fcm_token_updated_at column
                   (destructive on a shared table — own impact trace + sign-off);
                   fix the stale DB credentials in the web repo's .env.local; and
                   REWRITE the stale PSH.2 section of AUDIT_ROADMAP.md (it still
                   claims chat-notification/clock-reminder are undeployed).

  ⚪ NOT STARTED   (proposed codes — each is registered in PHASES.md when you start it)
      TOF.1   TIME OFF AUTHORIZATION + PTO INTEGRITY. Payroll-adjacent, NOT design
              work, deliberately excluded from AMB.8. The big two:
              1. TimeOffApprovalView HAS NO PERMISSION CHECK AT ALL — anything that
                 selects that tab reaches live approve/deny buttons on every
                 employee's requests. TimeOffService.canManageRequests() exists,
                 does the right check, and is never called.
              2. PTO SHORTFALLS ARE SWALLOWED — reservePTOHours throws and the
                 caller prints a warning and creates the request anyway; the same
                 swallow on release and on deduct; updateTimeOffRequest never
                 adjusts an existing reservation.
              Plus AMB.8's recorded findings, all TOF.1's now: the ownership check
              reads a UserDefaults "userID" key nothing writes (a photographer
              cannot cancel their own time off); organizations.pto_settings is
              written snake_case by the web and decoded camelCase by iOS (every
              admin-configured accrual rate silently ignored); web approve/deny
              NEVER releases pending_balance (the web's whole PTO write surface is
              dead code); pto_balances.used is written by nobody; iOS "underReview"
              vs web 'under_review' (an iOS put-in-review request vanishes from the
              web queue); TimeOffService inserts UPPERCASE uuids; sign-out leaks
              currentUserId/currentOrgId into the next sign-in. PTO HAS NEVER
              ACTUALLY FUNCTIONED — establish what is real before trusting any
              number on a payroll screen.
              BUILD NOTES FROM FLG.2 (2026-07-28) — use them:
              - The worked pattern for privileged writes is flag_user/unflag_user:
                SECURITY DEFINER RPC, permission via the role_permissions helpers,
                same-org check, self check, row-count assert. Copy that shape.
              - Any RLS helper used inside plpgsql MUST be wrapped
                coalesce(..., false) — is_user_admin() returns NULL for a JWT with
                no users row, and NULL denies inside a USING clause but FAILS OPEN
                inside IF NOT.
              - The UI gate and the DB policy can disagree: users_update_org lets a
                non-admin update only their OWN row regardless of what
                Permissions.has grants. Check BOTH sides of every write.
              Server auth via role_permissions + has_permission(); read the
              rls-remediation memory before touching it. Detail: AMB_BATCH2_PARITY.md
              + the TOF.1 section of AUDIT_ROADMAP.md.
      OFF.1   The offline schedule. The disk cache has NEVER worked on any device:
              loadMetadata decodes with a bare JSONDecoder while the save side
              writes ISO-8601 text, so every read concludes there is no cache. Same
              bug in TimeEntryCacheManager. PowerSync considered and REJECTED (O1).
              Scope: both decoders, a bounded window at the cache WRITE (never the
              query — 8 callers share it), failure visibility (O5: a failed read
              must not look like an empty cache), round-trip proofs. REGISTERED
              arc. Plan: OFFLINE_SCHEDULE_PLAN.md.
      OFF.2   Shift detail offline — SchoolService reads schools from Supabase
              though the data is ALREADY on the device in PowerSync; nothing reads
              it. Weather stays online by choice.
      DEC.1   Decompose the god files (DashboardWidgets; the Sports monoliths).
      DJR.1   Daily Job Report — draft auto-save + offline outbox. NO WIZARD
              (operator rejected 2026-07-26; evidence in AUDIT_ROADMAP). AMB.7's
              approved design is ONE screen where nothing collapses; what remains
              is the data layer: draft auto-save (leaving the form discards
              everything typed) and an offline outbox (a no-signal submit loses the
              report). Overlaps AMB.7's screens — sequence deliberately.
      ONB.1   Invite-code onboarding + sign-in hardening.
      TST.1   Tests for the money paths (TimeEntryValidator, PayPeriodService).
      CHT.1   Chat data-layer rebuild — MULTIPLATFORM, its own arc. Findings:
              CHAT_REBUILD_NOTES.md. Every chat defect is two clients disagreeing
              about one column; the fix moves truth INTO the database (participants
              join table, unread derived from per-person last_read_at, all writes
              through RPCs). NEEDS FIRST: the web app's chat code read properly, a
              real answer on whether Captura touches chat, the architecture gate
              written out.
      GIC.1   Group-images conflict handling (version-checked, not last-write-wins).
      SEC.*   iOS data protection — folds into the family SEC arc. The candidate
              list GREW during FLG.1/AUD.2, all recorded in AUDIT_ROADMAP:
              flag_note is still readable by ANY signed-in employee straight from
              PostgREST (RLS filters rows, not columns — needs a column grant or a
              manager-gated table); four more RLS-off tables carry authenticated
              SELECT (two backup tables that REPOPULATE, access_code_pricing,
              archive_step_legacy_fields — RLS_AUDIT §181); the audit triggers
              swallow failed inserts at NOTICE, which log_min_messages discards, so
              a failing audit write is invisible; FlaggedStatusView is dead code
              (no mount point) writing two MORE non-existent columns — delete it or
              build it, it is the flagged person's only route to respond to a flag.

  ✅ DONE   (closeouts in AUDIT_ROADMAP.md)
      FLG.1/FLG.2 + AUD.2   User flagging + audit-log tenant isolation — SHIPPED +
              PUSHED 2026-07-28, operator smoke PASSED ("it all worked").
              FLAGGING A USER HAD NEVER WORKED: TeamService wrote three columns to
              the shared users table and only is_flagged existed, so PostgREST
              rejected the whole UPDATE — no one was ever flagged, and before the
              fix the failure was at least loud; making the columns exist without
              the zero-row check would have turned it into a silent false success.
              Columns added; the notification trigger rebuilt from PSH.1's
              recovered payload (PSH.1's own migration was applied live and NEVER
              COMMITTED — check before promising to recover anything from git);
              managers can flag via flag_user/unflag_user SECURITY DEFINER RPCs
              (widening users_update_org was REJECTED — it governs the whole row).
              Operator decision on record: ANYONE is flaggable, admins included.
              AUD.2 closed a pre-existing CRITICAL found by the FLG.1 security
              audit: the audit_log partitions had RLS OFF with authenticated
              SELECT, so any employee could read every tenant's users rows (pay
              rates, APNs tokens, flag notes) by querying a partition directly —
              proven live, then closed: RLS on all ten partitions AND on every
              future partition at creation time, because fixing the tables without
              patching the CREATOR reopens the hole next month while looking done.
      AMB.1–AMB.8, PSH.1 — see the arc blocks above.
      PUB.1   Draft visibility — SHIPPED + PUSHED 2026-07-25, closes the PUB arc.
              Lesson: a redaction is only as good as the number of STORES it
              covers, not call sites.
      CRS.1   Captura roster save hardening — DONE + PUSHED 2026-07-23; all 4 loss
              paths fixed in both protected editors via the hook-lift procedure.
      NAV.1   Navigation restructure — SHIPPED 2026-07-14, verified iPhone + iPad.
              One nav bar per screen.
      Pre-arc (July 2026):  RLS security fixes (live)  ·  SessionService perf  ·
              PoserStation memo  ·  design tokens (partial)  ·  the 5 missing chat
              RPCs.


# ⚙️ The workflow  (the agent runs this)

  0  SYNC
     git fetch origin; confirm local main == origin/main. Never a blind pull or
     reset — review git log HEAD..origin/main first.

  1  FIND THE ARC
     Match the request to an arc/item in AUDIT_ROADMAP.md (or the family registry).
     If described in words, name the arc you matched and confirm. If it is new
     work, register a new arc in FocalPointProduction/docs/PHASES.md before any
     code. A HEADING IS NOT A PHASE: the old PSH.2 roadmap section was eight
     unrelated items parked under one label, and building "item one of the heading"
     cost a mid-session rescope. If the matched entry is a parking lot, say so and
     confirm WHICH item is the phase before researching.

  2  RESEARCH FIRST  (before writing anything)
     Read the ACTUAL code and trace the real execution path — parallel research
     agents for non-trivial work. No guessing; never describe code from its name.
     THE LIVE DATABASE IS THE AUTHORITY — not the repo, not DATABASE_SCHEMA.md
     (stale twice over). PSH.1 found FOUR mechanisms that were never wired, each
     invisible from the repo because the code looked correct while targeting a
     column or table that does not exist; FLG.1 found two more in the same shape.
     Verify every column you will touch, live. psql DOES NOT WORK on this project —
     the recipe (Supabase Management API + the CLI's keychain token) is in the
     psh-push-notifications memory. Grep for the WRITER, not the reader: ten
     handled types says nothing about whether ten types are ever sent. When the
     operator says a feature does not work, believe them and find WHY — the code
     will look right; that is the whole problem.
     Architecture decisions pass the plain-English decision gate first. Resolve
     small build choices from the plan; surface only a real safety/data-loss risk
     or a locked-decision conflict.

  2b MOCK IT FIRST  (AMB arc — hard gate; skip only for non-AMB work)
     Build the phase's views as a MOCKUP in the lab harness, mounted in the REAL
     shell's nav container (never its own NavigationStack — that is why AMB.1's
     lab could not catch a dead tap). Preferred form since AMB.7: the design is
     PRODUCTION components the lab IMPORTS (TimeOffKit is the worked example) —
     then there is no matching step and nothing to drift. The operator reviews ON
     A DEVICE. DO NOT TOUCH THE REAL SCREENS UNTIL THEY APPROVE.

  3  BUILD IT RIGHT THE FIRST TIME
     Match existing patterns exactly. No hacks/patches — fix the root cause.
     Delete-first: the old path dies in the same commit.
     Hard constraints:
       - Lowercase UUIDs on every comparison — WITH ONE EXCEPTION, learned the
         hard way in FLG.1: users.id is TEXT and one row is a mixed-case legacy
         Firebase uid. NEVER .lowercased() a value that came out of a text id
         column; pass it through as stored. A PostgREST UPDATE matching zero rows
         returns 200 — lowercasing that id reports success and does nothing.
       - PowerSync: no JOINs/subqueries; single-table SELECTs; denormalize
         organization_id onto child tables.
       - NEVER edit the protected Captura files (hook-enforced; see the
         protected-captura-files memory). FP Sports work is additive, in new files.
       - Server-side auth goes through role_permissions + has_permission().
         Privileged writes go through SECURITY DEFINER RPCs (flag_user is the
         worked example), and any RLS helper used inside plpgsql is wrapped
         coalesce(..., false) — NULL denies in USING but FAILS OPEN in IF NOT.
       - Explicit SELECT column lists on shared tables that carry a sensitive
         column — SELECT * starts shipping a new column to every client the moment
         the column exists. But a column list is NOT access control (RLS filters
         rows, not columns); truly restricting a read needs a grant or a gated
         table.

  3b MATCH THE MOCKUP  (AMB arc — do not skip)
     Put the converted screen next to the approved mockup and account for EVERY
     difference: interaction, frames, spacing, sizes, states, empty cases.
     Anything that differs is restored or named to the operator as deliberate.
     Make the walk a SCRIPT (parity_timeoff.sh: 144 checks, re-run every fix
     round, itself proved able to detect a loss) — writing the parity doc does not
     protect anything; only running it against the new screen does.

  4  AUDIT  (parallel agents)
       - Code: correctness, edge cases, Swift concurrency + SwiftUI lifecycle.
       - Security: Supabase RLS/auth on the SHARED DB, PII, secrets, blast radius
         onto the web app + Captura.
       - Data/Sync: PowerSync integrity, offline behavior, no data loss.
     Give at least one audit an explicit instruction to LEAVE THE REPO — the
     out-of-repo audit has found the most, multiple phases running. Fix every
     critical/high now.

  4b AUDIT THE FIX ROUND — TREAT IT AS A LAW, NINE PHASES RUNNING
     After fixing what an audit found, run a SEPARATE adversarial audit aimed
     specifically at the fix round's diff. It has found the phase's WORST defect
     in PUB.1, AMB.4, AMB.5, AMB.6 (twice), AMB.7 (twice), AMB.8, FLG.1 and
     FLG.2 — including a permission guard that failed open on NULL and a SELECT*
     fix applied to one site while a second site kept leaking. REPEAT UNTIL AN
     AUDIT COMES BACK CLEAN. The recurring shape is fixing the INSTANCE an audit
     named instead of sweeping the CLASS — after any fix, grep for every other
     site of the same hazard and say in the commit whether each was fixed.

  5  VERIFY BY RUNNING IT  (not by reading the diff)
       - Build clean: xcodebuild -> BUILD SUCCEEDED, no new warnings.
       - The operator runs the changed flow (iPhone AND iPad where relevant; AMB
         arc: both mandatory every phase, D7). If it can't run on the dev machine,
         say so and give exact test steps.
       - Re-grep the old pattern to confirm the change landed.
       - Live-DB changes (shared Supabase): reversible, read-back verified,
         nothing destructive without sign-off. FIRE EVERY NEW TRIGGER ONCE against
         a real row — plpgsql does not validate column references until the
         trigger RUNS; a trigger that installs cleanly can still raise and roll
         back every write to a shared table (PSH.1 shipped one; FLG.1 nearly did).
         The safe recipe: a DO block inside a transaction that RAISEs at the end
         so everything rolls back — observed values come back in the error text,
         nothing persists, and counting net.http_request_queue rows shows whether
         it fired. Sabotage-test error handlers the same way. QUEUED IS NOT
         DELIVERED — end-to-end device delivery is the operator's smoke.
       - Any check added as evidence must be PROVED ABLE TO FAIL: break the thing,
         watch it go red, restore it. AMB.8 ran nine such mutations.

  6  HIGH-STAKES -> run the review yourself
     If it touches Supabase RLS/auth, PowerSync/offline integrity, payroll
     (time_entries / PTO), the protected Captura roster editing, the nav shell,
     or a whole daily-use surface (an AMB conversion phase counts):
     run the code-review skill (high/max) yourself as the final step, BEFORE ANY
     PUSH (once merged there is no branch delta left to bundle), fix findings,
     deliver a plain-English report. Do not ask the operator to trigger it.

  7  CLOSE OUT  (do it, don't ask)
       - Commit onto main — branch first for high-blast-radius work. git fetch +
         review HEAD..origin/main first. Stage files BY PATH — never git add -A;
         a parallel session may share this working tree. End the message with the
         Co-Authored-By line below.
       - Check off the item + dated closeout note in AUDIT_ROADMAP.md; update the
         arc's status in FocalPointProduction/docs/PHASES.md; update memory.
       - Report in plain English: what changed, the evidence, the one thing only
         the operator can confirm (the on-device run).
       - PUSH ONLY WHEN THE OPERATOR ASKS. Committed-but-not-pushed is the safe
         state. EXCEPTION, standing: the AMB arc ships each phase to main as it
         lands (D8) — push once the review and BOTH device smokes pass, without
         asking again. Per-arc; does not generalize.

  THROUGHOUT: if the auto-mode classifier blocks an action, SAY SO IMMEDIATELY —
  name the action, why it was needed, and the remedy (Shift+Tab out of auto mode,
  say try again, Shift+Tab back) — BEFORE continuing or working around it. A hook
  in .claude/settings.local.json tells the operator THAT a block happened; saying
  WHAT and WHY is the agent's job. The two previously-recurring blocks
  (sibling-repo git, the Supabase Management API recipe) are allowlisted as of
  2026-07-28 and should no longer occur.


# 📖 Read first  (open the files — the titles are not the rules)

  1  CLAUDE.md (repo root) — hard rules + project lessons (lowercase UUIDs,
     protected Captura files).
  2  Memory index ~/.claude/projects/-Users-jason-Desktop-employeeapp/memory/MEMORY.md
     -> the titles are not the rules: open the linked feedback_*.md files, plus
     protected-captura-files, powersync-setup, rls-remediation-2026-07,
     psh-push-notifications (the live-DB query recipe), flg-user-flagging,
     project-structure.
  3  AUDIT_ROADMAP.md — the item's scope + any linked plan doc (RLS_AUDIT.md,
     OFFLINE_SCHEDULE_PLAN.md, CHAT_REBUILD_NOTES.md, DATABASE_SCHEMA.md).
  4  FocalPointProduction/docs/PHASES.md — the family arc registry (the naming rule).


# 🧭 Project facts

  Working dir   ~/Desktop/employeeapp/
  App           SwiftUI iOS, iPhone + iPad, min iOS 16.6 (NavigationStack
                available; the app still uses NavigationView)
  Backend       Supabase nofegnmrgnanpznavlqy — SHARED with the web app
                (~/Desktop/Focal-Point-Supabase) + Captura; any DB change can
                affect them. PowerSync offline-first for the Sports roster.
  Live DB       psql DOES NOT WORK (host gone, stale passwords, no Docker). Use
                the Supabase Management API with the CLI's keychain token — exact
                recipe in the psh-push-notifications memory. The LIVE database is
                the authority; DATABASE_SCHEMA.md has been stale twice.
  Build         xcodebuild build -workspace "Iconik Employee.xcworkspace"
                -scheme "Iconik Employee"
                -destination "platform=iOS Simulator,name=iPhone 17 Pro"
  Branch        main
  Commit        end with — Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>

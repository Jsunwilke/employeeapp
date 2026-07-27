# Start a Phase — Iconik Employee

Reusable kickoff. Paste this whole file into a new session, write ONE line under
START HERE, and the agent runs the phase end to end. One phase per session.

Iconik Employee is the iOS app of the Focal Point family: SwiftUI (iPhone + iPad),
Supabase backend shared with the Focal Point web app + Captura, PowerSync
offline-first for the Sports roster. Same building/research standards, same
phase-naming registry as the rest of the family.


# 🚀 START HERE  (you, the operator)

      WHAT TO BUILD:  AMB.6's leftover — build the BATCH 2 MOCKUPS
                      (Reports family + Time off) in the lab for approval

  ⚠️ READ THIS BEFORE ANYTHING ELSE. These mockups belong to AMB.6 (D10) and AMB.6
  did not build them — the phase went entirely into repairing Chat, which turned
  out never to have worked. Do NOT convert a real Reports or Time Off screen: D10
  is a hard gate and nothing has been approved.

  START FROM AMB_BATCH2_PARITY.md, which already exists. Its Time Off half is
  COMPLETE, read from source. Its Reports half is NOT — the file says so — and the
  Reports capability detail must be re-derived from source before drawing.

  AMB_BATCH2_PARITY.md also records ELEVEN non-style findings, and two of them are
  payroll-adjacent and should be raised with the operator early rather than folded
  silently into a design phase: TimeOffApprovalView has NO permission check at all
  (and the row that reveals it checks the wrong permission area), and PTO shortfall
  errors are swallowed so a request is created even when the balance is
  insufficient.

  An arc id (e.g. NAV.1) or just describe the item in plain words. That is the only
  line you fill in — the agent works out the exact phase and scope.

  KEEP THIS BLOCK EMPTY unless there is something the roadmap does not already say.
  It went stale during AMB.3 — it still described mockup work that had been built and
  approved two sessions earlier, which sent that session hunting for finished work.
  The phase list below and AUDIT_ROADMAP.md are the sources of truth; this line is not.


# 📋 Phases

  Named by arc code (ARC.N) per the family registry, FocalPointProduction/docs/PHASES.md.
  Full per-item scope + closeouts live in AUDIT_ROADMAP.md.

  🎨 AMB — Ambient design language rollout   (REGISTERED ARC, in progress)
      IT IS A REDESIGN WITH A PARITY CONSTRAINT (D12, operator 2026-07-25 — this
      SUPERSEDES the "restyle only" framing this file used to carry). IN scope: layout,
      hierarchy, information architecture, the reading order of a list, states that
      should exist and do not. OUT of scope, unchanged: data layers, services, loaders,
      caching, business rules and permissions, the shared Supabase schema/RLS/PowerSync.
      NO FEATURE MAY BE LOST, and that is checkable rather than promised — inventory the
      surface's capabilities FROM THE SOURCE before redesigning it (AMB_BATCH1_PARITY.md
      is the worked example; it caught eight feature losses across AMB.2 and AMB.3,
      three of them inside a design the operator had already approved).
      Every phase SHOWS A RUNNING SWIFTUI MOCKUP FOR OPERATOR APPROVAL BEFORE THE
      REAL SCREENS ARE TOUCHED (D10 — hard gate), and the approval must be ON A DEVICE.
      The mockups live in ONE lab harness built in AMB.2 (menu entry + sample data +
      gallery + switcher, in the real nav container), kept for the arc and deleted at
      AMB.12; each phase's own mockup views go at that phase's close. Smokes on iPhone
      AND iPad (D7); ships to main as it lands (D8).
      Plan + the 12 locked decisions (D1-D12): AMBIENT_ROLLOUT_PLAN.md. Scope/closeouts: AUDIT_ROADMAP.md.
      D11 (2026-07-25): the ambient wash takes each screen's FEATURE colour; the schedule
      keeps its data-driven tint as the exception. FeatureTheme's palette must be re-cut to
      be unique first (5 blues today) — proposed in AMB.2 session 2's mockups. Re-cutting it
      also changes the home tiles + bottom bar, which are live.

      ✅ AMB.1   Schedule                                    DONE + PUSHED 2026-07-24
      ✅ AMB.2   Design system + build gate + compact variants + THE LAB
                 DONE + PUSHED 2026-07-25 (3 sessions). DesignSystem/ primitives,
                 cardStyle() deleted, the card-drift gate, the lab, the D11 palette
                 (27 distinct feature colours — LIVE on home tiles, All Features and
                 the bottom bar), compact chosen as the density (D5), and all six
                 batch-1 mockups. Operator approved the batch-1 designs ON A DEVICE,
                 iPhone AND iPad — closing D10 and D7 for the batch.
        ── batch 1 ── mocked in AMB.2, reviewed in ONE sitting ──
      ✅ AMB.3   Equipment            DONE + PUSHED 2026-07-25, smoked iPhone + iPad.
                 One screen replaced the two-tab container. Proved the compact set.
                 LESSON FOR EVERY REMAINING PHASE: an approved mockup is a design
                 decision, NOT a capability inventory — the parity walk caught three
                 feature losses inside the design the operator had already signed off.
                 Check the redesign against the SOURCE, including approved parts.
                 RULE: one .ambientPush per view; two push targets means an enum
                 destination (two stacked NavigationLink(isActive:) is the AMB.1
                 dead-tap shape).
      ✅ AMB.4   Home dashboard + THE BOTTOM TAB BAR
                 DONE + smoked iPhone AND iPad 2026-07-26. Both allowlist rows deleted.
                 THE BAR WAS NOT IN THE PLAN: it belonged to no phase, because this list
                 is organised by FEATURE and the bar is SHELL — and the drift gate could
                 not catch it either, since a full-width bar is not a card. Two ways of
                 finding unconverted surfaces, both blind to it; the operator asking is
                 what found it (D13 folded it in).
                 ⚠️ BEFORE STARTING AMB.5: enumerate the rest of the SHELL the same way
                 — the profile toolbar, the theme picker, the toast, anything else that
                 appears on screens no phase owns. Do it deliberately rather than
                 waiting to be asked a second time.
                 LESSON: I cannot run the app (the lab needs a signed-in Supabase
                 session), and four operator smokes each found something a green build
                 could not. Instrument or reason it through BEFORE shipping, and never
                 leave a KNOWN regression for "its own phase".
      ✅ AMB.5   Tasks                DONE + PUSHED 2026-07-26
      ✅ AMB.6   Chat                 CONVERTED + DATA LAYER REPAIRED 2026-07-26,
                 commits de1eed5..58c4299, NOT PUSHED. Chat had NOT WORKED SINCE
                 SEP 2025: the conversations query could never succeed (a Swift
                 array became a Postgres array literal `{uuid}` against a JSONB
                 column, so Postgres answered "invalid input syntax for type json"
                 every time) — and the failure was reported as an EMPTY LIST, so
                 it hid for a year behind "No conversations". A FAILURE THAT IS
                 PRESENTABLE AS AN EMPTY STATE WILL HIDE INDEFINITELY. Ten more
                 data-layer defects fixed; two live shared-DB changes applied.
                 ⚠️ TWO CRITERIA UNMET, deliberately named: the iPad smoke was
                 NOT run (D7), and BATCH-2 MOCKUPS WERE NOT BUILT — they move to
                 the START of AMB.7, which D10 blocks until they exist. The
                 batch-1 mockup and its parity/research docs are therefore NOT
                 deleted yet.
                 LESSON: auditing my own FIX round found the worst defect five
                 phases running. Rounds one and two each introduced a new bug
                 while closing an old one — one a critical, one a message-loss
                 path. Never ship a fix round unaudited, and slow down instead.
        ── batch 2 ── ⚠️ NOT YET MOCKED — AMB.7 must build them before it starts
      ⬜ AMB.7   Reports family       (daily job report, custom, mine, photoshoot notes)
                 ⚠️ CARRIES BATCH-2 MOCKUPS (Reports + Time off) inherited from
                 AMB.6. D10 is a hard gate: no real screen until they are approved.
      ⬜ AMB.8   Time off             (8 views)   + mocks batch 3
        ── batch 3 ──
      ⬜ AMB.9   Mileage + Stats
      ⬜ AMB.10  Groups + Yearbook    (17 views)  + mocks batch 4
        ── batch 4 ──
      ⬜ AMB.11  Job box / NFC        (18 views)
      ⬜ AMB.12  Settings, Manager, Training — the tail (D9). Closes the arc and
                 DELETES the lab harness + its menu entry.
      ⛔ Sports Shoot Feature is PERMANENTLY out of scope for this arc (D1) — protected
         Captura files + a live iPad shoot tool.

  ⚪ NOT STARTED   (proposed codes — each is registered in PHASES.md when you start it)
      OFF.1   The offline schedule. The schedule's disk cache has NEVER worked, on any
              device, since the file was written: loadMetadata decodes with a bare
              JSONDecoder while the save side writes ISO-8601 text, so every read
              concludes there is no cache. Same bug in TimeEntryCacheManager. So: no
              cached first paint, the "Offline - last synced" banner can never appear,
              and offline the schedule throws instead of showing anything. PowerSync was
              considered and REJECTED (O1) — read-only need, and adding sessions costs a
              shared-DB schema change plus a sync-rule deploy that hits the live web app.
              Scope is both decoders, a bounded window applied at the cache WRITE (never
              the query — 8 callers share it), failure visibility (O5: a failed read must
              not look like an empty cache — that is why a typo survived 5 months), and
              round-trip proofs. REGISTERED arc. Plan: OFFLINE_SCHEDULE_PLAN.md.
      OFF.2   The shift detail offline — SchoolService reads schools from PowerSync
              instead of Supabase, so address and travel work with no signal. The data is
              ALREADY on the device; nothing reads it. Weather stays online by choice.
      DEC.1   Decompose the god files (DashboardWidgets; the Sports monoliths).
              NOTE: overlaps AMB.4 (home dashboard) on DashboardWidgets.swift — whichever
              runs first wins, the other rebases onto it.
      DJR.1   Daily Job Report redesign (wizard, draft auto-save, offline outbox).
              NOTE: overlaps AMB.7 (reports family) on the same screens — sequence
              deliberately.
      ONB.1   Invite-code onboarding + sign-in hardening.
      TST.1   Tests for the money paths (TimeEntryValidator, PayPeriodService).
      CHT.1   Chat data-layer rebuild — MULTIPLATFORM. Findings: CHAT_REBUILD_NOTES.md
              (written at AMB.6's close). Every chat defect AMB.6 found is two
              clients disagreeing about the same column: participants held as a
              jsonb blob with no foreign keys, unread counts stored as a number
              that BOTH the iOS app and the web app read-modify-write, and message
              type guessed by searching the message text for ".jpg". The fix is to
              move truth INTO the database — a participants join table, unread
              DERIVED from a per-person last_read_at, all writes through RPCs — so
              no client can contradict another. Cheapest it will ever be: 14
              conversations, most of the data already dead, dormant since Sep 2025.
              NEEDS FIRST: the web app's chat code read properly, a real answer on
              whether Captura touches chat (currently an inference), and the
              architecture gate written out. Its own arc, not an AMB phase.
      GIC.1   Group-images conflict handling (version-checked, not last-write-wins).
      SEC.*   iOS data protection (at-rest DB encryption, PII out of UserDefaults,
              LAN TLS) — folds into the existing family SEC arc, not a new code.

  ✅ DONE   (closeouts in AUDIT_ROADMAP.md)
      AMB.3   Equipment — the two tabs became ONE screen: your gear leads under a
              standing line saying what is out, due back and LATE (the app could only
              tell you by reading every kit card), the inventory is one row down or one
              keystroke away, the kit detail is a packing list opening EXPANDED in the
              app's own photography workflow order, and the item detail leads with
              status/holder/due instead of a 250pt photo. Six files deleted in the same
              commit. THREE dead controls fixed (an "Other Equipment" tap handler that
              was an empty comment; a "Browse Equipment" button posting a notification
              nothing observed; a malformed user id falling back to a random UUID).
              /code-review run by the operator BEFORE the push: 4 findings, 3 fixed, 1
              REFUSED with a reason (overdue-at-midnight is a business rule, not a
              restyle's to change — fixed afterwards as its own commit, pinned by 9
              tests). Operator smoke PASSED iPhone + iPad. SHIPPED 2026-07-25.
      PUB.1   Draft visibility — photographers see UNPUBLISHED sessions, grouped under
              their own "Not published yet" heading, with NO assignment shown on a draft
              (not others', not their own) for anyone without schedule-edit rights;
              staffing temperature deleted for everyone. BUILT 2026-07-25, OPERATOR SMOKE
              PASSED 2026-07-25; committed to main, push is the operator's call. Closes
              the PUB arc. Client-only: one .eq dropped from one query, no
              schema/policy/write change; /security-review no HIGH or MEDIUM. Three
              audit-found defects fixed in-phase that the plan never anticipated — the
              offline cache silently dropping every draft, an async-permissions race
              that could have let a manager save an empty roster, and the job box
              naming a person on a draft. Plan: DRAFT_VISIBILITY_PLAN.md.
      AMB.1   Schedule converted to the Ambient design language — ScheduleView +
              ScheduleRows + ScheduleStyleKit replace SlingWeeklyView (deleted same
              commit), ShiftDetailView restyled with its data layer untouched.
              SHIPPED to origin/main 2026-07-24 (b3a82e1..97324a4); operator smoke
              PASSED on iPhone; 8 code-review findings all fixed (5 were regressions
              the arc introduced). RESIDUAL: iPad smoke never run — D7 was adopted
              after this phase shipped. Plan: AMBIENT_ROLLOUT_PLAN.md.
      CRS.1   Captura roster save hardening — all 4 pre-existing loss paths from the
              6bf00ba post-ship review fixed 2026-07-23 (both protected editors, hook
              lifted with operator authorization + restored). 2 audits, 0 crit/high.
              Operator device smoke pending; capture-vs-shoot-switch debounce loss
              recorded as a follow-on candidate. Plan: CAPTURA_ROSTER_HARDENING_PLAN.md.
      NAV.1   Navigation restructure — one nav bar per screen; Home = top-left button per feature
              (iPhone) / large center bottom-bar button (iPad). SHIPPED 2026-07-14 to origin/main,
              verified on-device iPhone + iPad. TabView/typed-routes/deep-links deferred by plan.
      Pre-arc (July 2026):  RLS security fixes (live)  ·  SessionService perf  ·  PoserStation
              memo  ·  design tokens (partial)  ·  the 5 missing chat RPCs.


# ⚙️ The workflow  (the agent runs this)

  0  SYNC
     git fetch origin; confirm local main == origin/main. Never a blind pull or
     reset — review git log HEAD..origin/main first.

  1  FIND THE ARC
     Match the request to an arc/item in AUDIT_ROADMAP.md (or the family registry).
     If described in words, name the arc you matched and confirm. If it is new work,
     register a new arc in FocalPointProduction/docs/PHASES.md before any code.

  2  RESEARCH FIRST  (before writing anything)
     Read the ACTUAL code and trace the real execution path — parallel research
     agents for non-trivial work. No guessing; never describe code from its name.
     Architecture decisions pass the plain-English decision gate first. Resolve
     small build choices from the plan; surface only a real safety/data-loss risk
     or a locked-decision conflict.

  2b MOCK IT FIRST  (AMB arc — hard gate; skip only for non-AMB work)
     Build the phase's views as a MOCKUP in the lab harness with sample data,
     mounted in the REAL shell's nav container (never its own NavigationStack —
     that is why AMB.1's lab could not catch a dead tap). Batch phases mock
     several surfaces at once: see D10 for which batch this phase carries.
     The operator reviews it ON A DEVICE. DO NOT TOUCH THE REAL SCREENS UNTIL
     THEY APPROVE. A rejected mockup is re-cut here, where it costs minutes.

  3  BUILD IT RIGHT THE FIRST TIME
     Match existing patterns exactly. No hacks/patches — fix the root cause.
     Delete-first: the old path dies in the same commit.
     Hard constraints:
       - Lowercase UUIDs on every comparison.
       - PowerSync: no JOINs/subqueries; single-table SELECTs; denormalize
         organization_id onto child tables.
       - NEVER edit the protected Captura files (hook-enforced; see the
         protected-captura-files memory). FP Sports work is additive, in new files.
       - Server-side auth goes through role_permissions + has_permission()
         (see the rls-remediation memory).

  3b MATCH THE MOCKUP  (AMB arc — do not skip; this is where two defects got out)
     Put the converted screen next to the approved mockup and account for EVERY
     difference. Not "does it look similar" — walk the list:
       - interaction: does it scroll / page / snap the way the mockup did?
       - frames: a .frame that was right in the mockup's container can be wrong
         in the real one (maxWidth: .infinity in an HStack collapses to content
         width inside a horizontal ScrollView).
       - spacing, sizes, states, empty cases.
     Anything that differs is either restored or named to the operator as a
     deliberate change with a reason. AMB.1 shipped a static seven-day strip
     where the lab scrolled, then shipped it scrolling but at the wrong capsule
     width — both reached the operator, neither was caught by build or review.

  4  AUDIT  (parallel agents)
       - Code: correctness, edge cases, Swift concurrency + SwiftUI lifecycle.
       - Security: Supabase RLS/auth on the SHARED DB, PII, secrets, blast radius
         onto the web app + Captura.
       - Data/Sync: PowerSync integrity, offline behavior, no data loss.
     Fix every critical/high now.

  5  VERIFY BY RUNNING IT  (not by reading the diff)
       - Build clean: xcodebuild -> BUILD SUCCEEDED, no new warnings.
       - The operator runs the changed flow (iPhone AND iPad where relevant).
         UI/nav changes REQUIRE this. If it can't run on the dev machine, say so
         and give exact test steps.
         AMB arc: iPhone AND iPad are BOTH mandatory every phase (D7) — a phase
         is not done when only the iPhone passes.
       - Re-grep the old pattern to confirm the change landed.
       - Live-DB changes (shared Supabase): reversible, read-back verified, nothing
         destructive without sign-off.

  6  HIGH-STAKES -> run the review yourself
     If it touches Supabase RLS/auth, PowerSync/offline integrity, payroll
     (time_entries / PTO), the protected Captura roster editing, the nav shell,
     or a whole daily-use surface (an AMB conversion phase counts — AMB.1's
     review found 8, five of them regressions the phase itself introduced):
     run the code-review skill (high/max) yourself as the final step, fix findings,
     deliver a plain-English report. Do not ask the operator to trigger it.

  7  CLOSE OUT  (do it, don't ask)
       - Commit onto main — branch first for high-blast-radius work. git fetch +
         review HEAD..origin/main first. End the message with the Co-Authored-By
         line below.
       - Check off the item + dated closeout note in AUDIT_ROADMAP.md; update the
         arc's status in FocalPointProduction/docs/PHASES.md; update memory.
       - Report in plain English: what changed, the evidence, the one thing only
         the operator can confirm (the on-device run).
       - PUSH ONLY WHEN THE OPERATOR ASKS. Committed-but-not-pushed is the safe state.
         EXCEPTION, standing: the AMB arc ships each phase to main as it lands
         (D8, operator decision 2026-07-24) — push once the review and BOTH device
         smokes pass, without asking again. This exception is per-arc and does not
         generalize; every other arc keeps the default above.


# 📖 Read first  (open the files — the titles are not the rules)

  1  CLAUDE.md (repo root) — hard rules + project lessons (lowercase UUIDs,
     protected Captura files).
  2  Memory index ~/.claude/projects/-Users-jason-Desktop-employeeapp/memory/MEMORY.md
     -> the titles are not the rules: open the linked feedback_*.md files, plus
     protected-captura-files, powersync-setup, rls-remediation-2026-07,
     project-structure.
  3  AUDIT_ROADMAP.md — the item's scope + any linked plan doc (RLS_AUDIT.md,
     NAVIGATION_PLAN.md, POWERSYNC_SETUP.md, DATABASE_SCHEMA.md).
  4  FocalPointProduction/docs/PHASES.md — the family arc registry (the naming rule).


# 🧭 Project facts

  Working dir   ~/Desktop/employeeapp/
  App           SwiftUI iOS, iPhone + iPad, min iOS 16.6 (NavigationStack
                available; the app still uses NavigationView)
  Backend       Supabase nofegnmrgnanpznavlqy — SHARED with the web app
                (~/Desktop/Focal-Point-Supabase) + Captura; any DB change can
                affect them. PowerSync offline-first for the Sports roster.
  Build         xcodebuild build -workspace "Iconik Employee.xcworkspace"
                -scheme "Iconik Employee"
                -destination "platform=iOS Simulator,name=iPhone 17 Pro"
  Branch        main
  Commit        end with — Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
                (was 4.8; every commit from 2026-07-24 on carries the Opus 5 trailer)

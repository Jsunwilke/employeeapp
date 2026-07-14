# Start a Phase — Iconik Employee

Reusable kickoff. Paste this whole file into a new session, write ONE line under
START HERE, and the agent runs the phase end to end. One phase per session.

Iconik Employee is the iOS app of the Focal Point family: SwiftUI (iPhone + iPad),
Supabase backend shared with the Focal Point web app + Captura, PowerSync
offline-first for the Sports roster. Same building/research standards, same
phase-naming registry as the rest of the family.


# 🚀 START HERE  (you, the operator)

      WHAT TO BUILD:  Nav.1

  An arc id (e.g. NAV.1) or just describe the item in plain words. That is the only
  line you fill in — the agent works out the exact phase and scope.


# 📋 Phases

  Named by arc code (ARC.N) per the family registry, FocalPointProduction/docs/PHASES.md.
  Full per-item scope + closeouts live in AUDIT_ROADMAP.md.

  🟡 BUILT — AWAITING ON-DEVICE VERIFY
      NAV.1   Navigation restructure — one nav bar per screen + Home reachable everywhere.
              BUILT 2026-07-14 on branch nav-1-restructure. Home (per-device): iPhone = top-left
              Home button (house icon) on every feature screen's nav bar (Scan keeps bar center);
              iPad = large center Home button in the bottom bar (no center Scan there). Profile
              menu moved onto Home. Build clean, self code-review (high).
              NEXT: run it on iPhone AND iPad, walk every feature (one bar; Home works everywhere —
              top-left on iPhone, center-bottom on iPad; drill-ins show Back; capture mid-shoot
              back; kiosk still hides bar; iPad Sports rosters still reach Home; manager gated).
              Plan/closeout: NAVIGATION_PLAN.md + AUDIT_ROADMAP.md. The nav-single-stack branch
              is superseded (never merged) — safe to delete.

  ⚪ NOT STARTED   (proposed codes — each is registered in PHASES.md when you start it)
      DEC.1   Decompose the god files (DashboardWidgets; the Sports monoliths).
      DJR.1   Daily Job Report redesign (wizard, draft auto-save, offline outbox).
      ONB.1   Invite-code onboarding + sign-in hardening.
      TST.1   Tests for the money paths (TimeEntryValidator, PayPeriodService).
      GIC.1   Group-images conflict handling (version-checked, not last-write-wins).
      SEC.*   iOS data protection (at-rest DB encryption, PII out of UserDefaults,
              LAN TLS) — folds into the existing family SEC arc, not a new code.

  ✅ DONE   (July 2026, under the pre-arc audit scheme — closeouts in AUDIT_ROADMAP.md)
      RLS security fixes (live)  ·  SessionService perf  ·  PoserStation memo  ·
      design tokens (partial)  ·  the 5 missing chat RPCs.


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
       - Re-grep the old pattern to confirm the change landed.
       - Live-DB changes (shared Supabase): reversible, read-back verified, nothing
         destructive without sign-off.

  6  HIGH-STAKES -> run the review yourself
     If it touches Supabase RLS/auth, PowerSync/offline integrity, payroll
     (time_entries / PTO), the protected Captura roster editing, or the nav shell:
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


# 📖 Read first  (open the files — the titles are not the rules)

  1  .claude/CLAUDE.md — hard rules + project lessons (lowercase UUIDs, protected
     Captura files).
  2  Memory index ~/.claude/projects/-Users-jason-Desktop-employeeapp/memory/MEMORY.md
     -> open working-style-rules, protected-captura-files, powersync-setup,
     rls-remediation-2026-07, project-structure.
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
  Commit        end with — Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>

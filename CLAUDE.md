# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Hard rules (read first, every session)

Jason's working-style rules live canonically in `~/Brain/rules/` and are injected in full at
session start by the Brain's SessionStart hook — this repo no longer carries copies (BRAIN.4,
2026-07-29). Project-specific rules and facts live in this repo's memory at
`~/Brain/claude/memory/-Users-jason-Desktop-employeeapp/` (also reachable at the old
`~/.claude/projects/...` address). MEMORY.md is just the index — the titles are not the rules;
open the linked files. The rules below are THIS repo's own:

## Project-specific hard rules

- **Targeted git add only.** Never `git add -A`, never a blind `--amend` — a parallel session may share this working tree. Stage files by path. (Learned from the NAV.1/MD7 tangle 2026-07-14; `git-targeted-add.md` in memory.)
- **Protected Captura files are hook-enforced.** Never edit CapturaSportsView / CapturaSportsRosterView_iPhone (renamed 2026-07-23 from SportsShootListView/DetailView), RosterEntryService, LockManager, etc. — FP Sports work must be additive in new files. Lifting the hook requires explicit in-conversation operator authorization (the classifier denies edits even with a plan's standing authorization — budget for that approval when planning). (`protected-captura-files.md` in memory.)
- **UUID case: match what the column actually stores — do not blanket-lowercase.** UUIDs are case-insensitive by spec but PostgREST `.eq` on a TEXT column isn't, and a zero-row UPDATE returns 200 (silent no-op). Columns Supabase MINTS are MOSTLY lowercase (`users.id` and other uuid columns) — `.lowercased()` comparisons are right there. **`users.id` has a known exception**: one row's id is a 28-character mixed-case Firebase uid, carried over by the migration, so even that column is "mostly minted lowercase" rather than uniformly lowercase (FLG.1 traced it; `flg-user-flagging.md` in memory). Columns THIS APP writes from Swift's `UUID()` are UPPERCASE (`daily_job_reports.id`: 2,470 of 2,521 rows) and `organizations.id` carries mixed-case Firebase ids — lowercasing those matches NOTHING. AMB.9 shipped-then-caught a critical this way (a lowercased id made ~98% of mileage edits silent no-ops). When writing: prefer minting lowercase. When filtering: verify the column's stored case first, and make writes prove a row matched (`.select("id")` + throw on empty — see `DailyJobReportService.requireRowsWritten`).
- **PowerSync sync rules:** NO JOINs, NO subqueries in parameter OR data queries. Single-table SELECTs only. **Denormalize** — if a child table needs org-level filtering, add `organization_id` directly to it. (`powersync-setup.md` in memory.)
- **Shared backend.** Supabase project nofegnmrgnanpznavlqy is SHARED with the web app (~/Desktop/Focal-Point-Supabase) and Captura — any DB change can affect them. Server auth via role_permissions + has_permission(); read `rls-remediation-2026-07.md` before any server-side auth/RLS work.
- **Push only when the operator asks.** Committed-but-not-pushed is the safe state.

## Key Reference Documents

- **`AUDIT_ROADMAP.md`** — The per-item scope, plan links, and dated closeouts for the audit/fix program. Read it when the operator says "start phase N" or mentions the audit.
- **`~/Brain/projects/registry.md`** — The arc registry for all projects (moved from FocalPointProduction/docs/PHASES.md in BRAIN.3, 2026-07-29). Phases use arc codes ARC.N registered there (forward-only — shipped work isn't renamed). This repo's card: `~/Brain/projects/focal-point-ios.md`. To start a phase, say "Do ARC.N" — the start-phase skill replaces the retired kickoffs/START_A_PHASE.md (now in kickoffs/archive/). One phase per session.
- **`DATABASE_SCHEMA.md`** — The shared Supabase schema reference.
- **`.claude/MIGRATION_LESSONS.md`** — Firebase→Supabase migration lessons.

## Project Overview

This is the Focal Point family's iOS employee management app ("Iconik Employee"): SwiftUI, iPhone + iPad, min iOS 16.6, migrated from Firebase to Supabase. Backend is the shared Supabase project (with the web app + Captura); PowerSync provides offline-first sync for the Sports roster. Configuration must be secure (Config.xcconfig for secrets), maintainable (build-setting variables in Info.plist), and correct (proper variable substitution, no URL truncation).

**Build:** `xcodebuild build -workspace "Iconik Employee.xcworkspace" -scheme "Iconik Employee" -destination "platform=iOS Simulator,name=iPhone 17 Pro"`. Branch: main.

## Core Principle: Quality Over Speed

**IMPORTANT:** This project prioritizes correctness and thoroughness over speed.

- **Investigate before acting** — understand the full context before making changes
- **Verify assumptions** — check what exists before changing configuration
- **Test incrementally** — one change at a time, verify it works
- **Think through consequences** — consider what else might be affected
- **Don't rush** — do it properly the first time

Anti-patterns: configuration changes without checking prerequisites; "fixes" without understanding root causes; rushing through multiple solutions without investigation; assuming defaults without verification.

### Example of Proper Approach

When changing `GENERATE_INFOPLIST_FILE`:
1. ✅ First read the current Info.plist to see what keys exist
2. ✅ Research what keys are required when disabling auto-generation
3. ✅ Add missing keys with proper variable substitution
4. ✅ Then make the configuration change
5. ✅ Clean build and test

**NOT:** change the setting first, discover it broke something, rush to fix the new error.

## Key Lessons Learned

### Info.plist Configuration Issue
**Problem:** When using both `GENERATE_INFOPLIST_FILE = YES` and a custom `INFOPLIST_FILE`, Xcode's C preprocessor treats `://` in URLs as C++ comments, truncating URLs.

**Correct approach:** understand the root cause (C preprocessor comment bug) → evaluate solutions (preprocessor flag vs disabling auto-generation) → check prerequisites (verify Info.plist has required CFBundle* keys) → add missing keys if needed → make the change → clean build and verify. Never try a flag "to see if it works" or flip the setting without checking required keys first.

### Build Configuration Changes
Always verify current state before making changes: read affected files first, understand what the change will impact, add missing dependencies/requirements, then make the change, then verify it worked.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Hard rules (read first, every session)

These are loaded into context every session because they're rules Jason's agents keep tripping on. Each line points to the full feedback file in `~/.claude/projects/-Users-jason-Desktop-employeeapp/memory/` for context. MEMORY.md is just the index — read the linked files.

- **Questions are not requests.** If the user asks "how does X work" or "why does Y fail", answer the question. Do not modify code unless they explicitly ask. (`feedback_questions_not_requests.md`)
- **Audits and investigations are reports, not work orders.** Present findings, wait for direction. (`feedback_audits_are_reports.md`)
- **Never assume.** Verify in code, the actual DB, or ask the user. No "probably" or "likely". (`feedback_never_assume.md`)
- **Never guess — always research first.** Read the actual code and trace the real execution path before any fix. One correct fix after research beats five guesses. (`feedback_never_guess_always_research.md`)
- **Don't fake knowing code.** Never describe what a file does from its name or plausible inference. Read it first, or say "I haven't read it yet." (`feedback_dont_fake_knowing_code.md`)
- **Don't present assumptions as fact or invent evidence.** Distinguish what's verified (code, data, a real source) from general inference; label general reasoning as such UP FRONT. Never manufacture examples, sources, or statistics; if asked the basis and there is none, say "none." (`feedback_dont_present_assumptions_as_fact.md`)
- **Read existing code before building a parallel feature.** (`feedback_read_existing_code_first.md`)
- **If not 100% certain a change is safe, say so explicitly.** Don't push confidently when uncertain. (`feedback_say_when_unsure.md`)
- **Trace impact before changing behavior.** Before changing any default, data flow, or shared-DB schema, grep every caller and name the consumers out loud — the Supabase DB is SHARED with the web app and Captura. (`feedback_trace_impact_before_changing.md`, `feedback_grep_callers_first.md`)
- **No "MVP / fast path" framing.** Plan and build the correct version the first time. (`feedback_correctness_over_speed.md`)
- **Build the professional way the first time.** No hacks, patches, or workarounds. (`feedback_always_professional.md`)
- **Audit findings are suggestions, not instructions.** Verify each against existing decisions before applying; then fix all accepted findings now, not "next session". (`feedback_evaluate_audit_findings.md`, `feedback_fix_audit_findings_now.md`)
- **Never simplify or strip features to fix a bug.** Find the real cause. (`feedback_never_simplify.md`)
- **Match existing patterns exactly.** When told to "use the same pattern as [module]," read that module's actual code first; copy its real structure, then adapt only the data. (`feedback_match_existing_patterns_exactly.md`)
- **Verify before saying "fixed."** After every edit, re-grep for the old pattern (or rebuild/run) to confirm the change landed. Never report done without verifying. (`feedback_verify_before_responding.md`)
- **Instrument early on UI/behavior bugs.** For "tapped it, nothing happened"-style bugs, add logging/print probes immediately instead of iterating layout theories. (`feedback_instrument_early_on_ui_bugs.md`)
- **Delete-first migration.** When replacing an old code path with a new one, delete the old path in the same commit. No parallel implementations, no flags during transitions, no cleanup-as-followup. (`feedback_delete_first_migration.md`)
- **A phase cleans up its own scaffolding.** A spike, probe, or measurement harness with no production caller is deleted at the close of the phase that built it — never deferred. (`feedback_scaffolding_cleanup.md`)
- **Resolve build-time decisions yourself; don't pop questions.** When implementation surfaces a decision the plan didn't pre-decide, resolve it from the plan's existing principles. Build straight through is the default; the operator confirms by running the app, not by reviewing diffs. Surface only a genuine safety/data-loss risk or a true conflict between locked decisions. (`feedback_default_resolution.md`)
- **Don't commit broken code; fix all errors now.** Resolve every error and known issue before committing or calling work done. (`feedback_no_known_errors.md`, `feedback_dont_commit_unfinished.md`)
- **Check remote before git pull/reset.** Never `git pull` or `git reset --hard` without first `git fetch` + reviewing `HEAD..origin/main`. (`feedback_check_before_git_pull.md`, `feedback_never_reset_hard_without_checking.md`)
- **Drift audit before declaring done.** After writing any plan, run a drift-audit pass for rationalization vocabulary ("deferred," "follow-up cleanup," "subsequent phase") and split-phase patterns. The audit is a deliverable, not a step. (`feedback_drift_audit_before_declaring_done.md`)
- **High-stakes work gets an independent review gate + a plain-English report — and YOU run it, BEFORE any push.** The operator is not an engineer and can't vet a decision from a diff. Anything touching roster data integrity (the Captura save paths), PowerSync sync rules / offline data, the shared Supabase DB (schema, RLS, auth — shared with the web app and Captura), or the protected Captura files gets a SEPARATE adversarial review (not the builder self-grading) before it's called done — run `/code-review` (high/max effort) yourself as the final build step. CRS.1 lesson (2026-07-23): run it BEFORE pushing — once merged to origin/main there is no branch delta left to bundle, and a post-push review is not assurance. (`feedback_independent_review_gate.md`)
- **Architecture decisions pass the decision gate first.** Before calling any technology/data-flow choice "the right call," answer in plain English: immediate fix or forward architecture? does it survive every real constraint (offline-first PowerSync, shared multi-app DB, iPhone + iPad, min iOS 16.6)? cost to undo if wrong? validated or assumed? Surface that to pressure-test before locking it in. (`feedback_architecture_decision_gate.md`)
- **Read every linked feedback file at session start.** The titles do not encode the rules — the rules live in the linked files. (`feedback_read_memory_files_not_index.md`)
- **Use memory proactively.** Write memory as work happens; grep existing files first to avoid duplicates. (`feedback_use_memory_proactively.md`)

> Note: These working-style standards were ported from Focal Grade / Iconik-Photo-Grade (2026-07-23; originally adopted for this app 2026-07-13) to match the same building and research standards across Jason's apps. A few linked files cite Focal Point / KeepUp / Focal Grade examples — read the principle, ignore the example.

## Project-specific hard rules

- **Targeted git add only.** Never `git add -A`, never a blind `--amend` — a parallel session may share this working tree. Stage files by path. (Learned from the NAV.1/MD7 tangle 2026-07-14; `git-targeted-add.md` in memory.)
- **Protected Captura files are hook-enforced.** Never edit CapturaSportsView / CapturaSportsRosterView_iPhone (renamed 2026-07-23 from SportsShootListView/DetailView), RosterEntryService, LockManager, etc. — FP Sports work must be additive in new files. Lifting the hook requires explicit in-conversation operator authorization (the classifier denies edits even with a plan's standing authorization — budget for that approval when planning). (`protected-captura-files.md` in memory.)
- **Always use lowercase UUIDs.** Supabase stores lowercase; Swift generates uppercase. UUIDs are case-insensitive by spec but Swift string comparison isn't — mismatches cause silent lookup/filter failures. Use `.lowercased()` on both sides of comparisons; prefer lowercase when storing/passing.
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

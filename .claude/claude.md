# Claude Code Guidelines for This Project

## Hard rules (read first, every session)

Jason's shared working-style standards, adopted for this app 2026-07-13 to match how Focal
Point Production / Focal Grade / KeepUp are built. Full versions live in the Focal Grade
memory (`~/.claude/projects/-Users-jason-Desktop-Iconik-Photo-Grade/memory/feedback_*.md`).

- **Questions are not requests.** If asked "how does X work" / "why does Y", answer it. Do not change code unless explicitly asked.
- **Audits and investigations are reports, not work orders.** Present findings, wait for direction before fixing.
- **Never assume; never guess — research first.** Read the actual code, check the actual DB, trace the real execution path before any fix. No "probably"/"likely".
- **Don't fake knowing code.** Never describe a file from its name or plausible inference. Read it first, or say "I haven't read it yet."
- **Read existing code before building a parallel feature. Match existing patterns exactly** (read that module's real code first).
- **If not 100% certain a change is safe, say so explicitly.** Trace impact before changing behavior — grep every caller and name the consumers out loud.
- **Build the professional way the first time. No hacks, patches, or workarounds.** No "MVP / fast path" framing. Never simplify or strip features to fix a bug — find the real cause.
- **Delete-first migration.** When replacing an old path with a new one, delete the old path in the same commit. No parallel implementations, no transition flags. A phase cleans up its own scaffolding.
- **Resolve build-time decisions yourself from the plan's principles; don't pop questions.** Build straight through; the operator confirms by running the app, not by reviewing diffs. Surface only a genuine safety/data-loss risk or a true conflict between locked decisions.
- **Architecture decisions pass the plain-English decision gate first:** immediate fix or forward architecture? does it survive every real constraint? cost to undo if wrong? validated or assumed? Surface it to pressure-test before locking it in.
- **Verify before saying "fixed."** After every edit, re-grep for the old pattern (or rebuild/run) to confirm the change landed. Don't commit broken code — fix all errors now.
- **Verify by running, not by reading the diff.** The operator is not an engineer and can't vet a decision from a diff — reports are plain English, and high-stakes work gets a SEPARATE `/code-review` (high/max) that I run myself as the final step.
- **Check remote before git pull/reset** (`git fetch` + review `HEAD..origin/main` first). At the end, advise merge-now vs hold.
- **Use memory proactively** (grep existing files first to avoid duplicates). Plan/doc files: no backticks.

## Core Principle: Quality Over Speed

**IMPORTANT:** This project prioritizes correctness and thoroughness over speed.

### Working Standards:
- **Investigate before acting** - Always understand the full context before making changes
- **Verify assumptions** - Check what exists before changing configuration
- **Test incrementally** - Make one change at a time and verify it works
- **Think through consequences** - Consider what else might be affected by a change
- **Don't rush** - Take time to do things properly the first time

### Anti-Patterns to Avoid:
- ❌ Making configuration changes without checking prerequisites
- ❌ Applying "fixes" without understanding root causes
- ❌ Rushing to try multiple solutions without proper investigation
- ❌ Assuming defaults without verification

### Example of Proper Approach:
When changing `GENERATE_INFOPLIST_FILE`:
1. ✅ First read the current Info.plist to see what keys exist
2. ✅ Research what keys are required when disabling auto-generation
3. ✅ Add missing keys with proper variable substitution
4. ✅ Then make the configuration change
5. ✅ Clean build and test

**NOT:**
1. ❌ Change the setting first
2. ❌ Discover it broke something
3. ❌ Rush to fix the new error

---

## Project Context

This is an iOS employee management app being migrated from Firebase to Supabase. Configuration must be:
- Secure (using Config.xcconfig for secrets)
- Maintainable (using build setting variables in Info.plist)
- Correct (proper variable substitution, no URL truncation issues)

## Key Lessons Learned

### Info.plist Configuration Issue
**Problem:** When using both `GENERATE_INFOPLIST_FILE = YES` and a custom `INFOPLIST_FILE`, Xcode's C preprocessor treats `://` in URLs as C++ comments, truncating URLs.

**Wrong Approach:**
- Try `-traditional` flag without verifying if it works
- Change `GENERATE_INFOPLIST_FILE` setting without checking if Info.plist has required keys

**Correct Approach:**
1. Understand the root cause (C preprocessor comment bug)
2. Evaluate solutions (preprocessor flag vs disabling auto-generation)
3. Check prerequisites (verify Info.plist has required CFBundle* keys)
4. Add missing keys if needed
5. Make configuration change
6. Clean build and verify

### Build Configuration Changes
Always verify current state before making changes:
- Read affected files first
- Understand what the change will impact
- Add missing dependencies/requirements
- Then make the change
- Verify the change worked as expected

### UUID Handling
**Always use lowercase UUIDs** for consistency across the app.

**Problem:** Supabase stores UUIDs in lowercase, but iOS/Swift UUID generation and some auth services return uppercase UUIDs. This causes string comparison failures when matching user IDs to photographer IDs, etc.

**Rules:**
- When comparing UUIDs, always use `.lowercased()` on both sides
- When storing or passing UUIDs, prefer lowercase format
- Example: `userID.lowercased() == photographerID.lowercased()`

**Why:** UUIDs are case-insensitive by specification, but Swift string comparison is case-sensitive. Mismatched cases cause silent failures in lookups and filtering.

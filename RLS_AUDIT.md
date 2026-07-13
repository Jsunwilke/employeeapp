# Server-Side Authorization Audit (Phase 3, item 5)

Date: 2026-07-12 · Scope: RLS policies + Edge Functions + SECURITY DEFINER RPCs.

**Core thesis (confirmed):** all *application* authorization is client-side. The iOS
app decides what a user may see/do via `PermissionsService` (a cache of the
`role_permissions` table) and by which tab strings the menu exposes — but the
rendering switch in `MainEmployeeView.swift:872-932` maps a tab-id string straight
to a manager view (`TimeOffApprovalView`, `FlagUserView`, `ManagerMileageView`,
`StatsView`, `GalleryCreatorView`…) **with no role guard**. So the only thing that
actually stops a non-manager from reading/writing privileged data is **RLS on the
tables and re-authorization inside the RPCs/functions**. That backstop is what this
audit checks.

Legend: ✅ verified safe (from repo) · ⚠️ **must verify against live DB** (policy not in
repo migrations) · 🔴 confirmed problem.

---

## A. What I could verify from the repo

### ✅ `app_config` — fixed
`20260712_lock_down_app_config.sql` dropped the `USING (true)` SELECT policy and
nulled the key. RLS on, no policies → client can't read/write. Good. (Phase 1.)

### ✅ `tasks`, `task_comments`, `report_templates`, `daily_job_reports`, `photoshoot_notes`
RLS enabled with org-scoped `organization_id IN (SELECT organization_id FROM users
WHERE id = auth.uid()::text)` reads and owner-scoped writes. Role-checked where it
matters (`photoshoot_notes` managers, `time_off_requests` approvers). Two notes:
- `daily_job_reports` SELECT is **org-wide** — every employee can read every
  colleague's daily report (mileage, schools, free-text notes). Likely broader than
  intended; consider owner-or-manager. **Severity: Low** (same-org PII exposure).
- `tasks` UPDATE lets any org member update any task (no assignee/creator check).
  Probably intentional for collaboration. **Severity: Low.**

### 🔴 `acquire_lock` RPC — trusts caller-supplied identity, no org scope
`20250115_atomic_locks.sql`. `SECURITY DEFINER`, `GRANT EXECUTE … TO authenticated`.
It takes `p_user_id` / `p_user_name` **as arguments and trusts them** — it never
checks `p_user_id = auth.uid()`, and it never checks the caller's organization
against the locked row. Because it's `SECURITY DEFINER` it bypasses RLS. Impact:
- Any authenticated user can acquire a roster/group-image lock **as another user**
  (pass their id/name) → confusion + griefing in the collaborative Captura roster
  editing that other photographers use in production.
- No org check → a user in org A can lock rows in org B's `roster_entries` /
  `group_images` (cross-tenant griefing / DoS on the shared editing feature).
Mitigants: locks are advisory and auto-expire after 2 min (cron). **Severity:
Medium.** Drafted fix: `supabase/drafts/harden_acquire_lock.sql` (identity check; org scope
left as an optional follow-up because it needs the live column layout). ⚠️ Touches
PROTECTED Captura locking — **review + verify before deploy.**

### 🔴 `send-notification` Edge Function — no caller authorization
`supabase/functions/send-notification/index.ts`. Accepts `{title, body, userIds}` and
pushes to those users via the service role. There is **no check on who is calling** —
not manager-gated, not org-scoped to the recipients. It's reachable from the client
(`FlagUserView.swift:194`), so it's protected only by Supabase's default `verify_jwt`
gateway, which every employee passes. Impact: any employee can send an arbitrary
push notification (any title/body) to **any or all** employees → spoofing / phishing
(e.g. a fake "Session Cancelled" or "IT: tap to re-login" push). **Severity:
Medium-High.** Recommended fix in §C — not auto-applied because it's a live flow.

### ⚠️ Chat RPCs — verify they derive the actor from `auth.uid()`
`SupabaseChatService.swift` calls these with a client-supplied user id:
`mark_conversation_read(user_id)`, `toggle_pin_conversation(user_id)`,
`add_conversation_participants(added_by_id)`,
`remove_conversation_participant(participant_id, removed_by_id)`,
`leave_conversation(user_id)`. Their SQL bodies are **not in the repo** (live DB).
If any is `SECURITY DEFINER` and acts on the passed id without checking
`= auth.uid()` (and membership in the conversation), a user could mark others' convos
read, remove/add participants to conversations they're not in, etc. Verify with §B.4.

### Webhook/cron functions — not a client-auth concern (but verify gateway)
`chat-notification`, `session-notification`, `clock-reminder` are service-role,
webhook/cron-triggered. Fine **provided** their `verify_jwt` is such that a random
unauthenticated POST can't forge a payload (e.g. a fake "Session Cancelled" spam via
`session-notification`). Verify in §B.5. `optimize-route` and `claude-proxy` are
client-callable and gated only by `verify_jwt`; both are cost vectors (Google API /
Anthropic org key) with no per-user rate limit — **Low**, consider a rate limit later.

---

## B. Verification SQL — run in Supabase SQL editor (live DB is source of truth)

These cover the tables/functions whose policies live only in the DB. Paste each and
compare to the "expect" note.

**B.1 — Every table has RLS enabled (catch any table created without it):**
```sql
select relname, relrowsecurity
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by relrowsecurity, relname;   -- expect: NO row with relrowsecurity = false
```

**B.2 — All policies on the core tables (the ones not in repo migrations):**
```sql
select tablename, policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('users','sessions','session_days','time_entries','pto_balances',
                    'roster_entries','group_images','conversations','messages',
                    'organizations','time_off_requests','role_permissions')
order by tablename, cmd;
```
Expect, for each: `qual`/`with_check` ties `organization_id` (or an actor column like
`user_id`/`photographer_id`) to `auth.uid()` — e.g.
`organization_id in (select organization_id from users where id = auth.uid()::text)`.
🔴 Red flags: `qual = true` (or `USING (true)`) on anything, `time_entries` writable
by non-owner (it's payroll), `users` UPDATE that lets a user change another row or
their own `role`/`organization_id`, `pto_balances` writable by the balance owner.

**B.3 — `acquire_lock` definition (confirm the fix state):**
```sql
select prosecdef as security_definer, pg_get_functiondef(oid)
from pg_proc where proname = 'acquire_lock';
-- confirm it checks p_user_id = auth.uid() after any fix is deployed
```

**B.4 — Chat RPC bodies (the ⚠️ item):**
```sql
select proname, prosecdef, pg_get_functiondef(oid)
from pg_proc
where proname in ('mark_conversation_read','toggle_pin_conversation',
                  'add_conversation_participants','remove_conversation_participant',
                  'leave_conversation');
-- For each SECURITY DEFINER one: does it use auth.uid() for the actor and verify the
-- caller is a participant? If it acts on the passed *_id blindly → harden like acquire_lock.
```

**B.5 — Which functions skip JWT verification (webhook forge surface):**
Check Dashboard → Edge Functions → each function → "Verify JWT". Webhook receivers
(`chat-notification`, `session-notification`) typically have it **off**; if so, confirm
they validate a shared secret / the webhook signature in-code (currently they do not —
they act on any well-formed payload). Client-callable ones (`send-notification`,
`optimize-route`, `claude-proxy`) must have it **on**.

---

## C. Recommended remediations (priority order)

1. **`send-notification`** — require the caller to be a manager/admin (or at minimum
   verify the JWT and constrain `userIds` to the caller's org). Sketch: read the
   `Authorization` bearer, `supabase.auth.getUser(jwt)`, look up the caller's role,
   reject if not manager. This changes a live flow (`FlagUserView`) → deploy with a
   quick manual test that flagging still notifies.
2. **`acquire_lock`** — apply `DRAFT_harden_acquire_lock.sql` after review (identity
   check is low-risk; add org scope once the row's org column is confirmed).
3. **Chat RPCs** — per §B.4, switch actor to `auth.uid()` + participant check for any
   that trust args.
4. **Confirm core-table RLS** (§B.1/B.2). This is the single most important step — a
   missing/`true` policy on `users`, `time_entries`, `sessions`, or `pto_balances`
   would be the highest-severity finding, and it can only be seen in the live DB.
5. **Later/Low:** narrow `daily_job_reports` SELECT; add rate limits to `claude-proxy`
   / `optimize-route`; add webhook shared-secret checks.

## D. Status
- Repo-visible surface: audited. Findings above.
- Live-DB-only surface: **DONE 2026-07-12** — §B run against the live project
  (`nofegnmrgnanpznavlqy`) via the Management API. Results in §E. This closes the item.
- Drafted fixes (not deployed): `supabase/drafts/harden_acquire_lock.sql` and
  `supabase/drafts/rls_hardening.sql` (§E fixes). All need owner review — this is the
  SHARED Focal-Point DB (also backs Captura production), so DDL has cross-system blast radius.

---

## E. Live DB results (2026-07-12) — what the console SQL found

The client-side-authorization thesis is not just confirmed, it's **worse than "read-only
leakage"**: the server actively permits privilege escalation and unauthenticated data access.

### 🔴🔴 CRITICAL 1 — any employee can make themselves org admin
`users` has a `role text` column, and `is_user_admin()` / `is_admin_of_org()` (both
SECURITY DEFINER) gate admin power on `role = 'admin'`. The `users_update_org` policy
allows a user to UPDATE their **own** row (`id = auth.uid()`), and column grants show
`authenticated` **and `anon`** hold `UPDATE` on `users.role`, `users.role_id`, AND
`users.organization_id`. RLS can't restrict columns → **any employee can set their own
`role='admin'`** (real server-side admin, not just UI) or change their `organization_id`
to hop orgs. Exploitable with the JWT every employee already has.

### 🔴🔴 CRITICAL 2 — 14 tables are RLS-off AND granted to `anon` (public key) with full DML
RLS is disabled on and SELECT/INSERT/UPDATE/DELETE granted to **`anon`** (the anon key is
public — it ships in the app binary / `Config.xcconfig`) for: all `audit_log_2026_05 …
2027_01` + `audit_log_default` partitions, `access_code_pricing`, `archive_step_legacy_fields`,
`_recurring_tasks_backup_2026_05_28`, `_w12_repeats_backup_2026_05`. So **anyone with the
public anon key — no login — can read the entire audit log and pricing, and DELETE those
rows.** This is the shared Focal-Point DB, so the audit log likely spans Captura orgs too.

### 🔴 HIGH 3 — payroll / PTO / schedule writable by any employee
These use `FOR ALL` with only an org check (`organization_id = get_user_organization_id()`),
no owner/role restriction, so any authenticated org member can INSERT/UPDATE/DELETE **any**
row in their org:
- `pto_balances` — an employee can inflate their own PTO balance (money).
- `time_entries` — an employee can edit/delete colleagues' payroll punches.
- `time_off_requests` — an employee can self-approve or delete others' requests (the
  manager-only approve policy from migration 005 is moot — RLS policies OR together, so the
  permissive `ALL` policy wins).
- `sessions` / `session_days` — any employee can edit the whole org's schedule server-side.

### 🔴 HIGH 4 — `role_permissions` writable by any authenticated org member
`modify_role_permissions` (cmd ALL, role `authenticated`) only checks the target role is in
the caller's org — **not** that the caller is an admin. An employee can rewrite their own
role's permission set (self-serve permission escalation for the client-side gate).

### ✅ / minor
- `messages`, `conversations` — correctly scoped to participants (`participants @> auth.uid()`,
  `sender_id = auth.uid()`). Good.
- `organizations` — SELECT own, UPDATE admin-only. Good (INSERT open is fine for onboarding).
- Org-scope helper fns (`get_user_org_id`, `is_admin_of_org`, …) correctly derive from
  `auth.uid()`. Good.
- `acquire_lock` — LIVE is `SECURITY INVOKER` (not DEFINER as in the repo migration), so RLS
  applies and the cross-org concern is mitigated; it still trusts `p_user_id` for lock-owner
  identity (minor griefing only). Lower severity than the repo suggested.
- Chat RPCs (`mark_conversation_read`, `toggle_pin_conversation`,
  `add_conversation_participants`, `remove_conversation_participant`, `leave_conversation`)
  **do not exist** in the DB — the client `rpc(...)` calls to them fail at runtime. Separate
  bug to chase, but not an authz hole.

### APPLIED / STATUS (2026-07-12, live)
- ✅ **CRITICAL 2 — DONE & verified.** anon revoked entirely on all 14 tables;
  authenticated lost INSERT/UPDATE/DELETE/TRUNCATE (kept SELECT). Verified: no anon
  grants remain; authenticated has only SELECT/REFERENCES/TRIGGER.
- ⚠️ **CRITICAL 1 — NOT yet applied.** The approved column-`REVOKE` is a Postgres no-op:
  authenticated/anon hold a **table-level** UPDATE grant on `users`, so column revokes
  don't remove the privilege (verified still updatable). Corrected fix = a BEFORE UPDATE
  trigger (`supabase/drafts/fix_users_privileged_columns.sql`) blocking non-admins from
  CHANGING privileged columns. Also newly found: the same grant exposes
  `hourly_rate`, `salary_amount`, `compensation_type`, `amount_per_mile`,
  `overtime_threshold`, `is_accountant`, `is_active`, `is_flagged` to self-edit (raise
  your own pay / self-unflag). The trigger covers all but `is_flagged` (managers set that
  on others → needs the manager-or-admin check with the HIGH items). Awaiting go-ahead.

### Priority
1. **CRITICAL 2** (anon → audit/pricing/backups): ✅ done.
2. **CRITICAL 1** (self-admin): revoke `UPDATE` on `users.role`/`role_id`/`organization_id`
   from anon+authenticated; route role changes through an admin-only SECURITY DEFINER RPC.
3. **HIGH 3 & 4**: tighten the `FOR ALL` policies to owner/manager for writes; make
   `role_permissions` writes admin-only.
Draft SQL for all of the above: `supabase/drafts/rls_hardening.sql`. ⚠️ Shared Captura DB —
review each against live app + Captura flows before applying; some `FOR ALL` writes may be
intentional. Not auto-applied.

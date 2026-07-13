-- APPROVED CRITICAL FIXES — paste into Supabase SQL editor for project
-- nofegnmrgnanpznavlqy (Iconik employee app + Captura, shared DB).
-- Both are reversible (re-GRANT). See RLS_AUDIT.md §E for context.
-- Run as one script. Expected result: "Success. No rows returned."

BEGIN;

-- ── CRITICAL 2 ─────────────────────────────────────────────────────────────
-- 14 RLS-off tables were granted to anon (the PUBLIC anon key that ships in the
-- app binary) with full read/write. Remove anon access entirely; remove write
-- from authenticated. Keep authenticated SELECT in case a Captura admin view
-- reads them (tighten later if not).
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'audit_log_2026_05','audit_log_2026_06','audit_log_2026_07','audit_log_2026_08',
    'audit_log_2026_09','audit_log_2026_10','audit_log_2026_11','audit_log_2026_12',
    'audit_log_2027_01','audit_log_default','access_code_pricing',
    'archive_step_legacy_fields','_recurring_tasks_backup_2026_05_28','_w12_repeats_backup_2026_05'
  ] LOOP
    EXECUTE format('REVOKE ALL ON public.%I FROM anon;', t);
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.%I FROM authenticated;', t);
  END LOOP;
  -- Parent partitioned table, if grants are inherited from it:
  BEGIN
    EXECUTE 'REVOKE ALL ON public.audit_log FROM anon';
    EXECUTE 'REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.audit_log FROM authenticated';
  EXCEPTION WHEN undefined_table THEN NULL; END;
END $$;

-- ── CRITICAL 1 ─────────────────────────────────────────────────────────────
-- authenticated + anon held UPDATE on these columns, and the users_update_org
-- policy lets a user update their own row → any employee could set role='admin'.
-- The employee app never writes these columns, so this breaks nothing in it.
REVOKE UPDATE (role, role_id, organization_id) ON public.users FROM anon, authenticated;

COMMIT;

-- ── Verify (run separately; all three should return zero rows) ──────────────
-- 1) no anon grants remain on the 14 tables:
-- select table_name from information_schema.role_table_grants
--   where table_schema='public' and grantee='anon'
--     and table_name in ('audit_log_2026_07','access_code_pricing','_w12_repeats_backup_2026_05');
-- 2) no UPDATE on users.role for app roles:
-- select grantee from information_schema.column_privileges
--   where table_name='users' and column_name='role' and privilege_type='UPDATE'
--     and grantee in ('anon','authenticated');

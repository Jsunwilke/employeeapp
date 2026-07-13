-- DRAFT — NOT a live migration. Remediation for the live findings in RLS_AUDIT.md §E.
-- Kept out of supabase/migrations/ so `supabase db push` won't apply it.
--
-- ⚠️⚠️ This is the SHARED Focal-Point DB (project nofegnmrgnanpznavlqy) — it also backs
-- Captura production. Every statement here can affect systems beyond the employee app.
-- Review each block against BOTH the employee app and Captura before applying, and apply
-- one block at a time. Do NOT run this whole file blind.

-- =====================================================================
-- CRITICAL 2 — RLS-off tables granted to anon (public key) with full DML.
-- anon = the public anon key that ships in the app binary. No login required.
-- Fix: remove client access. These tables (audit logs, pricing, backups) have no
-- reason to be reachable by the app roles at all — service role / dashboard only.
-- =====================================================================
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'audit_log_2026_05','audit_log_2026_06','audit_log_2026_07','audit_log_2026_08',
    'audit_log_2026_09','audit_log_2026_10','audit_log_2026_11','audit_log_2026_12',
    'audit_log_2027_01','audit_log_default','access_code_pricing',
    'archive_step_legacy_fields','_recurring_tasks_backup_2026_05_28','_w12_repeats_backup_2026_05'
  ] LOOP
    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated;', t);
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t);  -- belt-and-suspenders
  END LOOP;
END $$;
-- Also revoke on the audit_log PARENT (partition grants can be inherited):
REVOKE ALL ON public.audit_log FROM anon, authenticated;
-- The two `_*_backup_*` tables look like one-off migration backups — consider DROPPING them
-- outright once confirmed disposable:
--   DROP TABLE public._recurring_tasks_backup_2026_05_28;
--   DROP TABLE public._w12_repeats_backup_2026_05;

-- =====================================================================
-- CRITICAL 1 — self-service admin escalation via users.role.
-- authenticated + anon can UPDATE users.role / role_id / organization_id, and the
-- users_update_org policy lets a user update their own row → set role='admin'.
-- Fix: take these columns away from the client entirely; role/org changes must go
-- through an admin-only path (dashboard, or a SECURITY DEFINER RPC that checks
-- is_admin_of_org). The app should not be writing its own role.
-- =====================================================================
REVOKE UPDATE (role, role_id, organization_id) ON public.users FROM anon, authenticated;
-- If admins currently change roles from inside the app (not the dashboard), add a
-- guarded RPC and grant EXECUTE to authenticated instead of the column UPDATE:
--
-- CREATE OR REPLACE FUNCTION public.admin_set_user_role(p_user_id text, p_role text)
-- RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
-- BEGIN
--   IF NOT is_user_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;
--   -- both actor and target must be same org
--   IF get_user_org_id() <> (SELECT organization_id FROM users WHERE id = p_user_id) THEN
--     RAISE EXCEPTION 'cross-org';
--   END IF;
--   UPDATE users SET role = p_role WHERE id = p_user_id;
-- END $$;
-- REVOKE ALL ON FUNCTION public.admin_set_user_role(text,text) FROM public;
-- GRANT EXECUTE ON FUNCTION public.admin_set_user_role(text,text) TO authenticated;

-- =====================================================================
-- HIGH 3 — payroll/PTO/schedule are FOR ALL with only an org check, so any employee
-- can write any row in the org. Split read (org-wide) from write (owner/admin).
-- ⚠️ VERIFY: managers may legitimately edit others' entries from the app. If so, use
-- an is_admin_of_org()/manager check for writes instead of owner-only. Confirm the
-- real write flows before applying — this is the block most likely to break the app.
-- =====================================================================
-- pto_balances: the employee app (PTOService reserve/use/release/create) writes the
-- user's OWN balance client-side, so admin-only would break time-off requests. Scope
-- writes to the owner: closes the cross-employee hole (can't touch colleagues'
-- balances) while keeping the app working. Residual: a user can still inflate their
-- OWN balance via a crafted request — fully closing that needs the balance math moved
-- server-side (RPC/trigger); tracked as a follow-up, not this policy.
DROP POLICY IF EXISTS pto_balances_org_access ON public.pto_balances;
CREATE POLICY pto_balances_select ON public.pto_balances
  FOR SELECT USING (organization_id = get_user_organization_id());
CREATE POLICY pto_balances_own_write ON public.pto_balances
  FOR ALL USING (user_id = (auth.uid())::text AND organization_id = get_user_organization_id())
  WITH CHECK (user_id = (auth.uid())::text AND organization_id = get_user_organization_id());
CREATE POLICY pto_balances_admin_write ON public.pto_balances
  FOR ALL USING (is_admin_of_org(organization_id)) WITH CHECK (is_admin_of_org(organization_id));

-- time_entries: read org-wide (managers see the team); write only your OWN punches.
-- If managers edit others' entries in-app, swap the write check to is_admin_of_org.
DROP POLICY IF EXISTS time_entries_org_access ON public.time_entries;
CREATE POLICY time_entries_select ON public.time_entries
  FOR SELECT USING (organization_id = get_user_organization_id());
CREATE POLICY time_entries_own_write ON public.time_entries
  FOR ALL USING (user_id = (auth.uid())::text AND organization_id = get_user_organization_id())
  WITH CHECK (user_id = (auth.uid())::text AND organization_id = get_user_organization_id());
-- Plus a manager override for edits/approvals:
CREATE POLICY time_entries_admin_write ON public.time_entries
  FOR ALL USING (is_admin_of_org(organization_id)) WITH CHECK (is_admin_of_org(organization_id));

-- time_off_requests: employees create/read own + org; approve/deny is admin-only.
DROP POLICY IF EXISTS time_off_requests_org_access ON public.time_off_requests;
CREATE POLICY tor_select ON public.time_off_requests
  FOR SELECT USING (organization_id = get_user_organization_id());
CREATE POLICY tor_own_write ON public.time_off_requests
  FOR ALL USING (photographer_id = (auth.uid())::text)
  WITH CHECK (photographer_id = (auth.uid())::text);
CREATE POLICY tor_admin_write ON public.time_off_requests
  FOR ALL USING (is_admin_of_org(organization_id)) WITH CHECK (is_admin_of_org(organization_id));
-- NOTE: verify the actor column name on time_off_requests is `photographer_id`.

-- sessions / session_days: if only managers should edit the schedule, gate writes:
-- (left commented — confirm whether employees are meant to edit sessions at all)
-- DROP POLICY IF EXISTS sessions_org_access ON public.sessions;
-- CREATE POLICY sessions_select ON public.sessions FOR SELECT USING (organization_id = get_user_organization_id());
-- CREATE POLICY sessions_admin_write ON public.sessions FOR ALL
--   USING (is_admin_of_org(organization_id)) WITH CHECK (is_admin_of_org(organization_id));

-- =====================================================================
-- HIGH 4 — role_permissions writable by any authenticated org member. Make writes
-- admin-only; keep read for the org so PermissionsService still works.
-- =====================================================================
DROP POLICY IF EXISTS modify_role_permissions ON public.role_permissions;
CREATE POLICY modify_role_permissions_admin ON public.role_permissions
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM roles r
                 WHERE r.id = role_permissions.role_id
                   AND r.organization_id = get_user_org_id())
         AND is_user_admin())
  WITH CHECK (EXISTS (SELECT 1 FROM roles r
                      WHERE r.id = role_permissions.role_id
                        AND r.organization_id = get_user_org_id())
              AND is_user_admin());

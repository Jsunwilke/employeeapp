-- ============================================================================
-- RLS HIGH batch — lock down payroll / PTO / schedule / permissions writes so a
-- regular employee can't write org-wide. Mirrors the apps' real RBAC:
-- role_permissions(area_code, level) with level 1=view, 2=edit, 3=admin. Paste
-- into the Supabase SQL editor for project nofegnmrgnanpznavlqy.
--
-- Design: SELECT stays org-wide everywhere (so nothing's reads break); only WRITES
-- get gated. Each write is allowed for: the row's OWNER, OR a user whose
-- role_permissions grant edit(2)+ on the governing area, OR an org admin. Verified
-- area names against both apps (iOS PermissionsService + web Focal-Point-Supabase):
--   payroll → pto_balances, time_entries    schedule → sessions/session_days
--   timeOffApprovals → time_off_requests     roles → role_permissions
--
-- Apply top-to-bottom. The last section (sessions) is the highest-risk — it gates
-- the schedule; apply it after confirming managers can still create/edit sessions.
-- Everything is reversible (restore the old `*_org_access` FOR ALL policy).
-- ============================================================================

-- ── helper: does the current user have >= p_min_level on p_area? ─────────────
-- Mirrors PermissionsService.has(area, level) / web hasPermission(area, level).
CREATE OR REPLACE FUNCTION public.has_permission(p_area text, p_min_level int)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((
    SELECT rp.level >= p_min_level
    FROM public.users u
    JOIN public.role_permissions rp ON rp.role_id = u.role_id
    WHERE u.id = (auth.uid())::text
      AND rp.area_code = p_area
    LIMIT 1
  ), false);
$$;
REVOKE ALL ON FUNCTION public.has_permission(text,int) FROM public;
GRANT EXECUTE ON FUNCTION public.has_permission(text,int) TO authenticated;

-- ── role_permissions: writes admin/roles-edit only (was: any org member) ─────
-- Highest-value, lowest-risk: the apps only READ this table; nothing writes it
-- from the client, so gating writes can't break a client flow. Leaves the
-- existing read_role_permissions SELECT policy in place.
DROP POLICY IF EXISTS modify_role_permissions ON public.role_permissions;
CREATE POLICY role_permissions_modify ON public.role_permissions
  AS PERMISSIVE FOR ALL TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.roles r
            WHERE r.id = role_permissions.role_id AND r.organization_id = get_user_org_id())
    AND (has_permission('roles', 2) OR is_user_admin())
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.roles r
            WHERE r.id = role_permissions.role_id AND r.organization_id = get_user_org_id())
    AND (has_permission('roles', 2) OR is_user_admin())
  );

-- ── pto_balances: read org-wide; write = owner OR payroll-edit OR admin ──────
-- iOS PTOService writes the user's OWN balance (owner path). Admin/payroll adjusts.
DROP POLICY IF EXISTS pto_balances_org_access ON public.pto_balances;
CREATE POLICY pto_balances_select ON public.pto_balances
  FOR SELECT USING (organization_id = get_user_organization_id());
CREATE POLICY pto_balances_write ON public.pto_balances
  FOR ALL
  USING (organization_id = get_user_organization_id()
         AND (user_id = (auth.uid())::text OR has_permission('payroll', 2) OR is_user_admin()))
  WITH CHECK (organization_id = get_user_organization_id()
         AND (user_id = (auth.uid())::text OR has_permission('payroll', 2) OR is_user_admin()));

-- ── time_entries: read org-wide; write = owner OR payroll-edit OR admin ──────
-- iOS clock in/out writes the user's OWN punches (owner path). Payroll/admin edits.
DROP POLICY IF EXISTS time_entries_org_access ON public.time_entries;
CREATE POLICY time_entries_select ON public.time_entries
  FOR SELECT USING (organization_id = get_user_organization_id());
CREATE POLICY time_entries_write ON public.time_entries
  FOR ALL
  USING (organization_id = get_user_organization_id()
         AND (user_id = (auth.uid())::text OR has_permission('payroll', 2) OR is_user_admin()))
  WITH CHECK (organization_id = get_user_organization_id()
         AND (user_id = (auth.uid())::text OR has_permission('payroll', 2) OR is_user_admin()));

-- ── time_off_requests: read org-wide; employees own theirs; approve = perm ───
-- Requester column is photographer_id. Approve/deny = a user with timeOffApprovals
-- edit (or admin). Employees create/edit/cancel their OWN requests.
DROP POLICY IF EXISTS time_off_requests_org_access ON public.time_off_requests;
CREATE POLICY tor_select ON public.time_off_requests
  FOR SELECT USING (organization_id = get_user_organization_id());
CREATE POLICY tor_write ON public.time_off_requests
  FOR ALL
  USING (organization_id = get_user_organization_id()
         AND (photographer_id = (auth.uid())::text OR has_permission('timeOffApprovals', 2) OR is_user_admin()))
  WITH CHECK (organization_id = get_user_organization_id()
         AND (photographer_id = (auth.uid())::text OR has_permission('timeOffApprovals', 2) OR is_user_admin()));

-- ── sessions / session_days: read org-wide; write = schedule-edit OR admin ───
-- ⚠️ HIGHEST RISK — this gates the whole schedule. iOS SessionService and the web
-- app already gate schedule editing on the `schedule` permission client-side, so
-- this should match; but APPLY LAST and confirm a manager can still create/edit a
-- session and a photographer still can't. To skip for now, don't run this block.
DROP POLICY IF EXISTS sessions_org_access ON public.sessions;
CREATE POLICY sessions_select ON public.sessions
  FOR SELECT USING (organization_id = get_user_organization_id());
CREATE POLICY sessions_write ON public.sessions
  FOR ALL
  USING (organization_id = get_user_organization_id()
         AND (has_permission('schedule', 2) OR is_user_admin()))
  WITH CHECK (organization_id = get_user_organization_id()
         AND (has_permission('schedule', 2) OR is_user_admin()));

DROP POLICY IF EXISTS session_days_org_access ON public.session_days;
CREATE POLICY session_days_select ON public.session_days
  FOR SELECT USING (EXISTS (SELECT 1 FROM public.sessions s
                            WHERE s.id = session_days.session_id
                              AND s.organization_id = get_user_organization_id()));
CREATE POLICY session_days_write ON public.session_days
  FOR ALL
  USING (EXISTS (SELECT 1 FROM public.sessions s
                 WHERE s.id = session_days.session_id
                   AND s.organization_id = get_user_organization_id())
         AND (has_permission('schedule', 2) OR is_user_admin()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.sessions s
                 WHERE s.id = session_days.session_id
                   AND s.organization_id = get_user_organization_id())
         AND (has_permission('schedule', 2) OR is_user_admin()));

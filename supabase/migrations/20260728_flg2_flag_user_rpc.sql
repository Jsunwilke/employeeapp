-- FLG.2 — let MANAGERS flag people, not just org admins.
--
-- THE MISMATCH FLG.1 SURFACED
-- The app gates FlagUserView on Permissions.has("users", .edit), which managers hold. The
-- database disagreed: RLS users_update_org is
--     (id = auth.uid()::text OR is_admin_of_org(organization_id))
-- so a non-admin could only ever update their OWN row. A manager pressing Flag matched zero
-- rows -- and before FLG.1 added the zero-row check, was told it had worked. Operator
-- decision 2026-07-28: managers should be able to flag.
--
-- WHY AN RPC AND NOT A WIDER POLICY
-- The obvious fix is to add has_permission('users', 2) to users_update_org. That was
-- rejected, and the reason is worth keeping: users_update_org governs the WHOLE ROW. Widening
-- it would hand every users-edit manager the ability to rewrite any colleague's name, email,
-- phone, home address, photo, preferences and apns_token -- silencing someone's push
-- notifications, among other things -- when what was asked for was the ability to flag.
-- trg_prevent_privilege_self_escalation would still protect role and pay, so the blast radius
-- is not unbounded, but it is far wider than the request and impossible to narrow later
-- without taking something away.
--
-- A SECURITY DEFINER function grants exactly one capability and nothing else, which is the
-- shape this database already uses for privileged writes -- the five chat RPCs added
-- 2026-07-13 (mark_conversation_read, toggle_pin_conversation, add/remove participants,
-- leave_conversation) are all SECURITY DEFINER with actor = auth.uid() guards, and moving
-- writes behind RPCs is the direction CHAT_REBUILD_NOTES.md argues for generally. So
-- users_update_org is left EXACTLY as it is.
--
-- DELETE-FIRST: TeamService.flagUser/unflagUser no longer write public.users directly. The
-- direct .update() path is removed in the same commit as these functions land.
--
-- BECAUSE THESE RUN AS postgres (which has rolbypassrls), THE CHECKS BELOW ARE THE ONLY
-- GUARD. There is no RLS behind them to catch a mistake. Hence: explicit permission check,
-- explicit same-organization check, explicit self check, and a row-count assertion.

CREATE OR REPLACE FUNCTION public.flag_user(p_user_id text, p_note text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor      text := auth.uid()::text;
  v_actor_org  text;
  v_target_org text;
  v_note       text := btrim(coalesce(p_note, ''));
  v_rows       int;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to flag a user' USING ERRCODE = '42501';
  END IF;

  -- Admins, or anyone the org has granted users-edit. Same helpers the RLS policies use --
  -- BUT the context is not the same, and an audit caught the difference before it bit:
  -- is_user_admin() returns NULL (not false) when the caller has no users row, and inside an
  -- RLS USING clause NULL means DENY while inside plpgsql IF NOT (...) NULL means the RAISE
  -- is SKIPPED. Moving the helper from a fail-closed context into a fail-open one, unwrapped,
  -- would have let a JWT with no users row (a just-deleted employee inside their token's
  -- lifetime, a fresh signup before the row lands) fall through to the org check -- which
  -- happens to catch it today, but the permission guard must not depend on its neighbour.
  -- COALESCE pins NULL to false: fail closed.
  IF NOT (coalesce(public.is_user_admin(), false)
          OR coalesce(public.has_permission('users', 2), false)) THEN
    RAISE EXCEPTION 'You do not have permission to flag users' USING ERRCODE = '42501';
  END IF;

  IF v_note = '' THEN
    RAISE EXCEPTION 'A flag note is required' USING ERRCODE = '22023';
  END IF;

  SELECT organization_id INTO v_actor_org  FROM public.users WHERE id = v_actor;
  SELECT organization_id INTO v_target_org FROM public.users WHERE id = p_user_id;

  IF v_target_org IS NULL THEN
    RAISE EXCEPTION 'No such user' USING ERRCODE = 'P0002';
  END IF;

  -- The tenant boundary. Without this an admin of one organization could flag anybody in
  -- another, because this function bypasses RLS.
  IF v_actor_org IS NULL OR v_actor_org IS DISTINCT FROM v_target_org THEN
    RAISE EXCEPTION 'You can only flag users in your own organization' USING ERRCODE = '42501';
  END IF;

  IF p_user_id = v_actor THEN
    RAISE EXCEPTION 'You cannot flag yourself' USING ERRCODE = '42501';
  END IF;

  UPDATE public.users
     SET is_flagged = true,
         flag_note  = v_note,
         flagged_by = v_actor
   WHERE id = p_user_id;

  -- Belt and braces. Every reason a row could be missing is checked above, so reaching this
  -- means an assumption broke -- and a silent no-op is exactly the failure FLG.1 existed to
  -- stop. trg_user_flagged_notification fires on this UPDATE and sends the push.
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Flagging % affected % rows, expected 1', p_user_id, v_rows;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.unflag_user(p_user_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor      text := auth.uid()::text;
  v_actor_org  text;
  v_target_org text;
  v_rows       int;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to unflag a user' USING ERRCODE = '42501';
  END IF;

  -- COALESCE for the same fail-closed reason as flag_user: NULL from a missing users row
  -- must deny, not skip the check.
  IF NOT (coalesce(public.is_user_admin(), false)
          OR coalesce(public.has_permission('users', 2), false)) THEN
    RAISE EXCEPTION 'You do not have permission to unflag users' USING ERRCODE = '42501';
  END IF;

  SELECT organization_id INTO v_actor_org  FROM public.users WHERE id = v_actor;
  SELECT organization_id INTO v_target_org FROM public.users WHERE id = p_user_id;

  IF v_target_org IS NULL THEN
    RAISE EXCEPTION 'No such user' USING ERRCODE = 'P0002';
  END IF;

  IF v_actor_org IS NULL OR v_actor_org IS DISTINCT FROM v_target_org THEN
    RAISE EXCEPTION 'You can only unflag users in your own organization' USING ERRCODE = '42501';
  END IF;

  -- Self-unflagging is NOT blocked here, deliberately, and it changes nothing: a user could
  -- already clear their own is_flagged through users_update_org, which is a known and
  -- accepted item from the 2026-07-12 RLS remediation. Blocking it in this function while
  -- leaving the direct path open would be theatre.
  UPDATE public.users
     SET is_flagged = false,
         flag_note  = NULL,
         flagged_by = NULL
   WHERE id = p_user_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Unflagging % affected % rows, expected 1', p_user_id, v_rows;
  END IF;
END;
$function$;

-- anon must never reach these; they are privileged writes on a shared multi-tenant table.
REVOKE ALL ON FUNCTION public.flag_user(text, text)   FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.unflag_user(text)       FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.flag_user(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unflag_user(text)     TO authenticated;

COMMENT ON FUNCTION public.flag_user(text, text) IS
  'FLG.2: flags a user in the caller''s own organization. Callable by an org admin or anyone '
  'with users-edit (role_permissions area users, level >= 2). Exists so managers can flag '
  'without widening users_update_org, which governs the whole row. Runs as postgres and '
  'therefore bypasses RLS: the checks inside are the only guard.';

COMMENT ON FUNCTION public.unflag_user(text) IS
  'FLG.2: clears a flag on a user in the caller''s own organization. Same permission rule as '
  'flag_user.';

-- REVERSIBLE WITH:
--   DROP FUNCTION IF EXISTS public.flag_user(text, text);
--   DROP FUNCTION IF EXISTS public.unflag_user(text);
--   (and restoring the direct .update() calls in TeamService.swift)

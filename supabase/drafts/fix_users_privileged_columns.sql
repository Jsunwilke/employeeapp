-- CRITICAL 1 (corrected) — the column REVOKE approach is a no-op because
-- authenticated/anon hold a TABLE-level UPDATE grant on public.users. Instead, guard
-- the sensitive columns with a BEFORE UPDATE trigger: a NON-admin may not CHANGE them
-- on any row (including their own). Profile edits don't touch these columns, so they're
-- unaffected; admins and the dashboard/service role (auth.uid() IS NULL) still can.
--
-- Columns guarded: privilege (role, role_id, organization_id) + compensation/status
-- (hourly_rate, salary_amount, compensation_type, amount_per_mile, overtime_threshold,
-- is_accountant, is_active). NOTE: is_flagged is intentionally NOT here — managers set it
-- on other users from the app; guarding it needs the manager-or-admin check (see the
-- HIGH-items follow-up), or it would break flagging.
--
-- Paste into the Supabase SQL editor for project nofegnmrgnanpznavlqy.

CREATE OR REPLACE FUNCTION public.prevent_privilege_self_escalation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF ( NEW.role               IS DISTINCT FROM OLD.role
    OR NEW.role_id            IS DISTINCT FROM OLD.role_id
    OR NEW.organization_id    IS DISTINCT FROM OLD.organization_id
    OR NEW.hourly_rate        IS DISTINCT FROM OLD.hourly_rate
    OR NEW.salary_amount      IS DISTINCT FROM OLD.salary_amount
    OR NEW.compensation_type  IS DISTINCT FROM OLD.compensation_type
    OR NEW.amount_per_mile    IS DISTINCT FROM OLD.amount_per_mile
    OR NEW.overtime_threshold IS DISTINCT FROM OLD.overtime_threshold
    OR NEW.is_accountant      IS DISTINCT FROM OLD.is_accountant
    OR NEW.is_active          IS DISTINCT FROM OLD.is_active )
   AND auth.uid() IS NOT NULL           -- allow dashboard / service role
   AND NOT public.is_user_admin() THEN  -- allow org admins
    RAISE EXCEPTION 'Not authorized to change privileged user fields (role/pay/status)';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_prevent_privilege_self_escalation ON public.users;
CREATE TRIGGER trg_prevent_privilege_self_escalation
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.prevent_privilege_self_escalation();

-- Verify: should list the trigger.
-- select tgname from pg_trigger where tgname = 'trg_prevent_privilege_self_escalation';

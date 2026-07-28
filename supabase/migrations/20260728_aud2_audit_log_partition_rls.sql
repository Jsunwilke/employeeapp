-- AUD.2 — close a cross-tenant read of every audited row.
--
-- THE HOLE
-- public.audit_log is a PARTITIONED table with RLS enabled and one policy,
-- audit_log_select USING (organization_id = my_org()). Its ten partitions
-- (audit_log_2026_05 .. audit_log_2027_01, audit_log_default) had RLS switched OFF, zero
-- policies, and `authenticated` holding SELECT on every one of them.
--
-- Postgres applies the policies of the table NAMED IN THE QUERY. Reading a partition
-- directly therefore consults no policy at all, and the parent's org scoping is simply not
-- in the plan. Any signed-in employee of any tenant could read every other tenant's audited
-- rows with an ordinary PostgREST call against a partition endpoint.
--
-- Measured live, as a real non-admin employee, before this migration:
--   SELECT count(DISTINCT organization_id) FROM public.audit_log             -> 1  (correct)
--   SELECT count(DISTINCT organization_id) FROM public.audit_log_2026_07     -> 2  (leak)
--
-- WHY IT MATTERS MORE THAN "an audit table"
-- phase_o_audit_users writes to_jsonb(NEW) -- THE WHOLE ROW -- on every change to
-- public.users. So these partitions already hold hourly_rate and apns_token for every
-- employee of every organization, and as of FLG.1 they hold flag_note, which is a manager's
-- written criticism of a named person. This is the PUB.1 lesson again: a redaction is only
-- as good as the number of STORES it covers, not the number of call sites. Narrowing the
-- app's SELECT column lists did nothing about this copy.
--
-- THE FIX, AND WHY IT IS THIS ONE
-- Enable RLS on each partition and add NO policy. RLS with no policy is default-deny for any
-- role that does not bypass it, so direct partition access returns nothing, while reads
-- through the parent keep using the parent's org policy exactly as before. Adding a
-- duplicate policy per partition was rejected: it would be a second copy of the org rule to
-- keep in sync, for an access path nothing legitimately uses.
--
-- Verified live before applying, in a rolled-back transaction, as a real non-admin employee:
--   parent org count      before 1 -> after 1   (legitimate access UNCHANGED)
--   partition org count   before 2 -> after 0   (leak closed)
--
-- AND THE WRITE PATH, ALSO PROVEN BEFORE APPLYING: audit writes still work.
-- phase_o_audit_log_trigger is SECURITY DEFINER owned by postgres, postgres has
-- rolbypassrls = true (both checked), and with RLS enabled on all ten partitions an ordinary
-- authenticated UPDATE on public.users succeeded and audit_log grew by exactly one row.
-- CORRECTION, from the fix-round audit: an earlier draft called a blocked audit insert
-- "catastrophic -- every write to every audited table would have started failing". That
-- overstates it. The trigger wraps its INSERT in EXCEPTION WHEN OTHERS THEN RAISE NOTICE, so
-- a blocked insert would never have failed the caller's write; the actual risk was the
-- opposite and quieter one -- audit rows silently lost, reported at NOTICE, which
-- log_min_messages (warning) discards. That swallow-at-NOTICE pattern is pre-existing,
-- shared with record_audit_read_event, and is recorded in AUDIT_ROADMAP rather than changed
-- here: relogging a live shared audit trigger is its own decision, not a rider on this one.

ALTER TABLE public.audit_log_2026_05 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log_2026_06 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log_2026_07 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log_2026_08 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log_2026_09 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log_2026_10 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log_2026_11 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log_2026_12 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log_2027_01 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log_default ENABLE ROW LEVEL SECURITY;

-- AND THE PART WITHOUT WHICH THIS REOPENS IN A MONTH.
-- ensure_audit_log_partition() is called by the audit-log-partition-maintenance cron every
-- month to create a rolling six-month buffer of partitions. It created them with CREATE TABLE
-- ... PARTITION OF and nothing else, and Supabase's default privileges grant `authenticated`
-- SELECT on new tables in public -- which is exactly how ten partitions came to be readable.
-- Fixing only the existing ten would have left the next one wide open, and the fix would have
-- looked done. The partition is now secured at the moment it is created.
CREATE OR REPLACE FUNCTION public.ensure_audit_log_partition(p_month timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
 SET lock_timeout TO '5s'
AS $function$
DECLARE
    v_month_start timestamptz := date_trunc('month', p_month);
    v_month_end timestamptz := v_month_start + interval '1 month';
    v_partition_name text := 'audit_log_' || to_char(v_month_start, 'YYYY_MM');
    v_rls_on boolean;
BEGIN
    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS public.%I PARTITION OF public.audit_log FOR VALUES FROM (%L) TO (%L)',
        v_partition_name, v_month_start, v_month_end
    );

    -- AUD.2: default-deny on direct access to the new partition. Reads through the parent are
    -- unaffected and keep using audit_log_select. Without this every new month reopens the
    -- cross-tenant read this migration exists to close.
    --
    -- The ALTER runs ONLY when RLS is actually off. ALTER TABLE takes an ACCESS EXCLUSIVE
    -- lock BEFORE discovering it has nothing to do, and the maintenance cron sweeps the
    -- CURRENT month's partition too -- the one every audited write in the database is landing
    -- in right now. The cron runs as postgres, which carries no lock_timeout of its own, so
    -- an unconditional ALTER waiting behind any long reader would have queued every write to
    -- all audited tables behind it, monthly, at 03:00 on the 1st. Skipping when RLS is
    -- already on makes the steady-state run lock-free, and the belt-and-braces lock_timeout
    -- above bounds the one genuine ALTER a new partition needs. On a timeout the exception
    -- escapes to maintain_audit_log_partitions, whose per-month handler warns and moves on --
    -- and because that wraps each month in a subtransaction, the CREATE rolls back with the
    -- failed ALTER, so a partition can never be left created-but-unsecured.
    SELECT c.relrowsecurity INTO v_rls_on
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = v_partition_name;

    IF NOT coalesce(v_rls_on, false) THEN
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_partition_name);
    END IF;
END;
$function$;

COMMENT ON FUNCTION public.ensure_audit_log_partition(timestamp with time zone) IS
  'AUD.1 created the monthly audit_log partition. AUD.2 additionally enables row level '
  'security on it with no policy, so the partition is default-deny on direct access while '
  'reads through public.audit_log keep using audit_log_select. Do not remove that line: '
  'Supabase default privileges grant authenticated SELECT on new tables in public, so a '
  'partition created without it is readable across every tenant.';

-- REVERSIBLE WITH (restores the pre-AUD.2 behaviour, INCLUDING the hole):
--   ALTER TABLE public.audit_log_2026_05 DISABLE ROW LEVEL SECURITY;  -- ... and each other partition
--   and dropping the ALTER ... ENABLE ROW LEVEL SECURITY line from ensure_audit_log_partition().

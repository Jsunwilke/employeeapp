-- PSH.2 — the three reminder pushes that are clock-driven, not event-driven.
--
-- WHY SQL DISPATCHERS AND NOT THE clock-reminder EDGE FUNCTION. That function was
-- deployed in PSH.1 (code-corrected, never wired) and turned out to be unbuildable-on:
-- it reads time_entries.clock_in_time / clock_out_time (the live columns are start_time
-- / end_time), embeds sessions.photographers (removed by the MD7 crew move — the crew
-- lives on session_days), compares stored local wall-clock times against the Deno
-- runtime's UTC clock, and has no caller-auth gate. Every one of those is the PSH.1
-- defect class: code that looks correct and targets things that do not exist. Rather
-- than patch four defects into a second privileged sender, the recipient queries live
-- HERE, next to the data they read, and the one canonical gated sender
-- (send-notification) does the pushing — the same split every trigger in
-- 20260729_psh2_push_triggers.sql uses. The edge function is deleted in this commit
-- (delete-first).
--
-- TIMEZONES. session_days.date / start_time are LOCAL wall-clock text (YYYY-MM-DD /
-- HH24:MI). The org's timezone comes from organizations.preferences->>'timezone' with an
-- America/Chicago fallback — the same convention daily-workflow-check already uses. Each
-- org is evaluated on its own clock; a bad timezone string skips that org with a WARNING
-- instead of failing the whole run.

-- ============================================================================
-- Clock-in: "your session starts within 30 minutes and you haven't clocked in"
-- ============================================================================
-- Runs every 30 minutes. The window is FLOORED to the half-hour grid — [10:30, 11:00)
-- regardless of whether cron fired at 10:30:00 or 10:31:40 — so a late run can neither
-- skip a session nor overlap the next run's window and double-remind. (The 00:00 run
-- floors to the NEW day's 00:00 and covers [00:00, 00:30) correctly — an earlier draft
-- of this comment claimed that window was unreachable, which the fix-round audit
-- disproved by reading the arithmetic.)

CREATE OR REPLACE FUNCTION public.dispatch_clock_in_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org       record;
  v_local     timestamp;
  v_floor     timestamp;
  v_today     text;
  v_win_start text;
  v_win_end   text;
  v_day       record;
  v_crew      text[];
BEGIN
  FOR v_org IN
    SELECT id, coalesce(preferences->>'timezone', 'America/Chicago') AS tz
      FROM public.organizations
     WHERE is_active IS NOT FALSE
  LOOP
    BEGIN
      v_local := now() AT TIME ZONE v_org.tz;
      v_floor := date_trunc('hour', v_local)
                 + make_interval(mins => (extract(minute FROM v_local)::int / 30) * 30);
      v_today     := to_char(v_floor, 'YYYY-MM-DD');
      v_win_start := to_char(v_floor, 'HH24:MI');
      v_win_end   := to_char(v_floor + interval '30 minutes', 'HH24:MI');
      IF v_win_end = '00:00' THEN
        v_win_end := '24:00';  -- keep the lexicographic compare monotonic at midnight
      END IF;

      FOR v_day IN
        SELECT s.id AS sid, s.school_name, sd.start_time,
               (SELECT array_agg(DISTINCT elem->>'id')
                  FROM jsonb_array_elements(coalesce(sd.photographers, '[]'::jsonb)) elem
                 WHERE coalesce(elem->>'id', '') <> '') AS crew
          FROM public.session_days sd
          JOIN public.sessions s ON s.id = sd.session_id
         WHERE s.organization_id = v_org.id
           AND s.is_published IS TRUE
           AND s.is_time_off IS NOT TRUE
           AND sd.date = v_today
           AND sd.start_time IS NOT NULL
           AND sd.start_time >= v_win_start
           AND sd.start_time <  v_win_end
      LOOP
        -- Suppress the reminder for anyone who (a) has a time entry for THIS session
        -- TODAY — day-scoped, so day 1's entry cannot silence day 2 of a multi-day
        -- session — or (b) is currently clocked in on an entry STARTED TODAY. (b)
        -- matters because session_id is optional at clock-in and NULL on the
        -- overwhelming majority of real entries (live: 239 of the last 273) — keying on
        -- the session alone would nag people already on the clock. The started-today
        -- bound keeps a stale never-closed entry from a past day from silencing every
        -- future clock-in reminder forever (second fix-round audit) — a stale open
        -- entry is the 09:00 clock-OUT dispatcher's job to nag about, not a licence to
        -- skip clock-in reminders.
        SELECT array_agg(x) INTO v_crew
          FROM unnest(coalesce(v_day.crew, ARRAY[]::text[])) x
         WHERE NOT EXISTS (
                 SELECT 1 FROM public.time_entries te
                  WHERE te.user_id = x
                    AND (
                          (te.session_id = v_day.sid AND te.date = v_today)
                          OR (te.status = 'clocked-in' AND te.end_time IS NULL
                              AND te.start_time IS NOT NULL
                              AND (te.start_time AT TIME ZONE v_org.tz)::date = v_floor::date)
                        )
               );

        CONTINUE WHEN v_crew IS NULL;

        PERFORM public.psh2_send_push(
          v_crew,
          'Clock-In Reminder',
          'Your session at ' || coalesce(v_day.school_name, 'your school')
            || ' starts at ' || v_day.start_time || '. Don''t forget to clock in!',
          'clock_reminder',
          jsonb_build_object(
            -- handleClockReminderNotification requires reminderType.
            'reminderType', 'clock_in',
            'sessionId',    v_day.sid,
            'schoolName',   coalesce(v_day.school_name, '')
          )
        );
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'dispatch_clock_in_reminders: org % failed (%): %', v_org.id, SQLSTATE, SQLERRM;
    END;
  END LOOP;
END;
$function$;

-- ============================================================================
-- Clock-out: "you're still clocked in"
-- ============================================================================
-- Runs hourly; each org hears it only at deliberate local hours, so nobody is nagged
-- every sixty minutes:
--   18:00 and 21:00 local — still clocked in on an entry started today
--   09:00 local          — still clocked in on an entry started a PREVIOUS day
--                          (forgot entirely; the entry needs closing or correcting)

CREATE OR REPLACE FUNCTION public.dispatch_clock_out_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org   record;
  v_local timestamp;
  v_hour  int;
  v_users text[];
BEGIN
  FOR v_org IN
    SELECT id, coalesce(preferences->>'timezone', 'America/Chicago') AS tz
      FROM public.organizations
     WHERE is_active IS NOT FALSE
  LOOP
    BEGIN
      v_local := now() AT TIME ZONE v_org.tz;
      v_hour  := extract(hour FROM v_local)::int;

      IF v_hour IN (18, 21) THEN
        SELECT array_agg(DISTINCT te.user_id) INTO v_users
          FROM public.time_entries te
         WHERE te.organization_id = v_org.id
           AND te.status = 'clocked-in'
           AND te.end_time IS NULL
           AND te.start_time IS NOT NULL
           AND (te.start_time AT TIME ZONE v_org.tz)::date = v_local::date;

        PERFORM public.psh2_send_push(
          v_users,
          'Clock-Out Reminder',
          'You''re still clocked in. Don''t forget to clock out!',
          'clock_reminder',
          jsonb_build_object('reminderType', 'clock_out')
        );
      ELSIF v_hour = 9 THEN
        SELECT array_agg(DISTINCT te.user_id) INTO v_users
          FROM public.time_entries te
         WHERE te.organization_id = v_org.id
           AND te.status = 'clocked-in'
           AND te.end_time IS NULL
           AND te.start_time IS NOT NULL
           AND (te.start_time AT TIME ZONE v_org.tz)::date < v_local::date;

        PERFORM public.psh2_send_push(
          v_users,
          'Clock-Out Reminder',
          'You''re still clocked in from a previous day — please clock out or correct your time entry.',
          'clock_reminder',
          jsonb_build_object('reminderType', 'clock_out')
        );
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'dispatch_clock_out_reminders: org % failed (%): %', v_org.id, SQLSTATE, SQLERRM;
    END;
  END LOOP;
END;
$function$;

-- ============================================================================
-- Daily report: "you worked today and haven't filed a report"
-- ============================================================================
-- Runs hourly; fires per org at 19:00 local. Recipients: everyone on today's crew
-- (session_days.photographers) who has not FILED a report today — the test is the
-- filing timestamp (created_at, org-local), NOT the report's date column. The date
-- column is stamped with the UTC calendar date of the picked day (verified in
-- DailyJobReportService.createReport), which makes it ambiguous around the 19:00 run:
-- yesterday's after-the-nag filing and today's on-time filing carry the SAME stamp, so
-- keying on it wrongly silenced tomorrow's reminder for exactly the people who file
-- after the nag (fix-round audit, M1). "Did they file anything today, their time" is
-- unambiguous and is what the reminder actually wants to know. The date-stamp quirk
-- itself is recorded in AUDIT_ROADMAP for the report arc to fix at the source.

CREATE OR REPLACE FUNCTION public.dispatch_report_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org   record;
  v_local timestamp;
  v_today text;
  v_users text[];
BEGIN
  FOR v_org IN
    SELECT id, coalesce(preferences->>'timezone', 'America/Chicago') AS tz
      FROM public.organizations
     WHERE is_active IS NOT FALSE
  LOOP
    BEGIN
      v_local := now() AT TIME ZONE v_org.tz;
      CONTINUE WHEN extract(hour FROM v_local)::int <> 19;
      v_today := to_char(v_local, 'YYYY-MM-DD');

      SELECT array_agg(DISTINCT crew.id) INTO v_users
        FROM public.session_days sd
        JOIN public.sessions s ON s.id = sd.session_id
        CROSS JOIN LATERAL (
          SELECT elem->>'id' AS id
            FROM jsonb_array_elements(coalesce(sd.photographers, '[]'::jsonb)) elem
        ) crew
       WHERE s.organization_id = v_org.id
         AND s.is_published IS TRUE
         AND s.is_time_off IS NOT TRUE
         AND sd.date = v_today
         AND coalesce(crew.id, '') <> ''
         AND NOT EXISTS (
               SELECT 1 FROM public.daily_job_reports djr
                WHERE djr.user_id = crew.id
                  AND (djr.created_at AT TIME ZONE v_org.tz)::date = v_local::date
             );

      PERFORM public.psh2_send_push(
        v_users,
        'Daily Report Reminder',
        'Don''t forget to submit your daily job report for today''s sessions.',
        'report_reminder',
        jsonb_build_object('date', v_today)
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'dispatch_report_reminders: org % failed (%): %', v_org.id, SQLSTATE, SQLERRM;
    END;
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION public.dispatch_clock_in_reminders()  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dispatch_clock_out_reminders() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dispatch_report_reminders()    FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- Schedules (delete-first so a re-run cannot double-schedule)
-- ============================================================================

DO $do$
DECLARE
  v_job record;
BEGIN
  FOR v_job IN
    SELECT jobid FROM cron.job
     WHERE jobname IN ('psh2-clock-in-reminders', 'psh2-clock-out-reminders',
                       'psh2-report-reminders')
  LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;
END;
$do$;

SELECT cron.schedule('psh2-clock-in-reminders',  '*/30 * * * *',
                     $cmd$SELECT public.dispatch_clock_in_reminders()$cmd$);
SELECT cron.schedule('psh2-clock-out-reminders', '0 * * * *',
                     $cmd$SELECT public.dispatch_clock_out_reminders()$cmd$);
SELECT cron.schedule('psh2-report-reminders',    '0 * * * *',
                     $cmd$SELECT public.dispatch_report_reminders()$cmd$);

COMMENT ON FUNCTION public.dispatch_clock_in_reminders() IS
  'PSH.2: every 30 minutes, reminds crew whose session starts inside the next half-hour '
  'grid window and who have no time entry for it. Org-local time via '
  'organizations.preferences timezone (America/Chicago fallback).';
COMMENT ON FUNCTION public.dispatch_clock_out_reminders() IS
  'PSH.2: hourly; at 18:00/21:00 org-local reminds anyone still clocked in today, at '
  '09:00 anyone still clocked in from a previous day.';
COMMENT ON FUNCTION public.dispatch_report_reminders() IS
  'PSH.2: at 19:00 org-local, reminds today''s crew who have not filed a daily job '
  'report (matching iOS''s UTC-date stamping quirk, recorded in AUDIT_ROADMAP).';

-- REVERSIBLE WITH:
--   SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname LIKE 'psh2-%';
--   DROP FUNCTION IF EXISTS public.dispatch_clock_in_reminders(),
--     public.dispatch_clock_out_reminders(), public.dispatch_report_reminders();

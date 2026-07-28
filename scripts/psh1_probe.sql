-- PSH.1 live-database probe — READ ONLY. No writes, no DDL, nothing destructive.
-- Run with:
--   cd ~/Desktop/Focal-Point-Supabase && set -a && . ./.env.local && set +a \
--     && psql "$SUPABASE_DB_URL" -f ~/Desktop/employeeapp/scripts/psh1_probe.sql
--
-- Answers the four questions PSH.1 cannot settle from the two repos.

\echo '=== Q1. Is the sessions notification trigger actually PRESENT? ==='
-- The migration 20260714_sec1_session_notification_vault.sql is committed in the web
-- repo. Committed is not applied. If this returns no rows, the one live push path is
-- not live at all and that is an independent second cause.
SELECT t.tgname          AS trigger_name,
       c.relname         AS on_table,
       t.tgenabled       AS enabled_flag,   -- 'O' = enabled, 'D' = DISABLED
       p.proname         AS calls_function
FROM pg_trigger t
JOIN pg_class c     ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p      ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal
  AND n.nspname = 'public'
  AND (c.relname IN ('sessions','session_days','messages','photo_critiques',
                     'time_off_requests','task_notifications')
       OR p.proname ILIKE '%notif%')
ORDER BY c.relname, t.tgname;

\echo ''
\echo '=== Q1b. Every trigger anywhere that makes an outbound HTTP call ==='
-- Catches dashboard-created webhooks that exist in no migration.
SELECT n.nspname||'.'||c.relname AS on_table, t.tgname, p.proname
FROM pg_trigger t
JOIN pg_class c     ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p      ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal
  AND (pg_get_functiondef(p.oid) ILIKE '%net.http_post%'
    OR pg_get_functiondef(p.oid) ILIKE '%supabase_functions.http_request%')
ORDER BY 1, 2;

\echo ''
\echo '=== Q2. Does the Vault secret the trigger depends on exist? ==='
-- notify_session_change() reads a Vault secret; if it is missing the function
-- RAISE NOTICEs and returns, silently sending nothing. Names only, never values.
SELECT name, created_at, updated_at FROM vault.secrets ORDER BY name;

\echo ''
\echo '=== Q3. Is users.apns_token actually populated? ==='
-- Counts only. No token values are selected.
SELECT count(*)                                                  AS total_users,
       count(apns_token)                                         AS have_apns_token,
       count(fcm_token)                                          AS have_fcm_token,
       count(*) FILTER (WHERE apns_token IS NOT NULL
                          AND fcm_token IS NOT NULL)             AS have_both,
       count(DISTINCT length(apns_token))                        AS distinct_apns_lengths
FROM public.users;

\echo ''
\echo '-- APNs device tokens are 64 hex chars. Anything else is not a usable token.'
SELECT length(apns_token) AS token_length, count(*) AS n
FROM public.users WHERE apns_token IS NOT NULL
GROUP BY 1 ORDER BY 2 DESC;

\echo ''
\echo '=== Q4. notification_queue — does it exist, and is anything draining it? ==='
SELECT to_regclass('public.notification_queue') AS queue_table_exists;

SELECT status, count(*) AS rows,
       min(created_at) AS oldest, max(created_at) AS newest
FROM public.notification_queue
GROUP BY status ORDER BY 2 DESC;

\echo ''
\echo '-- Which notification types have ever been queued (roadmap claims only one)'
SELECT notification_type, count(*) AS n, max(created_at) AS newest
FROM public.notification_queue
GROUP BY 1 ORDER BY 2 DESC;

\echo ''
\echo '=== Q5. Which cron jobs are REGISTERED right now (committed is not scheduled) ==='
SELECT jobid, schedule, jobname, active,
       left(regexp_replace(command, '\s+', ' ', 'g'), 90) AS command_head
FROM cron.job ORDER BY jobname;

\echo ''
\echo '-- Recent cron outcomes: is daily-workflow-check actually running?'
SELECT j.jobname, d.status, count(*) AS runs, max(d.start_time) AS last_run
FROM cron.job_run_details d
JOIN cron.job j ON j.jobid = d.jobid
WHERE d.start_time > now() - interval '7 days'
GROUP BY 1, 2 ORDER BY 1, 3 DESC;

\echo ''
\echo '=== Q6. Outbound HTTP responses — did the session trigger ever fire, and what did APNs say? ==='
-- pg_net keeps a short rolling window. A 400 BadDeviceToken here would be direct
-- confirmation of the sandbox-vs-production mismatch.
SELECT status_code, count(*) AS n, max(created) AS newest
FROM net._http_response
GROUP BY 1 ORDER BY 2 DESC;

\echo ''
\echo '=== Q7. task_notifications — is the id column defaulted, and do the broken writers fail? ==='
-- Three of seven web writers omit id or write a non-existent `read` column.
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='public' AND table_name='task_notifications'
ORDER BY ordinal_position;

\echo ''
\echo '=== Q8. Does users have the columns both senders disagree about? ==='
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema='public' AND table_name='users'
  AND column_name IN ('apns_token','fcm_token','fcm_token_updated_at',
                      'notification_preferences','email_notifications')
ORDER BY column_name;

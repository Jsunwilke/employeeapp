-- Migration: APNs Push Notifications Setup
-- This migration sets up the database for APNs push notifications

-- 1. Add apns_token column to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS apns_token TEXT;

-- Create index for efficient token lookups
CREATE INDEX IF NOT EXISTS idx_users_apns_token ON users(apns_token) WHERE apns_token IS NOT NULL;

-- 2. Enable required extensions
CREATE EXTENSION IF NOT EXISTS pg_net; -- For HTTP requests from Postgres
CREATE EXTENSION IF NOT EXISTS pg_cron; -- For scheduled jobs

-- 3. Grant pg_cron permissions (run as superuser)
-- Note: This may need to be run separately with appropriate permissions
-- GRANT USAGE ON SCHEMA cron TO postgres;
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA cron TO postgres;

-- 4. Create scheduled jobs for clock reminders
-- Note: Replace YOUR_PROJECT_REF with your actual Supabase project reference

-- Clock-in reminder: Every 5 minutes during work hours (6 AM - 6 PM)
-- Checks for sessions starting in the next 30 minutes
SELECT cron.schedule(
    'clock-in-reminder',
    '*/5 6-18 * * *',  -- Every 5 min, 6 AM to 6 PM
    $$
    SELECT net.http_post(
        url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/clock-reminder',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
        ),
        body := '{"type": "clock_in"}'::jsonb
    );
    $$
);

-- Clock-out reminder: 8 PM daily
-- Reminds employees who are still clocked in
SELECT cron.schedule(
    'clock-out-reminder',
    '0 20 * * *',  -- 8 PM daily
    $$
    SELECT net.http_post(
        url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/clock-reminder',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
        ),
        body := '{"type": "clock_out"}'::jsonb
    );
    $$
);

-- Daily report reminder: 7:30 PM daily
-- Reminds employees to submit their daily job reports
SELECT cron.schedule(
    'daily-report-reminder',
    '30 19 * * *',  -- 7:30 PM daily
    $$
    SELECT net.http_post(
        url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-notification',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
        ),
        body := jsonb_build_object(
            'title', 'Daily Report Reminder',
            'body', 'Don''t forget to submit your daily job report!',
            'type', 'report_reminder',
            'userIds', (
                SELECT array_agg(DISTINCT te.user_id)
                FROM time_entries te
                WHERE te.clock_in_time::date = CURRENT_DATE
                AND NOT EXISTS (
                    SELECT 1 FROM daily_job_reports djr
                    WHERE djr.user_id = te.user_id
                    AND djr.report_date = CURRENT_DATE
                )
            )
        )
    );
    $$
);

-- 5. View scheduled jobs (for verification)
-- SELECT * FROM cron.job;

-- IMPORTANT: Database Webhooks need to be configured in Supabase Dashboard:
-- Go to Database > Webhooks and create:
--
-- 1. Session Notification Webhook:
--    - Name: session-notification
--    - Table: sessions
--    - Events: INSERT, UPDATE
--    - Method: POST
--    - URL: https://YOUR_PROJECT_REF.supabase.co/functions/v1/session-notification
--    - Headers: Authorization: Bearer <service_role_key>
--
-- 2. Chat Notification Webhook:
--    - Name: chat-notification
--    - Table: messages
--    - Events: INSERT
--    - Method: POST
--    - URL: https://YOUR_PROJECT_REF.supabase.co/functions/v1/chat-notification
--    - Headers: Authorization: Bearer <service_role_key>
--
-- 3. Photo Critique Notification Webhook:
--    - Name: critique-notification
--    - Table: photo_critiques
--    - Events: INSERT
--    - Method: POST
--    - URL: https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-notification
--    - Headers: Authorization: Bearer <service_role_key>

-- ============================================================================
-- SR1: Link daily job reports to the session they were shot for
-- ============================================================================
-- Phase SR1 of SESSION_REPORT_NOTES_PLAN.md.
--
-- daily_job_reports.session_id (TEXT, nullable) already existed but was NULL on
-- every row because iOS never captured it. This migration makes the link real:
--   - adds session_name (readable label captured alongside session_id, D7)
--   - indexes session_id for the "notes for this session" lookups (SR2)
--   - adds the FK to sessions with ON DELETE SET NULL so deleting a session
--     leaves the historical report intact (safe alongside existing NULLs; D8 = no backfill)
--
-- sessions.id is TEXT, matching daily_job_reports.session_id. The session link
-- is OPTIONAL: off-schedule reports persist with session_id = NULL.
-- Idempotent so it can be re-applied; the live DB is the source of truth.
-- ============================================================================

ALTER TABLE public.daily_job_reports
    ADD COLUMN IF NOT EXISTS session_name TEXT;  -- Readable session label, set on capture

CREATE INDEX IF NOT EXISTS idx_daily_job_reports_session
    ON public.daily_job_reports(session_id);

ALTER TABLE public.daily_job_reports
    DROP CONSTRAINT IF EXISTS fk_daily_job_reports_session;

ALTER TABLE public.daily_job_reports
    ADD CONSTRAINT fk_daily_job_reports_session FOREIGN KEY (session_id)
        REFERENCES public.sessions(id) ON DELETE SET NULL;

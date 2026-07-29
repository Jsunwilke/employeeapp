-- Job box progression fix, part 2 of 2 (part 1 is the iOS JobBox model reading the
-- `timestamp` column instead of the nonexistent `updated_at`).
--
-- ShiftDetailView and the manager tracker subscribe to realtime postgres_changes on
-- public.job_boxes — but the table was never added to the supabase_realtime
-- publication, and a subscription to an unpublished table delivers NOTHING, silently
-- (the same failure shape as a realtime listener on users, which sits in the powersync
-- publication only). So an open shift-detail screen never heard about a new scan; only
-- a fresh open re-fetched. Verified live 2026-07-29: sessions was in the publication,
-- job_boxes was not.
--
-- Safety: realtime enforces RLS on postgres_changes, and job_boxes_org_access scopes
-- rows to the subscriber's own organization — adding the table broadcasts nothing
-- cross-tenant. PowerSync uses its own publication and is untouched.
--
-- CORRECTION (review round): this header originally claimed "the web app has no
-- job_boxes subscription (grepped)". FALSE — SessionDetailsModal.js:255 subscribes to
-- postgres_changes on job_boxes filtered by shift_uid, and had been dead since creation
-- for exactly the reason this migration fixes. Publishing the table ACTIVATES that
-- dormant web listener: the web session-details modal now re-fetches its job box when a
-- matching scan lands, which is the behavior its author intended. Recorded here rather
-- than silently corrected, because the original claim shipped as impact analysis.

DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND tablename = 'job_boxes'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.job_boxes;
  END IF;
END;
$do$;

-- REVERSIBLE WITH:
--   ALTER PUBLICATION supabase_realtime DROP TABLE public.job_boxes;

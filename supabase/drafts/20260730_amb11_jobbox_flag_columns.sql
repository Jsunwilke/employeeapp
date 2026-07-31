-- AMB.11 — Job box "Flag for Attention", built for real (operator ruling, batch-4
-- sitting 2026-07-30: "add the database fields the buttons always assumed").
--
-- The manager tracker's flag swipe/context-menu/sheet have ALWAYS written these
-- three columns, and none of them existed — PostgREST rejected the statement as a
-- unit, so no job box has ever been flagged (the FLG.1 defect class). This makes
-- the columns real. ADDITIVE ONLY: no existing column, policy or trigger changes,
-- so the web app and Captura are unaffected (they never select these columns).
--
-- Semantics (implemented in ManagerJobBoxTrackerView / JobBoxFlagRules):
--   - Flagging UPDATEs the box's latest scan row (flagged, flag_note, flagged_at).
--   - A box READS as flagged when any row of its CURRENT TRIP (the rows since the
--     last "Packed") is flagged — so ordinary later scans do not silently clear a
--     flag, and a fresh trip starts clean.
--   - Unflagging clears the columns on every flagged row of that box.
--
-- RLS: covered by the existing job_boxes_org_access ALL policy
-- (organization_id = get_user_organization_id()) — verified live 2026-07-30.
--
-- Apply via the Supabase Management API or the dashboard SQL editor.

ALTER TABLE public.job_boxes
  ADD COLUMN flagged boolean NOT NULL DEFAULT false,
  ADD COLUMN flag_note text,
  ADD COLUMN flagged_at timestamptz;

COMMENT ON COLUMN public.job_boxes.flagged IS
  'AMB.11 2026-07-30: Flag for Attention (operator-sanctioned). Set on the latest scan row of a box; a box reads as flagged when any row of its current trip is flagged.';

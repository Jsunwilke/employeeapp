-- FLG.1 — make flagging a user actually work.
--
-- WHAT WAS WRONG
-- TeamService.flagUser has always written three columns to public.users: is_flagged,
-- flag_note and flagged_by. Only is_flagged exists. PostgREST rejects the whole statement
-- on the unknown column names, so the UPDATE fails as a unit -- is_flagged is not set
-- either. Flagging a user has therefore NEVER worked, on any build, for anyone. Verified
-- live on 2026-07-27: information_schema returns is_flagged and nothing else matching flag.
--
-- The iOS app is already built to consume all three. MainEmployeeView selects
-- "is_flagged, flag_note, flagged_by, photo_url" for the signed-in user, subscribes to
-- realtime changes on that row, and renders a red ambient wash plus a banner naming who
-- flagged them -- and BOTH the banner and the inline card require flag_note to be
-- non-empty, so even a working is_flagged alone would have produced a red screen with no
-- explanation. UnflagUserView displays the note to the manager clearing the flag. The
-- consumers are real; the columns were the missing half.
--
-- BLAST RADIUS ON THE SHARED DATABASE
-- Checked rather than assumed. The web app (~/Desktop/Focal-Point-Supabase) contains ZERO
-- references to is_flagged, flag_note, flagged_by, isFlagged or flagNote across src and
-- supabase -- user flagging is an iOS-only feature. These two columns are additive and
-- nullable, so no existing read, write or decoder anywhere can change behaviour.
--
-- NOT DONE HERE, DELIBERATELY: a user can still clear their own is_flagged. That is a
-- pre-existing hole recorded as a known, accepted low-risk item in the 2026-07-12 RLS
-- remediation ("is_flagged self-edit left open"). Closing it means editing
-- prevent_privilege_self_escalation, and that trigger's condition is "not an admin",
-- while flagging is granted to anyone with users-edit (level 2) -- so the obvious edit
-- would block managers from flagging at all. Reopening that decision is not this fix's
-- job; it is named here so it is not mistaken for an oversight.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS flag_note  text,
  ADD COLUMN IF NOT EXISTS flagged_by text;

COMMENT ON COLUMN public.users.flag_note IS
  'FLG.1: why this user was flagged. Shown to the flagged user in the app banner and to a '
  'manager in UnflagUserView. Written by TeamService.flagUser alongside is_flagged.';

COMMENT ON COLUMN public.users.flagged_by IS
  'FLG.1: public.users.id (text) of whoever set the flag. Resolved to a first name for the '
  'banner. Deliberately NOT a foreign key: users.id is text and holds legacy Firebase uids '
  'as well as Supabase uuids, so a constraint would reject historical flaggers.';

-- REVERSIBLE WITH:
--   ALTER TABLE public.users DROP COLUMN IF EXISTS flag_note;
--   ALTER TABLE public.users DROP COLUMN IF EXISTS flagged_by;

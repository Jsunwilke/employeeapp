-- PSH.2 — one row per DEVICE, not one token column per person.
--
-- WHY. users.apns_token was a single column, so a person signed in on an iPhone and an
-- iPad had one slot between them: whichever device registered most recently owned it and
-- the other silently received nothing. PSH.1 recorded this as the real fix ("a
-- user_devices table keyed by token, carrying the environment; every sender fans out
-- over it") and narrowed the damage in the meantime. This migration is that fix.
--
-- NAME. public.devices already exists and is a hardware/station registry for a different
-- feature (verified live 2026-07-28) — hence user_devices, which is free.
--
-- WRITERS AND READERS, all switched in this same commit (delete-first):
--   writes  PushNotificationManager.saveAPNsTokenToSupabase   (register_push_device RPC)
--   deletes PushNotificationManager.clearAPNsTokenOnSignOut   (delete this device's row)
--   reads   send-notification, chat-notification, session-notification via
--           supabase/functions/_shared/tokens.ts (service role; RLS does not apply)
--
-- ENVIRONMENT. Same contract as the users.apns_environment column this replaces
-- (20260727_psh1_apns_environment.sql): which Apple push service minted the token,
-- resolved on-device from the embedded provisioning profile. NULL means "stored before
-- the environment was recorded" and the sender resolves it by probing production first
-- and retrying sandbox on BadDeviceToken.

CREATE TABLE IF NOT EXISTS public.user_devices (
  -- The token IS the device identity. Apple may rotate it; a rotation registers as a new
  -- row and the dead old row is reaped by the sender the first time Apple rejects it
  -- (410 Unregistered / BadDeviceToken), so the table is self-cleaning.
  token       text PRIMARY KEY,
  -- users.id is TEXT (one legacy mixed-case Firebase uid among the rows — that orphan
  -- cannot sign in, so it can never own a device row; every writable user_id here is a
  -- lowercase uuid string).
  user_id     text NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  environment text CHECK (environment IS NULL OR environment IN ('sandbox', 'production')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_devices_user_id ON public.user_devices (user_id);

-- Keep updated_at honest on upserts that do not set it, matching the table family's
-- existing convention.
DROP TRIGGER IF EXISTS trg_user_devices_updated_at ON public.user_devices;
CREATE TRIGGER trg_user_devices_updated_at
  BEFORE UPDATE ON public.user_devices
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- ACCESS. AUD.2's lesson applies to every NEW table on this project: Supabase default
-- privileges hand anon and authenticated table-level grants at creation, which is exactly
-- how the audit_log partitions became world-readable. Close it here, at creation time.
-- A device token is a per-device push credential: nobody has any business reading another
-- person's rows, and anon has no business here at all.
ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_devices FROM anon;
-- Fix-round hygiene (F9): authenticated keeps only what it uses — SELECT and DELETE,
-- both row-scoped by the policies below. INSERT/UPDATE go through the RPC (and were
-- inert anyway with no policies), TRUNCATE/REFERENCES have no business here at all.
REVOKE INSERT, UPDATE, TRUNCATE, REFERENCES, TRIGGER ON public.user_devices FROM authenticated;

-- Own-row read and delete. auth.uid() is uuid, users.id is text; every signable-in
-- user's id is the lowercase text form of their auth uuid, so the cast comparison is
-- exact. There are deliberately NO insert or update policies: registration goes through
-- the register_push_device RPC below, because a plain own-row policy cannot handle the one
-- case that matters — a device changing users.
DROP POLICY IF EXISTS user_devices_select_own ON public.user_devices;
CREATE POLICY user_devices_select_own ON public.user_devices
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid())::text);

DROP POLICY IF EXISTS user_devices_delete_own ON public.user_devices;
CREATE POLICY user_devices_delete_own ON public.user_devices
  FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid())::text);

-- REGISTRATION IS A PRIVILEGED WRITE, so it follows the flag_user worked pattern:
-- SECURITY DEFINER RPC, guards coalesce-wrapped where a helper could return NULL, row
-- effect asserted. Named register_PUSH_device because public.register_device already
-- exists for the hardware/station registry (public.devices) — discovered live at apply
-- time; a second same-named RPC with a different purpose is a trap even when named-arg
-- dispatch can technically tell them apart. The privilege being exercised: claiming a token row away from its
-- previous owner. If user A signs out uncleanly (crash, reinstall) and user B signs in on
-- the same handset, the token now belongs to B's session — but under own-row RLS, B can
-- neither update nor delete A's row, and the stale row would deliver A's notifications
-- to the device B is holding. Possession of the 64-hex APNs token IS the proof of
-- holding the device (Apple mints it to the handset, it is never shown to other users),
-- so any authenticated caller presenting a token may claim it, evicting the stale owner.
CREATE OR REPLACE FUNCTION public.register_push_device(p_token text, p_environment text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid text;
BEGIN
  v_uid := (SELECT auth.uid())::text;
  -- coalesce so a NULL uid (no JWT context) DENIES. NULL fails open inside IF NOT —
  -- the FLG.2 lesson, applied at write time rather than re-learned.
  IF coalesce(v_uid, '') = '' THEN
    RAISE EXCEPTION 'register_push_device: not authenticated';
  END IF;

  -- The caller must exist as a users row, or the FK below would produce a confusing
  -- error; and an APNs token is 64 hex bytes today — bounded loosely so an Apple format
  -- change does not break registration, but garbage is refused.
  IF p_token IS NULL OR length(p_token) < 16 OR length(p_token) > 200 THEN
    RAISE EXCEPTION 'register_push_device: token has an unexpected length';
  END IF;
  IF p_environment IS NOT NULL AND p_environment NOT IN ('sandbox', 'production') THEN
    RAISE EXCEPTION 'register_push_device: environment must be sandbox, production, or null';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_uid) THEN
    RAISE EXCEPTION 'register_push_device: no users row for this account';
  END IF;

  INSERT INTO public.user_devices (token, user_id, environment, updated_at)
  VALUES (p_token, v_uid, p_environment, now())
  ON CONFLICT (token) DO UPDATE
    SET user_id     = excluded.user_id,
        environment = excluded.environment,
        updated_at  = now();
END;
$function$;

REVOKE ALL ON FUNCTION public.register_push_device(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_push_device(text, text) TO authenticated;

-- BACKFILL before the drop: every stored token survives the move. 22 rows expected
-- (verified live 2026-07-28); environment is NULL for all of them because no device ever
-- successfully wrote users.apns_environment (the write only ran on the .signedIn auth
-- event, which a warm launch never emits — fixed in the same commit as this migration by
-- also flushing on the restored-session event).
INSERT INTO public.user_devices (token, user_id, environment)
SELECT u.apns_token, u.id, u.apns_environment
  FROM public.users u
 WHERE u.apns_token IS NOT NULL
ON CONFLICT (token) DO NOTHING;

-- DELETE-FIRST: the single-token columns die in the migration that replaces them.
-- Operator sign-off 2026-07-28 for all three drops (they are destructive DDL on the
-- shared users table):
--   apns_token / apns_environment — the path this table replaces; web app and Captura
--     have zero references (verified by grep and live read).
--   fcm_token_updated_at — orphaned Firebase-era column; its companion fcm_token never
--     existed on the live table. Nothing writes it. The only Swift reference was
--     UserProfileService's dead full-row update path (zero callers, deleted in this same
--     commit).
DROP INDEX IF EXISTS public.idx_users_apns_token;
ALTER TABLE public.users
  DROP COLUMN IF EXISTS apns_token,
  DROP COLUMN IF EXISTS apns_environment,
  DROP COLUMN IF EXISTS fcm_token_updated_at;

COMMENT ON TABLE public.user_devices IS
  'PSH.2: one row per registered iOS device. token is the APNs device token (a per-device '
  'push credential — never expose to other users); environment records which Apple push '
  'service minted it (sandbox/production, NULL = unknown legacy). Written by the iOS app '
  'for its own user only; read by the push edge functions with the service role, which '
  'fan out one send per row and reap rows Apple rejects as dead.';

-- REVERSIBLE WITH (data restore only approximate: a user''s newest device wins the column):
--   ALTER TABLE public.users ADD COLUMN apns_token text, ADD COLUMN apns_environment text
--     CHECK (apns_environment IS NULL OR apns_environment IN ('sandbox','production')),
--     ADD COLUMN fcm_token_updated_at timestamptz;
--   UPDATE public.users u SET apns_token = d.token, apns_environment = d.environment
--     FROM (SELECT DISTINCT ON (user_id) user_id, token, environment
--             FROM public.user_devices ORDER BY user_id, updated_at DESC) d
--    WHERE d.user_id = u.id;
--   DROP TABLE public.user_devices;

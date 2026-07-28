-- PSH.1 — record WHICH Apple push service minted each device token.
--
-- WHY THIS EXISTS
-- Apple runs two separate push services, sandbox and production, and a token issued by one
-- is rejected by the other. Until now the sender chose its endpoint from a single global
-- secret (APNS_PRODUCTION = true), so it treated every stored token as a production token.
-- Every push this app has ever sent was therefore rejected. Captured directly from the
-- session-notification function log on 2026-07-27, sending to a real stored token:
--
--     error: "BadDeviceToken", statusCode: 400
--
-- A global flag cannot be corrected, only moved: flipping it to false would fix development
-- installs and break TestFlight/App Store installs, because there is one token column per
-- person. The environment has to travel WITH the token, which is what this column does.
--
-- BLAST RADIUS ON THE SHARED DATABASE
-- Purely additive: one nullable column on public.users. Nothing is dropped, nothing is
-- renamed, no policy changes, no default backfill that could contradict reality.
--   * The web app (~/Desktop/Focal-Point-Supabase) reads users with explicit column lists and
--     with select('*'); an unexpected extra key is ignored by JavaScript either way.
--   * The iOS app decodes users into explicit Codable structs, which ignore undeclared keys.
--   * Captura does not read a push token.
-- Reversible with: ALTER TABLE public.users DROP COLUMN apns_environment;

-- Also carried forward from the deleted migration: the extensions. pg_net in particular is
-- a hard dependency of the notification triggers (net.http_post). Both are already present
-- on this database via the web repo's cron migrations, so these are no-ops in practice —
-- restated so the migration history does not depend on that coincidence.
CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Carried forward from 20241228_apns_and_notifications.sql, which is DELETED in this same
-- commit. That file's three cron.schedule calls all still contained the literal placeholder
-- YOUR_PROJECT_REF and were verified never to have been registered (cron.job holds none of
-- clock-in-reminder, clock-out-reminder or daily-report-reminder), so the file could never
-- have run as written. Its one real, applied statement was this column, which does exist in
-- production — so it is restated here rather than lost from the migration history.
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS apns_token TEXT;

CREATE INDEX IF NOT EXISTS idx_users_apns_token
  ON public.users(apns_token) WHERE apns_token IS NOT NULL;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS apns_environment TEXT;

COMMENT ON COLUMN public.users.apns_environment IS
  'Which Apple push service minted apns_token: sandbox (development build) or production '
  '(App Store / TestFlight). Written by the iOS app alongside apns_token. The sender MUST '
  'route on this per token — a sandbox token sent to api.push.apple.com returns 400 '
  'BadDeviceToken. NULL means the token predates PSH.1 and its environment is unknown.';

-- Only ever the two values the app writes, or NULL for tokens stored before PSH.1.
ALTER TABLE public.users
  DROP CONSTRAINT IF EXISTS users_apns_environment_check;

ALTER TABLE public.users
  ADD CONSTRAINT users_apns_environment_check
  CHECK (apns_environment IS NULL OR apns_environment IN ('sandbox', 'production'));

-- DELIBERATELY NOT BACKFILLED.
-- The 22 tokens already stored carry no record of which build produced them, and guessing
-- would be worse than admitting ignorance: a wrong guess sends to the wrong endpoint and
-- fails exactly as before, but now with a value that looks authoritative. They stay NULL
-- and the sender treats NULL as "try both", which self-heals on each device's next launch
-- when the app writes the real value.

-- NOT DROPPED HERE, deliberately: users.fcm_token_updated_at is an orphan — the fcm_token
-- column it describes does not exist on this database (verified 2026-07-27; it was dropped
-- and the timestamp left behind). Removing it is a DESTRUCTIVE change on a table shared with
-- the web app and Captura, and UserProfileService's full-row update path encodes that field,
-- so a drop could start failing profile saves. It is recorded as cleanup for its own change
-- with its own impact trace and the operator's sign-off, not smuggled into a push fix.

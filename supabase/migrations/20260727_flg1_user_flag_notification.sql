-- FLG.1 — tell a flagged person they have been flagged.
--
-- DEPENDS ON 20260727_flg1_user_flag_columns.sql. APPLY THAT FIRST, AND FIRE THIS ONCE
-- BEFORE BELIEVING IT. plpgsql does NOT validate field references until the trigger
-- actually RUNS, so against the old schema this creates cleanly and then raises on the
-- first flag, rolling back the very UPDATE it is attached to. That is not hypothetical:
-- PSH.1 created this trigger against these exact missing columns, it installed without
-- complaint, and it had to be dropped live once testing showed it would have broken every
-- is_flagged update on a table shared with the web app and Captura. A trigger that creates
-- successfully is not a trigger that works.
--
-- PROVENANCE. The operator asked for PSH.1's version to be recovered rather than rewritten.
-- It could not be: PSH.1 applied it live and never committed the file — d61d475's own
-- message says "The migration is deleted rather than left to be applied by someone else",
-- and searching every commit in both repos for trg_user_flagged_notification and
-- notify_user_flagged returns no migration at any path. What WAS recoverable is the payload
-- PSH.1 intended, from the sendFlagNotification function deleted out of FlagUserView.swift
-- in that same commit (git show d61d475^:"Iconik Employee/Manager Features/FlagUserView.swift").
-- The title, body, type and data below are that payload exactly. The structure is
-- notify_time_off_change, which is the pattern the roadmap names for this job.
--
-- WHY THE NOTE IS IN THE BODY. It is a manager's written criticism, and it lands on a lock
-- screen. That is a real privacy question and it is recorded as an open PSH.2 item covering
-- time-off reasons, which are on the lock screen today for the same reason. It is answered
-- here by MATCHING the app's existing posture rather than quietly inventing a stricter one
-- for this single notification: PSH.1's payload put the note in the body, and the roadmap's
-- position on the equivalent time-off case is that a notification with no substance is
-- useless. If that posture changes, it should change for both at once, not here alone.
--
-- THREE CORRECTIONS TO AN EARLIER DRAFT OF THIS HEADER, each caught by an adversarial audit
-- and each verified against the live database rather than argued:
--   1. It claimed the payload matched PSH.1's "exactly". It matches on title, body, type and
--      data, but PSH.1 sent userIds: [targetId.lowercased()] and this sends NEW.id unfolded.
--      The difference is immaterial in practice -- send-notification lowercases the ids
--      itself (functions/send-notification/index.ts:128) -- but the claim was overstated.
--      Consequence worth knowing: for the one legacy mixed-case users.id, that lowercasing
--      means the recipient lookup misses. That is pre-existing behaviour of the sender and
--      affects every notification type, not just this one.
--   2. It claimed MainEmployeeView "subscribes to realtime changes on that row". public.users
--      is in the powersync publication ONLY, not supabase_realtime, so that subscription
--      cannot deliver. The flagged person sees the banner on the next load, not instantly.
--   3. It claimed flagging is granted to anyone with users-edit (level 2). That is the CLIENT
--      gate. The RLS policy users_update_org is
--        (id = auth.uid()::text OR is_admin_of_org(organization_id))
--      so a non-admin manager can only ever update their OWN row -- flagging somebody else
--      silently matches zero rows. TeamService.flagUser now throws on a zero-row update so
--      this surfaces as an error instead of a false success, but the underlying mismatch
--      between the in-app permission and the database policy is NOT resolved here and is
--      recorded in the FLG.1 closeout as needing an operator decision.

CREATE OR REPLACE FUNCTION public.notify_user_flagged()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_service_key text;
  v_body        text;
BEGIN
  SELECT decrypted_secret INTO v_service_key
    FROM vault.decrypted_secrets
   WHERE name = 'service_role_key'
   LIMIT 1;

  IF v_service_key IS NULL THEN
    -- Never block the flag write over a missing secret. Same posture as
    -- notify_time_off_change and notify_session_change: the row must save even if the
    -- push cannot be sent.
    -- WARNING, not NOTICE: log_min_messages defaults to warning, so a NOTICE here would be
    -- invisible -- and a renamed or absent vault secret is the single most likely way this
    -- silently stops working.
    RAISE WARNING 'notify_user_flagged: service_role_key secret missing; skipping push';
    RETURN NEW;
  END IF;

  -- No recipient, no request. users.id is a text column and is the key send-notification
  -- expects. It is NOT lowercased here: 39 of 40 rows are lowercase uuids but one is a
  -- 28-character mixed-case legacy Firebase uid belonging to an active admin, and folding
  -- case would address the notification to a user that does not exist.
  IF NEW.id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Whoever pressed the button does not need to be told they pressed it. The UI forbids
  -- flagging yourself; the table does not.
  IF NEW.flagged_by IS NOT DISTINCT FROM NEW.id THEN
    RETURN NEW;
  END IF;

  -- send-notification rejects a null or empty body with a 400, and net.http_post discards
  -- the response, so an empty note would mean silence with no trace anywhere. The UI
  -- already requires a non-empty note; this is the backstop for every other writer.
  --
  -- The note is also CAPPED. flag_note is unbounded text and the whole APNs payload must fit
  -- in 4KB; past that Apple rejects it, and because net.http_post discards the response the
  -- rejection would be invisible. 300 characters is far more than a lock-screen banner shows.
  v_body := nullif(btrim(coalesce(NEW.flag_note, '')), '');

  IF v_body IS NULL THEN
    RAISE WARNING 'notify_user_flagged: user % flagged with an empty note; no push sent', NEW.id;
    RETURN NEW;
  END IF;

  IF length(v_body) > 300 THEN
    v_body := left(v_body, 297) || '...';
  END IF;

  PERFORM net.http_post(
    url := 'https://nofegnmrgnanpznavlqy.supabase.co/functions/v1/send-notification',
    headers := jsonb_build_object(
      'Content-type',  'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := jsonb_build_object(
      -- Field name must match the edge function exactly. PSH.1 found this call sending
      -- `user_ids` where the function reads `userIds`, which produced an empty recipient
      -- list and a "sent 0" the caller reported as success.
      'userIds', to_jsonb(ARRAY[NEW.id]),
      'title',   'You''ve Been Flagged',
      'body',    v_body,
      -- Must match PushNotificationManager.NotificationType.flag exactly. PSH.1 found this
      -- sending 'flag_notification', which the app's handler does not know, so even a
      -- delivered payload routed to .unknown.
      'type',    'flag',
      'data',    jsonb_build_object(
                   'flaggedBy', NEW.flagged_by,
                   'note',      v_body
                 )
    ),
    timeout_milliseconds := 5000
  );

  RETURN NEW;

EXCEPTION
  -- THE HEADER PROMISES THIS TRIGGER NEVER BLOCKS THE FLAG WRITE. Without this handler that
  -- promise was only half true: the NULL-secret case was handled, but the vault SELECT itself
  -- raising (extension absent or unreadable) or net.http_post raising (pg_net dropped or
  -- mid-upgrade) would propagate into the caller's transaction and ROLL BACK the UPDATE on a
  -- table shared with the web app and Captura. That is precisely the failure mode PSH.1 had
  -- to drop this trigger for, arriving by a different route. A notification is never worth
  -- losing the write it describes.
  --
  -- HONEST LIMIT, do not read "never" too literally: plpgsql's OTHERS matches every error
  -- class EXCEPT query_canceled and assert_failure. The `authenticated` role carries an 8s
  -- statement_timeout, so a timeout landing while control is inside this trigger still
  -- propagates and still rolls the UPDATE back. That window is small -- net.http_post only
  -- enqueues a row, it does not wait on the network -- but it is not zero, and claiming
  -- otherwise would be the same kind of overstatement this file already had to correct.
  WHEN OTHERS THEN
    RAISE WARNING 'notify_user_flagged: push failed for user % (%): %', NEW.id, SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$function$;

-- Delete-first: drop any earlier definition before creating, so a re-run cannot leave two
-- triggers on the table firing two notifications for one flag.
DROP TRIGGER IF EXISTS trg_user_flagged_notification ON public.users;

-- UPDATE OF is_flagged plus the WHEN clause means the function does not execute at all for
-- the ordinary writes that hit this shared, hot table -- profile edits, APNs token writes,
-- role changes. Verified live rather than assumed: an UPDATE touching only first_name
-- queued zero http requests.
--
-- The WHEN clause covers TWO cases, not one. The obvious case is a genuine transition into
-- flagged. The second is a RE-FLAG: FlagUserView does not exclude already-flagged people
-- from its picker, so a manager can flag the same person again with a new note. Guarding on
-- the transition alone silently sent nothing for that, while still telling the manager it had
-- worked, and the person's banner text would change with no notification. Testing
-- NEW.flag_note IS DISTINCT FROM OLD.flag_note covers it. What neither clause matches is an
-- unrelated edit to an already-flagged row, which is the case that must never re-notify --
-- also verified live: touching a flagged row without changing the note queued nothing.
-- Precisely: a changed note is covered; a re-flag with an IDENTICAL note is not, and sends
-- nothing. That is deliberate (there is no new information to deliver) but it is a limit,
-- not full coverage.
--
-- HOW THE ABOVE WAS VERIFIED, stated exactly so nobody over-reads it. Each case was run
-- against a real row inside a transaction that was then ROLLED BACK, counting rows in
-- net.http_request_queue: ordinary profile write 0, genuine flag 1, re-touch without a note
-- change still 1, re-flag with a new note 2, oversized note 3 with the body capped to 300 and
-- the title read back as "You've Been Flagged". A deliberately raising body was also
-- installed and the flag write still survived, proving the EXCEPTION handler. That proves the
-- plpgsql field references RESOLVE AT RUN TIME -- the exact thing that killed PSH.1's version
-- -- and that the payload is well formed. It does NOT prove delivery: because the transaction
-- rolled back, pg_net never actually sent the requests. End-to-end delivery to a device is
-- the operator's smoke test.
CREATE TRIGGER trg_user_flagged_notification
  AFTER UPDATE OF is_flagged ON public.users
  FOR EACH ROW
  WHEN (
    NEW.is_flagged IS TRUE
    AND (
      OLD.is_flagged IS DISTINCT FROM TRUE
      OR NEW.flag_note IS DISTINCT FROM OLD.flag_note
    )
  )
  EXECUTE FUNCTION public.notify_user_flagged();

COMMENT ON FUNCTION public.notify_user_flagged() IS
  'FLG.1: pushes a notification to a user when they are flagged, via the send-notification '
  'edge function. Fires on a false-to-true transition of is_flagged AND on a changed '
  'flag_note while already flagged (a re-flag); a re-flag with an identical note sends '
  'nothing. Payload follows the sendFlagNotification call PSH.1 deleted from FlagUserView, '
  'except that the body is capped at 300 characters. Never blocks the write: a missing vault '
  'secret, an empty note, or ANY exception in the body returns quietly.';

-- REVERSIBLE WITH:
--   DROP TRIGGER IF EXISTS trg_user_flagged_notification ON public.users;
--   DROP FUNCTION IF EXISTS public.notify_user_flagged();

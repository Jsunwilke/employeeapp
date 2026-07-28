-- PSH.1 — push notifications for time off, in the database so no client can forget.
--
-- WHY A TRIGGER AND NOT A CLIENT CALL
-- Time off is decided from BOTH the iOS app and the web app. Ten notification types were
-- already wired up in the iOS handler and in a sender, with nothing in between them,
-- because every client was expected to remember to fire one and none of them did. The one
-- notification path in this system that works end to end -- trg_session_notification on
-- public.sessions -- is the one that lives here. This follows that shape deliberately.
--
-- WHAT IT SENDS
--   1. SUBMITTED  -> everyone who can action it (timeOffApprovals level >= 2, or an admin)
--                    in the requester's organization. This is the operator's original ask:
--                    "I denied it on the iPhone. I should always get a push for those."
--   2. DECIDED    -> the requester, when status leaves 'pending'/'underReview' for
--                    approved / denied / partially_approved.
--
-- The requester is never notified of their own submission, and whoever made a decision is
-- never notified of their own decision.
--
-- STATUS VOCABULARY, AND WHY IT IS SPELLED BOTH WAYS
-- The two clients disagree: iOS writes camelCase 'underReview' while the web only ever
-- matches snake_case 'under_review' (recorded in AUDIT_ROADMAP under TOF.1). This trigger
-- accepts BOTH spellings rather than picking a side, because picking a side here would
-- silently drop every request created by the other client. Reconciling the vocabulary is
-- TOF.1's job; this migration must not depend on that being done first.

CREATE OR REPLACE FUNCTION public.notify_time_off_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_service_key   text;
  v_recipients    text[];
  v_title         text;
  v_body          text;
  v_type          text;
  v_actor         text;
  v_dates         text;
  v_old_status    text;
  v_new_status    text;
BEGIN
  SELECT decrypted_secret INTO v_service_key
    FROM vault.decrypted_secrets
   WHERE name = 'service_role_key'
   LIMIT 1;

  IF v_service_key IS NULL THEN
    -- Never block a time-off write over a missing secret. Same posture as
    -- notify_session_change: the row must save even if the push cannot be sent.
    RAISE NOTICE 'notify_time_off_change: service_role_key secret missing; skipping push';
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Normalise the status hard: lowercase, trimmed, and underscores removed. The two
  -- clients genuinely disagree about spelling — iOS writes camelCase 'underReview' while
  -- the web matches snake_case 'under_review' — so comparing raw strings silently drops
  -- whichever client loses. Folding to a single form means 'partially_approved',
  -- 'partiallyApproved' and 'Partially Approved' are all recognised. The canonical type
  -- strings sent to the device are written out explicitly below rather than derived from
  -- the status, so normalising here can never invent a type the app cannot route.
  v_old_status := replace(replace(lower(btrim(coalesce(OLD.status, ''))), '_', ''), ' ', '');
  v_new_status := replace(replace(lower(btrim(coalesce(NEW.status, ''))), '_', ''), ' ', '');

  -- A readable date range: "Aug 3" for one day, "Aug 3 to Aug 7" for several.
  -- start_date and end_date are both NULLABLE. If either is missing, to_char returns NULL,
  -- which would make the whole message body NULL — and the sender rejects a null body with
  -- a 400 that net.http_post throws away, so the person would simply never be told. Fall
  -- back to wording that is vague but real.
  v_dates := CASE
    WHEN NEW.start_date IS NULL AND NEW.end_date IS NULL
      THEN 'your requested dates'
    WHEN NEW.start_date IS NULL OR NEW.end_date IS NULL
      THEN to_char(coalesce(NEW.start_date, NEW.end_date), 'Mon FMDD')
    WHEN NEW.start_date::date = NEW.end_date::date
      THEN to_char(NEW.start_date, 'Mon FMDD')
    ELSE to_char(NEW.start_date, 'Mon FMDD') || ' to ' || to_char(NEW.end_date, 'Mon FMDD')
  END;

  IF TG_OP = 'INSERT' THEN
    -- Only a request that is actually waiting on somebody is worth interrupting them for.
    IF v_new_status NOT IN ('pending', 'underreview') THEN
      RETURN NEW;
    END IF;

    SELECT array_agg(u.id) INTO v_recipients
      FROM public.users u
     WHERE u.organization_id = NEW.organization_id
       AND u.id IS DISTINCT FROM NEW.photographer_id      -- never notify your own request
       AND (
             u.role = 'admin'
             OR EXISTS (
                  SELECT 1 FROM public.role_permissions rp
                   WHERE rp.role_id = u.role_id
                     AND rp.area_code = 'timeOffApprovals'
                     AND rp.level >= 2
                )
           );

    v_type  := 'time_off_submitted';
    v_title := 'Time Off Request';
    v_body  := coalesce(NEW.photographer_name, 'Someone')
               || ' requested ' || v_dates
               || CASE WHEN NEW.reason IS NOT NULL AND NEW.reason <> ''
                       THEN ' (' || NEW.reason || ')' ELSE '' END;

  ELSE
    -- UPDATE. Only a genuine transition INTO a decided state counts. Guarding on the
    -- transition rather than the new value alone is what stops an unrelated edit to an
    -- already-approved row from re-notifying the requester every time it is touched.
    IF v_old_status = v_new_status THEN
      RETURN NEW;
    END IF;

    IF v_new_status NOT IN ('approved', 'denied', 'partiallyapproved') THEN
      RETURN NEW;
    END IF;

    -- Whoever pressed the button does not need to be told they pressed it.
    v_actor := CASE v_new_status
                 WHEN 'approved' THEN NEW.approved_by
                 WHEN 'denied'   THEN NEW.denied_by
                 ELSE NEW.approved_by
               END;

    IF NEW.photographer_id IS NULL OR NEW.photographer_id IS NOT DISTINCT FROM v_actor THEN
      RETURN NEW;
    END IF;

    v_recipients := ARRAY[NEW.photographer_id];

    -- Type strings are written out literally, NOT derived from the status. They must match
    -- PushNotificationManager.NotificationType exactly or the banner shows and the tap does
    -- nothing. Deriving them would have produced 'time_off_partiallyapproved' from the
    -- normalised status above, which the app does not know.
    IF v_new_status = 'approved' THEN
      v_type  := 'time_off_approved';
      v_title := 'Time Off Approved';
      v_body  := 'Your time off for ' || v_dates || ' was approved.';
    ELSIF v_new_status = 'denied' THEN
      v_type  := 'time_off_denied';
      v_title := 'Time Off Denied';
      v_body  := 'Your time off for ' || v_dates || ' was denied.'
                 || CASE WHEN NEW.denial_reason IS NOT NULL AND NEW.denial_reason <> ''
                         THEN ' ' || NEW.denial_reason ELSE '' END;
    ELSE
      v_type  := 'time_off_partially_approved';
      v_title := 'Time Off Partially Approved';
      v_body  := 'Some of your time off for ' || v_dates || ' was approved. Open the app for details.';
    END IF;
  END IF;

  -- Final backstop: the sender rejects a null/empty title or body with a 400, and
  -- net.http_post discards the response, so a NULL here would mean silence with no trace.
  IF v_title IS NULL OR v_body IS NULL OR v_title = '' OR v_body = '' THEN
    RAISE WARNING 'notify_time_off_change: refusing to send an empty notification for request %', NEW.id;
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF v_recipients IS NULL OR array_length(v_recipients, 1) IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  PERFORM net.http_post(
    url := 'https://nofegnmrgnanpznavlqy.supabase.co/functions/v1/send-notification',
    headers := jsonb_build_object(
      'Content-type',  'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := jsonb_build_object(
      'userIds', to_jsonb(v_recipients),   -- field name must match the function exactly
      'title',   v_title,
      'body',    v_body,
      'type',    v_type,
      'data',    jsonb_build_object(
                   'requestId',   NEW.id,
                   'status',      NEW.status,
                   'startDate',   NEW.start_date,
                   'endDate',     NEW.end_date
                 )
    ),
    timeout_milliseconds := 5000
  );

  RETURN COALESCE(NEW, OLD);
END;
$function$;

-- Delete-first: drop any earlier definition before creating, so a re-run cannot leave two
-- triggers on the table firing two notifications for one decision.
DROP TRIGGER IF EXISTS trg_time_off_notification ON public.time_off_requests;

CREATE TRIGGER trg_time_off_notification
  AFTER INSERT OR UPDATE ON public.time_off_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_time_off_change();

COMMENT ON FUNCTION public.notify_time_off_change() IS
  'PSH.1: pushes a notification when a time-off request is submitted (to approvers) or '
  'decided (to the requester), via the send-notification edge function. Accepts both the '
  'camelCase and snake_case spellings of under-review because the two clients disagree. '
  'Never blocks the write: a missing vault secret or an empty recipient list returns quietly.';

-- REVERSIBLE WITH:
--   DROP TRIGGER IF EXISTS trg_time_off_notification ON public.time_off_requests;
--   DROP FUNCTION IF EXISTS public.notify_time_off_change();

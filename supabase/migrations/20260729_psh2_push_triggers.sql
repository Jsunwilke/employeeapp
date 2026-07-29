-- PSH.2 — the six push types that could never fire, wired in the database.
--
-- PSH.1's architecture decision, applied: the trigger for a notification lives in the
-- DATABASE, because the one path that ever worked was built that way and because a
-- client-side call is a thing every client must remember and none of them did. Chat is
-- written by BOTH the iOS app and the web app into the same messages table, so one
-- trigger here covers both with no client changes.
--
-- Structure: one internal transport helper (psh2_post_function / psh2_send_push), and one
-- small trigger function per event. The helper exists because FLG.2's audits kept finding
-- the same defect class — a fix applied to one copy of a repeated skeleton while a second
-- copy kept the bug. Seven hand-copied vault-fetch-and-post skeletons is that hazard by
-- construction; one shared transport is not. Every trigger function still owns its own
-- WHEN OTHERS handler, because "a notification is never worth losing the write it
-- describes" (the FLG.1 rule) must hold per-write.

-- ============================================================================
-- Transport helpers (internal — not callable by clients)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.psh2_post_function(p_fn text, p_body jsonb)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_service_key text;
BEGIN
  SELECT decrypted_secret INTO v_service_key
    FROM vault.decrypted_secrets
   WHERE name = 'service_role_key'
   LIMIT 1;

  IF v_service_key IS NULL THEN
    -- WARNING, not NOTICE: log_min_messages defaults to warning, so a NOTICE would be
    -- invisible — and a renamed or absent vault secret is the single most likely way this
    -- silently stops working (the FLG.1 lesson).
    RAISE WARNING 'psh2_post_function: service_role_key secret missing; % not called', p_fn;
    RETURN false;
  END IF;

  PERFORM net.http_post(
    url := 'https://nofegnmrgnanpznavlqy.supabase.co/functions/v1/' || p_fn,
    headers := jsonb_build_object(
      'Content-type',  'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := p_body,
    timeout_milliseconds := 5000
  );
  RETURN true;
END;
$function$;

-- Builds the send-notification body. Field names must match the edge function exactly
-- (userIds, not user_ids — the PSH.1 bug). Refuses empty input quietly: the sender 400s
-- on an empty title/body and net.http_post discards the response, so posting garbage
-- would be silence with no trace.
CREATE OR REPLACE FUNCTION public.psh2_send_push(
  p_user_ids text[], p_title text, p_body text, p_type text, p_data jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_body text;
BEGIN
  IF p_user_ids IS NULL OR array_length(p_user_ids, 1) IS NULL THEN
    RETURN false;
  END IF;
  IF coalesce(btrim(p_title), '') = '' OR coalesce(btrim(p_body), '') = '' THEN
    RAISE WARNING 'psh2_send_push: refusing an empty title/body for type %', p_type;
    RETURN false;
  END IF;

  -- The whole APNs payload must fit in 4KB; past that Apple rejects it invisibly
  -- (net.http_post discards the response). 300 characters is far more than a banner shows.
  v_body := p_body;
  IF length(v_body) > 300 THEN
    v_body := left(v_body, 297) || '...';
  END IF;

  RETURN public.psh2_post_function('send-notification', jsonb_build_object(
    'userIds', to_jsonb(p_user_ids),
    'title',   p_title,
    'body',    v_body,
    'type',    p_type,
    'data',    coalesce(p_data, '{}'::jsonb)
  ));
END;
$function$;

REVOKE ALL ON FUNCTION public.psh2_post_function(text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.psh2_send_push(text[], text, text, text, jsonb) FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- 1. Chat messages — AFTER INSERT ON public.messages
-- ============================================================================
-- Recipient resolution (conversation participants, sender name) lives in the
-- chat-notification edge function, which takes the standard webhook shape; the trigger
-- stays thin, the same split the working sessions path uses. System rows (the web app
-- writes type = 'system' for add/remove/leave events) are excluded in the WHEN clause so
-- this function does not execute at all for them.

CREATE OR REPLACE FUNCTION public.notify_chat_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.psh2_post_function('chat-notification', jsonb_build_object(
    'type',       'INSERT',
    'table',      'messages',
    'schema',     'public',
    'record',     to_jsonb(NEW),
    'old_record', NULL
  ));
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_chat_message: push failed for message % (%): %', NEW.id, SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_chat_message_notification ON public.messages;
CREATE TRIGGER trg_chat_message_notification
  AFTER INSERT ON public.messages
  FOR EACH ROW
  WHEN (coalesce(NEW.type, '') <> 'system')
  EXECUTE FUNCTION public.notify_chat_message();

-- ============================================================================
-- 2. Photo critiques — published critique notifies its target photographer
-- ============================================================================
-- The web app inserts critiques with status 'published' directly (verified in
-- photoCritiqueService.js); the UPDATE trigger covers any future draft-then-publish flow
-- so a status rework does not silently kill the push. target_photographer_id is a text id
-- from the shared users table and is NOT lowercased (the FLG.1 rule: one legacy
-- mixed-case id exists; fold case and the lookup misses).

CREATE OR REPLACE FUNCTION public.notify_photo_critique()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_submitter text;
  v_actor     text;
BEGIN
  IF NEW.target_photographer_id IS NULL THEN
    RETURN NEW;
  END IF;
  -- Whoever submitted it does not need to be told they submitted it.
  IF NEW.target_photographer_id IS NOT DISTINCT FROM NEW.submitter_id THEN
    RETURN NEW;
  END IF;

  -- GUARDS (PSH.2 fix round, F2). photo_critiques' RLS is WITH CHECK (true) for anon AND
  -- authenticated — a pre-existing hole, recorded under SEC.* — which made this trigger
  -- an arbitrary-push primitive: one unauthenticated INSERT naming any user id would
  -- deliver attacker text to that person's lock screen, cross-tenant. The trigger cannot
  -- fix the table's RLS (that is SEC.* work with its own impact trace), but it CAN refuse
  -- to amplify it:
  --   1. no authenticated actor, no push (kills the anon-key path outright);
  --   2. the actor must belong to the row's organization;
  --   3. the target must belong to the row's organization (kills cross-tenant).
  -- In-org content is still author-controlled — that is what the critique feature IS.
  v_actor := (SELECT auth.uid())::text;
  IF v_actor IS NULL THEN
    RAISE WARNING 'notify_photo_critique: no authenticated actor for critique %; not pushing', NEW.id;
    RETURN NEW;
  END IF;
  IF NEW.organization_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.users u
                     WHERE u.id = v_actor AND u.organization_id = NEW.organization_id)
     OR NOT EXISTS (SELECT 1 FROM public.users u
                     WHERE u.id = NEW.target_photographer_id
                       AND u.organization_id = NEW.organization_id) THEN
    RAISE WARNING 'notify_photo_critique: org mismatch for critique %; not pushing', NEW.id;
    RETURN NEW;
  END IF;

  v_submitter := coalesce(nullif(btrim(NEW.submitter_name), ''), 'Your manager');

  PERFORM public.psh2_send_push(
    ARRAY[NEW.target_photographer_id],
    'New Photo Critique',
    CASE WHEN NEW.example_type = 'example'
         THEN v_submitter || ' shared an example photo with you.'
         ELSE v_submitter || ' left feedback on your photos.'
    END,
    'photo_critique',
    jsonb_build_object(
      -- critiqueId is the one consumed key (tap routing → TabBarManager.pendingCritiqueId
      -- → the PhotoCritiqueListView consumer). submitterName/exampleType were dropped in
      -- the review round: no client reads them, and the submitter is already in the body.
      'critiqueId', NEW.id
    )
  );
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_photo_critique: push failed for critique % (%): %', NEW.id, SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_photo_critique_notification_ins ON public.photo_critiques;
CREATE TRIGGER trg_photo_critique_notification_ins
  AFTER INSERT ON public.photo_critiques
  FOR EACH ROW
  WHEN (NEW.status = 'published')
  EXECUTE FUNCTION public.notify_photo_critique();

DROP TRIGGER IF EXISTS trg_photo_critique_notification_upd ON public.photo_critiques;
CREATE TRIGGER trg_photo_critique_notification_upd
  AFTER UPDATE OF status ON public.photo_critiques
  FOR EACH ROW
  WHEN (NEW.status = 'published' AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.notify_photo_critique();

-- ============================================================================
-- 3. Job boxes — a scan notifies the shift's crew
-- ============================================================================
-- Every scan INSERTs a fresh job_boxes row (DatabaseManager+NFC.saveJobBoxRecord), so
-- INSERT is the event. Recipients: the crew of the shift the box belongs to
-- (session_days.photographers for shift_uid), excluding whoever scanned it. A scan with
-- no shift attached notifies nobody — there is no crew to tell.

CREATE OR REPLACE FUNCTION public.notify_job_box()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_crew    text[];
  v_school  text;
  v_scanner text;
BEGIN
  IF NEW.shift_uid IS NULL OR btrim(NEW.shift_uid) = '' THEN
    RETURN NEW;
  END IF;

  -- STALENESS GUARD FIRST (review round: it depends only on NEW, and it exists for the
  -- offline-outbox replay case — a burst of N stale scans must cost N timestamp
  -- comparisons, not N runs of the org probe and crew aggregation below).
  IF NEW.timestamp IS NOT NULL AND NEW.timestamp < now() - interval '2 hours' THEN
    RAISE WARNING 'notify_job_box: box % scan is a stale replay (%); recorded, not pushed', NEW.id, NEW.timestamp;
    RETURN NEW;
  END IF;

  -- GUARD (PSH.2 fix round, F3): shift_uid is unconstrained text on a client-writable
  -- row, and this function reads session_days as SECURITY DEFINER — without the org
  -- check, a row naming ANOTHER tenant's session id would push that tenant's crew.
  -- job_boxes' RLS pins organization_id to the inserter's own org, so requiring the
  -- shift to belong to the row's org confines the push to the inserter's tenant.
  IF NEW.organization_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.sessions s
        WHERE s.id = NEW.shift_uid AND s.organization_id = NEW.organization_id
     ) THEN
    RAISE WARNING 'notify_job_box: shift % not in org % for box %; not pushing',
      NEW.shift_uid, NEW.organization_id, NEW.id;
    RETURN NEW;
  END IF;

  SELECT array_agg(DISTINCT p.id) INTO v_crew
    FROM public.session_days sd
    CROSS JOIN LATERAL (
      SELECT elem->>'id' AS id
        FROM jsonb_array_elements(coalesce(sd.photographers, '[]'::jsonb)) elem
    ) p
   WHERE sd.session_id = NEW.shift_uid
     AND coalesce(p.id, '') <> ''
     -- lower() on BOTH sides (review round): 6 users' time_entries and 341 report rows
     -- verifiably carry uppercase ids, so a case-sensitive exclusion would push the
     -- scanner their own scan. This is a comparison between two id VALUES, not a lookup
     -- of users.id — the FLG mixed-case exception governs lookups, not equality folds.
     AND lower(p.id) IS DISTINCT FROM lower(NEW.user_id);   -- the scanner knows; they did it

  IF v_crew IS NULL THEN
    RETURN NEW;
  END IF;

  v_school  := coalesce(nullif(btrim(NEW.school), ''), 'your session');
  v_scanner := coalesce(nullif(btrim(NEW.photographer), ''), 'Someone');

  PERFORM public.psh2_send_push(
    v_crew,
    'Job Box Update',
    v_scanner || ' marked the ' || v_school || ' job box: ' || coalesce(NEW.status, 'updated'),
    'jobbox',
    jsonb_build_object(
      -- Exactly the consumed keys, nothing speculative (review round): the ShiftDetailView
      -- observer requires shiftUid; JobBoxService.processJobBoxNotification reads status
      -- and photographer; the tap routing feeds shiftUid to TabBarManager.pendingSessionId.
      -- An earlier version also sent scannedBy/schoolName/boxNumber, which no client
      -- reads — unconsumed contract keys are the name-drift class this phase exists to kill.
      'status',       coalesce(NEW.status, ''),
      'photographer', v_scanner,
      'shiftUid',     NEW.shift_uid
    )
  );
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_job_box: push failed for job box % (%): %', NEW.id, SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_job_box_notification ON public.job_boxes;
CREATE TRIGGER trg_job_box_notification
  AFTER INSERT ON public.job_boxes
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_job_box();

-- ============================================================================
-- 4. Sessions — repair a path that has been silently dead since the MD7 crew move
-- ============================================================================
-- trg_session_notification (web repo, 20260714_sec1_session_notification_vault.sql) posts
-- the sessions row to the session-notification edge function, which resolves recipients
-- from record.photographers — a column the MD7 arc REMOVED from sessions (crew lives on
-- session_days now; verified live: sessions has no photographers column, and the
-- photographer_ids array is empty on all 991 published rows). So every fire since the
-- move has exited "No assigned employees": session pushes deliver nothing today. This
-- section supersedes the web repo's definition. Three changes:
--
--   a. The single any-write trigger becomes targeted triggers. The old shape fired on
--      EVERY sessions UPDATE — including the job-box scan path, which writes
--      has_job_box_assigned on sessions — and once crew resolution works again that
--      would push "Session Updated" spam for every incidental write. UPDATE now fires
--      only for is_published / school_name transitions. Date, time and crew changes live
--      on session_days (the granular day-move notification is recorded follow-up work,
--      not silently claimed here).
--   b. DELETE becomes a BEFORE trigger that captures the crew INTO the payload
--      (crew_ids), because the session_days rows cascade away with the parent and an
--      AFTER trigger finds nobody to tell.
--   c. No INSERT trigger at all. Both clients insert the sessions row FIRST and the day
--      rows (with the crew) in a later statement, so at INSERT time the crew is
--      unresolvable — the old INSERT path never once had a recipient. "You've been
--      assigned" is sent by the session_days trigger below, which fires when the crew
--      actually lands.

CREATE OR REPLACE FUNCTION public.notify_session_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_record jsonb;
  v_crew   jsonb;
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- BEFORE DELETE: the day rows still exist; capture the crew for the edge function.
    SELECT jsonb_agg(DISTINCT p.id) INTO v_crew
      FROM public.session_days sd
      CROSS JOIN LATERAL (
        SELECT elem->>'id' AS id
          FROM jsonb_array_elements(coalesce(sd.photographers, '[]'::jsonb)) elem
      ) p
     WHERE sd.session_id = OLD.id
       AND coalesce(p.id, '') <> '';

    v_record := to_jsonb(OLD) || jsonb_build_object('crew_ids', coalesce(v_crew, '[]'::jsonb));

    PERFORM public.psh2_post_function('session-notification', jsonb_build_object(
      'type',       'DELETE',
      'table',      'sessions',
      'schema',     'public',
      'record',     NULL,
      'old_record', v_record
    ));
    RETURN OLD;   -- BEFORE DELETE must return OLD or it CANCELS the delete
  END IF;

  PERFORM public.psh2_post_function('session-notification', jsonb_build_object(
    'type',       TG_OP,
    'table',      'sessions',
    'schema',     'public',
    'record',     to_jsonb(NEW),
    'old_record', CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END
  ));
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_session_change: push failed for session % (%): %',
      coalesce(NEW.id, OLD.id), SQLSTATE, SQLERRM;
    RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS trg_session_notification ON public.sessions;
-- Review-round gate: the DELETE twin below always had the published/not-time-off guard;
-- this UPDATE trigger did not, so renaming a DRAFT (or a time-off block) pushed "Session
-- Updated" to crew PUB.1 deliberately redacts drafts from. Fires only when the session
-- is or was visible to crew (published on at least one side) and is not time off; a
-- draft-to-draft rename now stays silent while publish and unpublish transitions still
-- fire (the edge function renders unpublish as a cancellation — see its comment).
CREATE TRIGGER trg_session_notification
  AFTER UPDATE OF is_published, school_name ON public.sessions
  FOR EACH ROW
  WHEN (
    (OLD.is_published IS TRUE OR NEW.is_published IS TRUE)
    AND OLD.is_time_off IS NOT TRUE
    AND NEW.is_time_off IS NOT TRUE
    AND (
      OLD.is_published IS DISTINCT FROM NEW.is_published
      OR OLD.school_name IS DISTINCT FROM NEW.school_name
    )
  )
  EXECUTE FUNCTION public.notify_session_change();

DROP TRIGGER IF EXISTS trg_session_delete_notification ON public.sessions;
-- WHEN clause (PSH.2 fix round, H3): a deleted DRAFT must not push "Session Cancelled"
-- to crew who were never told the session existed — PUB.1 deliberately redacts draft
-- crew from non-schedulers, and announcing a draft's death un-redacts it. Same for
-- deleting a time-off block. Every other recipient path in this phase already gates on
-- published-and-not-time-off; the delete path was the one that did not.
CREATE TRIGGER trg_session_delete_notification
  BEFORE DELETE ON public.sessions
  FOR EACH ROW
  WHEN (OLD.is_published IS TRUE AND OLD.is_time_off IS NOT TRUE)
  EXECUTE FUNCTION public.notify_session_change();

-- ============================================================================
-- 5. Session days — "You've been assigned" fires when the crew actually lands
-- ============================================================================
-- Statement-level with a transition table: the web inserts a session's day rows in one
-- statement, so this sends ONE push per creation, not one per day. It fires only when the
-- parent session is already published — for the publish-gated orgs the day rows land
-- while unpublished (nothing sent here; the publish transition above carries the news),
-- while the direct-publish org inserts published sessions and gets its assignment push
-- from here. Adding a day to an already-published session also lands here, which is
-- correct: that day's crew was just assigned. The web EDITS existing days by UPDATE, not
-- delete-and-reinsert (queries.js syncSessionDays diffs by id — verified), so edits do
-- not re-fire this.

CREATE OR REPLACE FUNCTION public.notify_session_days_assigned()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_session record;
  v_crew    text[];
  v_dates   text;
BEGIN
  FOR v_session IN
    SELECT nd.session_id,
           min(nd.date)  AS first_date,
           count(DISTINCT nd.date) AS day_count,
           s.school_name,
           s.id AS sid
      FROM new_days nd
      JOIN public.sessions s ON s.id = nd.session_id
     WHERE s.is_published IS TRUE
       AND s.is_time_off IS NOT TRUE
     GROUP BY nd.session_id, s.school_name, s.id
  LOOP
    SELECT array_agg(DISTINCT p.id) INTO v_crew
      FROM new_days nd
      CROSS JOIN LATERAL (
        SELECT elem->>'id' AS id
          FROM jsonb_array_elements(coalesce(nd.photographers, '[]'::jsonb)) elem
      ) p
     WHERE nd.session_id = v_session.session_id
       AND coalesce(p.id, '') <> '';

    CONTINUE WHEN v_crew IS NULL;

    v_dates := coalesce(v_session.first_date, 'an upcoming date')
               || CASE WHEN v_session.day_count > 1
                       THEN ' (+' || (v_session.day_count - 1) || ' more day'
                            || CASE WHEN v_session.day_count > 2 THEN 's' ELSE '' END || ')'
                       ELSE '' END;

    PERFORM public.psh2_send_push(
      v_crew,
      'New Session Assigned',
      'You''ve been assigned to ' || coalesce(v_session.school_name, 'a session')
        || ' on ' || v_dates,
      'session_new',
      jsonb_build_object(
        -- sessionId feeds the tap routing (TabBarManager.pendingSessionId → the shift).
        'sessionId',   v_session.sid,
        'schoolName',  coalesce(v_session.school_name, ''),
        'sessionDate', coalesce(v_session.first_date, '')
      )
    );
  END LOOP;
  RETURN NULL;   -- AFTER statement triggers return NULL
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_session_days_assigned: push failed (%): %', SQLSTATE, SQLERRM;
    RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_session_days_assigned_notification ON public.session_days;
CREATE TRIGGER trg_session_days_assigned_notification
  AFTER INSERT ON public.session_days
  REFERENCING NEW TABLE AS new_days
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.notify_session_days_assigned();

-- ============================================================================
-- 5b. Crew ADDED to an existing day (fix-round, F2) — the dominant assignment path
-- ============================================================================
-- The INSERT trigger above covers create-with-crew and add-a-day. But in BOTH clients
-- the ordinary way a person gets assigned is an UPDATE of an existing day's
-- photographers jsonb — the web scheduling modal, the AI assignment engine, and the iOS
-- crew editor all do it that way — and without this trigger every one of those
-- assignments notified nobody. Pushes go only to the ADDED ids (OLD∖NEW diff), only
-- when the parent is published and not time off. A whole-session assignment on a
-- multi-day session updates each day row in its own statement, so an added person can
-- receive one push per day — accepted: sessions here average ~1.1 days, and dedup
-- across statements would need cross-statement state. Removal from crew deliberately
-- notifies nobody (recorded, not built).

CREATE OR REPLACE FUNCTION public.notify_session_day_crew_added()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_added   text[];
  v_session record;
BEGIN
  SELECT array_agg(DISTINCT n.id) INTO v_added
    FROM (
      SELECT elem->>'id' AS id
        FROM jsonb_array_elements(coalesce(NEW.photographers, '[]'::jsonb)) elem
    ) n
   WHERE coalesce(n.id, '') <> ''
     AND NOT EXISTS (
           SELECT 1 FROM jsonb_array_elements(coalesce(OLD.photographers, '[]'::jsonb)) o
            WHERE o->>'id' = n.id
         );

  IF v_added IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT s.id AS sid, s.school_name INTO v_session
    FROM public.sessions s
   WHERE s.id = NEW.session_id
     AND s.is_published IS TRUE
     AND s.is_time_off IS NOT TRUE;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  PERFORM public.psh2_send_push(
    v_added,
    'New Session Assigned',
    'You''ve been assigned to ' || coalesce(v_session.school_name, 'a session')
      || ' on ' || coalesce(NEW.date, 'an upcoming date'),
    'session_new',
    jsonb_build_object(
      'sessionId',   v_session.sid,
      'schoolName',  coalesce(v_session.school_name, ''),
      'sessionDate', coalesce(NEW.date, '')
    )
  );
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_session_day_crew_added: push failed for day % (%): %', NEW.id, SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_session_day_crew_added_notification ON public.session_days;
CREATE TRIGGER trg_session_day_crew_added_notification
  AFTER UPDATE OF photographers ON public.session_days
  FOR EACH ROW
  WHEN (OLD.photographers IS DISTINCT FROM NEW.photographers)
  EXECUTE FUNCTION public.notify_session_day_crew_added();

COMMENT ON FUNCTION public.notify_session_day_crew_added() IS
  'PSH.2 fix round: assignment push for crew ADDED to an existing published day — the '
  'dominant assignment path in both clients is an UPDATE of session_days.photographers, '
  'which the INSERT trigger cannot see. Pushes only to added ids. Never blocks the write.';

-- ============================================================================
-- 6. Time off — the reason comes OFF the lock screen (privacy decision, PSH.2)
-- ============================================================================
-- The submitted-request push carried the requester's reason and the denial push carried
-- the manager's denial reason — both can be medical or family detail, and a push body
-- renders on the lock screen of whatever is lying on the kitchen counter. Decided
-- deliberately rather than by copy (the roadmap's instruction): the flag trigger already
-- keeps its note off the lock screen for exactly this reason, and PSH.2 adds
-- tap-to-navigate, so the detail is one tap away inside the app where it belongs. The
-- bodies below carry the decision and the dates; the reasons stay in the database. Only
-- the body construction changes; everything else matches 20260727_psh1_time_off_notifications.sql.

CREATE OR REPLACE FUNCTION public.notify_time_off_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_recipients    text[];
  v_title         text;
  v_body          text;
  v_type          text;
  v_actor         text;
  v_dates         text;
  v_old_status    text;
  v_new_status    text;
  v_tz            text;
BEGIN
  v_old_status := replace(replace(lower(btrim(coalesce(OLD.status, ''))), '_', ''), ' ', '');
  v_new_status := replace(replace(lower(btrim(coalesce(NEW.status, ''))), '_', ''), ' ', '');

  -- Dates render in the ORG'S clock, not the server's (review round): an evening
  -- Central-time submission stores start_date past UTC midnight, and to_char in the
  -- session timezone told the requester their Jul 30 time off was "for Jul 31" — a
  -- wrong day on a payroll-adjacent message. Same timezone convention as the reminder
  -- dispatchers (organizations.preferences, America/Chicago fallback).
  SELECT coalesce(o.preferences->>'timezone', 'America/Chicago') INTO v_tz
    FROM public.organizations o WHERE o.id = NEW.organization_id;
  v_tz := coalesce(v_tz, 'America/Chicago');

  v_dates := CASE
    WHEN NEW.start_date IS NULL AND NEW.end_date IS NULL
      THEN 'your requested dates'
    WHEN NEW.start_date IS NULL OR NEW.end_date IS NULL
      THEN to_char(coalesce(NEW.start_date, NEW.end_date) AT TIME ZONE v_tz, 'Mon FMDD')
    WHEN (NEW.start_date AT TIME ZONE v_tz)::date = (NEW.end_date AT TIME ZONE v_tz)::date
      THEN to_char(NEW.start_date AT TIME ZONE v_tz, 'Mon FMDD')
    ELSE to_char(NEW.start_date AT TIME ZONE v_tz, 'Mon FMDD') || ' to '
         || to_char(NEW.end_date AT TIME ZONE v_tz, 'Mon FMDD')
  END;

  IF TG_OP = 'INSERT' THEN
    IF v_new_status NOT IN ('pending', 'underreview') THEN
      RETURN NEW;
    END IF;

    SELECT array_agg(u.id) INTO v_recipients
      FROM public.users u
     WHERE u.organization_id = NEW.organization_id
       -- lower() both sides (review round): iOS's TimeOffService verifiably inserts
       -- UPPERCASE uuids (recorded under TOF.1), so a case-sensitive exclusion would
       -- notify a requesting manager of their own submission. Comparison fold only —
       -- the recipient values themselves stay as stored.
       AND lower(u.id) IS DISTINCT FROM lower(NEW.photographer_id)
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
    -- PSH.2 privacy: the reason is deliberately NOT in the body (it was, in PSH.1).
    v_body  := coalesce(NEW.photographer_name, 'Someone') || ' requested ' || v_dates || '.';

  ELSE
    IF v_old_status = v_new_status THEN
      RETURN NEW;
    END IF;

    IF v_new_status NOT IN ('approved', 'denied', 'partiallyapproved') THEN
      RETURN NEW;
    END IF;

    v_actor := CASE v_new_status
                 WHEN 'approved' THEN NEW.approved_by
                 WHEN 'denied'   THEN NEW.denied_by
                 ELSE NEW.approved_by
               END;

    IF NEW.photographer_id IS NULL
       OR lower(NEW.photographer_id) IS NOT DISTINCT FROM lower(v_actor) THEN
      RETURN NEW;
    END IF;

    v_recipients := ARRAY[NEW.photographer_id];

    IF v_new_status = 'approved' THEN
      v_type  := 'time_off_approved';
      v_title := 'Time Off Approved';
      v_body  := 'Your time off for ' || v_dates || ' was approved.';
    ELSIF v_new_status = 'denied' THEN
      v_type  := 'time_off_denied';
      v_title := 'Time Off Denied';
      -- PSH.2 privacy: the denial reason is deliberately NOT in the body (it was, in
      -- PSH.1). The tap opens the request, where the reason is shown.
      v_body  := 'Your time off for ' || v_dates || ' was denied. Tap for details.';
    ELSE
      v_type  := 'time_off_partially_approved';
      v_title := 'Time Off Partially Approved';
      v_body  := 'Some of your time off for ' || v_dates || ' was approved. Open the app for details.';
    END IF;
  END IF;

  PERFORM public.psh2_send_push(
    v_recipients, v_title, v_body, v_type,
    jsonb_build_object(
      'requestId', NEW.id,
      'status',    NEW.status,
      'startDate', NEW.start_date,
      'endDate',   NEW.end_date
    )
  );
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_time_off_change: push failed for request % (%): %', NEW.id, SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$function$;

-- The trigger itself (trg_time_off_notification, AFTER INSERT OR UPDATE) is unchanged;
-- CREATE OR REPLACE swaps the body under it in place.

-- ============================================================================
-- 7. Flag trigger joins the shared transport (review round)
-- ============================================================================
-- notify_user_flagged (20260727_flg1_user_flag_notification.sql) was the last hand copy
-- of the vault-fetch/cap/post skeleton psh2_send_push centralizes — and one copy left
-- behind is exactly how "a fix applied to one copy while the second keeps the bug"
-- happens: a secret rename or sender-contract change would fix six consumers and
-- silently kill flag pushes. Behavior is unchanged (same guards, same payload, same
-- 300-char cap — now applied by the helper); the trigger and its WHEN clause are
-- untouched. Supersedes the FLG.1 file's function body.

CREATE OR REPLACE FUNCTION public.notify_user_flagged()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_body text;
BEGIN
  -- No recipient, no push. users.id is NOT lowercased here (the FLG.1 rule: one
  -- mixed-case legacy Firebase uid exists; folding a LOOKUP value misses it).
  IF NEW.id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Whoever pressed the button does not need to be told they pressed it.
  IF lower(NEW.flagged_by) IS NOT DISTINCT FROM lower(NEW.id) THEN
    RETURN NEW;
  END IF;

  v_body := nullif(btrim(coalesce(NEW.flag_note, '')), '');
  IF v_body IS NULL THEN
    RAISE WARNING 'notify_user_flagged: user % flagged with an empty note; no push sent', NEW.id;
    RETURN NEW;
  END IF;

  PERFORM public.psh2_send_push(
    ARRAY[NEW.id],
    'You''ve Been Flagged',
    v_body,                      -- psh2_send_push caps at 300 chars (4KB APNs limit)
    'flag',                      -- must match PushNotificationManager.NotificationType
    jsonb_build_object('flaggedBy', NEW.flagged_by, 'note', v_body)
  );
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_user_flagged: push failed for user % (%): %', NEW.id, SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.notify_chat_message() IS
  'PSH.2: posts new chat messages to the chat-notification edge function. Covers both the '
  'iOS app and the web app because both insert into public.messages. System rows excluded '
  'by the trigger WHEN clause. Never blocks the write.';
COMMENT ON FUNCTION public.notify_photo_critique() IS
  'PSH.2: notifies the target photographer when a critique is published (insert-published '
  'or a status transition to published). Never blocks the write.';
COMMENT ON FUNCTION public.notify_job_box() IS
  'PSH.2: notifies the shift''s crew (minus the scanner) when a job box is scanned. '
  'Never blocks the write.';
COMMENT ON FUNCTION public.notify_session_days_assigned() IS
  'PSH.2: statement-level assignment push when day rows land for a published session. '
  'This is the only "new session" push — see notify_session_change for why sessions has '
  'no INSERT trigger. Never blocks the write.';
COMMENT ON FUNCTION public.notify_session_change() IS
  'PSH.1, repaired in PSH.2: posts session publish/rename/delete events to the '
  'session-notification edge function. DELETE runs BEFORE the row goes so the crew '
  '(session_days.photographers) can be captured into the payload as crew_ids. Supersedes '
  'the web repo''s 20260714 definition. Never blocks the write.';

-- REVERSIBLE WITH:
--   DROP TRIGGER IF EXISTS trg_chat_message_notification ON public.messages;
--   DROP TRIGGER IF EXISTS trg_photo_critique_notification_ins ON public.photo_critiques;
--   DROP TRIGGER IF EXISTS trg_photo_critique_notification_upd ON public.photo_critiques;
--   DROP TRIGGER IF EXISTS trg_job_box_notification ON public.job_boxes;
--   DROP TRIGGER IF EXISTS trg_session_days_assigned_notification ON public.session_days;
--   DROP TRIGGER IF EXISTS trg_session_delete_notification ON public.sessions;
--   DROP FUNCTION IF EXISTS public.notify_chat_message(), public.notify_photo_critique(),
--     public.notify_job_box(), public.notify_session_days_assigned();
--   -- and restore notify_session_change()/notify_time_off_change() from
--   -- 20260714_sec1_session_notification_vault.sql / 20260727_psh1_time_off_notifications.sql,
--   -- recreating trg_session_notification AS AFTER INSERT OR UPDATE OR DELETE.

-- STATUS: NOT YET APPLIED. Written 2026-07-26 during AMB.6.
--
-- Adds the ONE chat RPC that fix_chat_rpcs.sql deliberately did not: raising
-- everyone else's unread count when a message is sent.
--
-- Why it is needed: the iOS app has never incremented anyone's unread count.
-- SupabaseChatService.sendMessage carried a comment saying it required an RPC
-- and then simply did not do it, so a message sent from the phone never moved
-- another participant's badge. Only web-sent messages did, because the web app
-- does it client-side.
--
-- Why an RPC rather than copying the web app's approach: the web app SELECTs the
-- whole conversation row, mutates unread_counts in JavaScript, and UPDATEs the
-- whole blob back (src/services/chatService.js sendMessage). Two people sending
-- at the same time both read the same counts and both write back their own +1,
-- so one increment is silently lost; it also clobbers a concurrent mark-as-read.
-- The window is a full network round trip, not a microsecond. Doing it in one
-- statement with jsonb_set removes the race for the iOS side.
--
-- Security: SECURITY DEFINER, matching the five functions in fix_chat_rpcs.sql,
-- because it must write OTHER participants' entries which the caller's own RLS
-- policy would not be the right check for. It verifies the caller is the sender
-- (sender_id = auth.uid()) AND that the caller is a participant, exactly as the
-- existing five do. Idempotent (CREATE OR REPLACE).
--
-- Blast radius on the SHARED database: additive only. No schema change, no
-- policy change, no change to any existing function. The web app keeps its own
-- client-side increment and is unaffected — it re-reads the whole row on every
-- realtime event, so a server-authored increment arrives as an ordinary UPDATE
-- and is picked up identically. Captura does not touch chat.
--
-- KNOWN, AND DELIBERATELY NOT SOLVED HERE: a web send concurrent with an iOS
-- send can still lose the iOS increment, because the web app writes the whole
-- blob. That is the web app's pre-existing race with itself; closing it means
-- moving the web app onto this RPC too, which is a change to the other app and
-- is not AMB.6's to make.

CREATE OR REPLACE FUNCTION public.increment_conversation_unread(conversation_id text, sender_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_parts  jsonb;
  v_unread jsonb;
  pid      text;
BEGIN
  IF lower(sender_id) <> lower((auth.uid())::text) THEN RAISE EXCEPTION 'Not authorized'; END IF;

  SELECT participants, coalesce(unread_counts, '{}'::jsonb)
    INTO v_parts, v_unread
    FROM conversations
   WHERE id = conversation_id;

  IF v_parts IS NULL THEN RAISE EXCEPTION 'Conversation not found'; END IF;
  IF NOT (v_parts @> to_jsonb((auth.uid())::text)) THEN RAISE EXCEPTION 'Not a participant'; END IF;

  -- Every participant except the sender. The comparison is lower()ed on both
  -- sides: this project stores lowercase UUIDs but Swift generates uppercase,
  -- and the web app's equivalent uses a case-SENSITIVE compare, which would
  -- increment the sender's own count on a mixed-case id.
  FOR pid IN SELECT jsonb_array_elements_text(v_parts) LOOP
    IF lower(pid) <> lower(sender_id) THEN
      v_unread := jsonb_set(
        v_unread,
        array[pid],
        to_jsonb(coalesce((v_unread ->> pid)::int, 0) + 1),
        true
      );
    END IF;
  END LOOP;

  UPDATE conversations SET unread_counts = v_unread WHERE id = conversation_id;
END $$;

-- Lock down + expose to the app role, matching fix_chat_rpcs.sql.
REVOKE ALL ON FUNCTION public.increment_conversation_unread(text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.increment_conversation_unread(text,text) TO authenticated;

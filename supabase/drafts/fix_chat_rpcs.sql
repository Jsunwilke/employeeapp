-- STATUS: APPLIED + verified live 2026-07-13 (behavioral test on a real UUID
-- conversation confirmed mark-read + pin work under a simulated participant JWT,
-- rolled back so nothing persisted). Idempotent (IF NOT EXISTS / CREATE OR REPLACE).
--
-- Fix the 5 chat RPCs the iOS employee app calls that DON'T EXIST in the DB, so
-- these features silently fail today: mark-read, pin/unpin, add participant,
-- remove participant, leave conversation. Behavior mirrors the web app's
-- services/chatService.js (direct-update logic), reimplemented server-side.
--
-- Also adds the missing `pinned_by` column (both apps expect it; the web app's
-- togglePin select('pinned_by') is broken without it too).
--
-- Security: all SECURITY DEFINER (they must edit rows the caller may not directly
-- update, e.g. leaving removes yourself which RLS WITH CHECK would block). Each
-- verifies the caller is a participant AND that the actor id argument equals
-- auth.uid() — so a caller can't act as someone else (closes the roadmap's
-- "chat RPCs trust p_user_id" concern). Contract matches the iOS param names.
--
-- Deliberately NOT replicating the web app's "system message" insert: the messages
-- table has none of the columns it uses (system_action, added_by, …) and no id
-- default, so that insert is itself broken. Core operations only — a working
-- system-message design is a separate follow-up.

-- Missing column both apps read/write (jsonb array of user ids that pinned it).
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS pinned_by jsonb NOT NULL DEFAULT '[]'::jsonb;

-- Helper predicate reused below: is the authenticated caller a participant?
-- (matches the existing conversations_participant_access RLS expression.)

-- 1) mark_conversation_read(conversation_id, user_id) → unread_counts[user_id] = 0
CREATE OR REPLACE FUNCTION public.mark_conversation_read(conversation_id text, user_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_parts jsonb;
BEGIN
  IF lower(user_id) <> lower((auth.uid())::text) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT participants INTO v_parts FROM conversations WHERE id = conversation_id;
  IF v_parts IS NULL THEN RAISE EXCEPTION 'Conversation not found'; END IF;
  IF NOT (v_parts @> to_jsonb((auth.uid())::text)) THEN RAISE EXCEPTION 'Not a participant'; END IF;
  UPDATE conversations
     SET unread_counts = jsonb_set(coalesce(unread_counts,'{}'::jsonb), array[user_id], '0'::jsonb, true)
   WHERE id = conversation_id;
END $$;

-- 2) toggle_pin_conversation(conversation_id, user_id, is_pinned)  (is_pinned = desired final state)
CREATE OR REPLACE FUNCTION public.toggle_pin_conversation(conversation_id text, user_id text, is_pinned boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_parts jsonb; v_pins jsonb;
BEGIN
  IF lower(user_id) <> lower((auth.uid())::text) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT participants, coalesce(pinned_by,'[]'::jsonb) INTO v_parts, v_pins FROM conversations WHERE id = conversation_id;
  IF v_parts IS NULL THEN RAISE EXCEPTION 'Conversation not found'; END IF;
  IF NOT (v_parts @> to_jsonb((auth.uid())::text)) THEN RAISE EXCEPTION 'Not a participant'; END IF;
  IF is_pinned THEN
    IF NOT (v_pins @> to_jsonb(user_id)) THEN v_pins := v_pins || to_jsonb(user_id); END IF;
  ELSE
    v_pins := (SELECT coalesce(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements_text(v_pins) e WHERE e <> user_id);
  END IF;
  UPDATE conversations SET pinned_by = v_pins WHERE id = conversation_id;
END $$;

-- 3) add_conversation_participants(conversation_id, new_participant_ids, added_by_id, added_by_name)
CREATE OR REPLACE FUNCTION public.add_conversation_participants(conversation_id text, new_participant_ids text[], added_by_id text, added_by_name text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_parts jsonb; v_unread jsonb; nid text;
BEGIN
  IF lower(added_by_id) <> lower((auth.uid())::text) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT participants, coalesce(unread_counts,'{}'::jsonb) INTO v_parts, v_unread FROM conversations WHERE id = conversation_id;
  IF v_parts IS NULL THEN RAISE EXCEPTION 'Conversation not found'; END IF;
  IF NOT (v_parts @> to_jsonb((auth.uid())::text)) THEN RAISE EXCEPTION 'Not a participant'; END IF;
  FOREACH nid IN ARRAY new_participant_ids LOOP
    IF nid IS NOT NULL AND nid <> '' AND NOT (v_parts @> to_jsonb(nid)) THEN
      v_parts := v_parts || to_jsonb(nid);
      v_unread := jsonb_set(v_unread, array[nid], '0'::jsonb, true);
    END IF;
  END LOOP;
  UPDATE conversations SET participants = v_parts, unread_counts = v_unread WHERE id = conversation_id;
END $$;

-- 4) remove_conversation_participant(conversation_id, participant_id, removed_by_id, removed_by_name, removed_participant_name)
CREATE OR REPLACE FUNCTION public.remove_conversation_participant(conversation_id text, participant_id text, removed_by_id text, removed_by_name text, removed_participant_name text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_parts jsonb; v_unread jsonb;
BEGIN
  IF lower(removed_by_id) <> lower((auth.uid())::text) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT participants, coalesce(unread_counts,'{}'::jsonb) INTO v_parts, v_unread FROM conversations WHERE id = conversation_id;
  IF v_parts IS NULL THEN RAISE EXCEPTION 'Conversation not found'; END IF;
  IF NOT (v_parts @> to_jsonb((auth.uid())::text)) THEN RAISE EXCEPTION 'Not a participant'; END IF;
  v_parts := (SELECT coalesce(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements_text(v_parts) e WHERE e <> participant_id);
  v_unread := v_unread - participant_id;
  UPDATE conversations SET participants = v_parts, unread_counts = v_unread WHERE id = conversation_id;
END $$;

-- 5) leave_conversation(conversation_id, user_id, user_name)
CREATE OR REPLACE FUNCTION public.leave_conversation(conversation_id text, user_id text, user_name text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_parts jsonb; v_unread jsonb; v_type text;
BEGIN
  IF lower(user_id) <> lower((auth.uid())::text) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT participants, coalesce(unread_counts,'{}'::jsonb), type INTO v_parts, v_unread, v_type FROM conversations WHERE id = conversation_id;
  IF v_parts IS NULL THEN RAISE EXCEPTION 'Conversation not found'; END IF;
  IF NOT (v_parts @> to_jsonb(user_id)) THEN RAISE EXCEPTION 'User is not a participant in this conversation'; END IF;
  IF v_type = 'direct' THEN RAISE EXCEPTION 'Cannot leave direct conversations'; END IF;
  IF jsonb_array_length(v_parts) <= 2 THEN RAISE EXCEPTION 'Cannot leave group - would have less than 2 participants'; END IF;
  v_parts := (SELECT coalesce(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements_text(v_parts) e WHERE e <> user_id);
  v_unread := v_unread - user_id;
  UPDATE conversations SET participants = v_parts, unread_counts = v_unread WHERE id = conversation_id;
END $$;

-- Lock down + expose to the app role.
DO $$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'mark_conversation_read(text,text)',
    'toggle_pin_conversation(text,text,boolean)',
    'add_conversation_participants(text,text[],text,text)',
    'remove_conversation_participant(text,text,text,text,text)',
    'leave_conversation(text,text,text)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM public;', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated;', fn);
  END LOOP;
END $$;

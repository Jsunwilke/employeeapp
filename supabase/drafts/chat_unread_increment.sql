-- STATUS: APPLIED + verified live 2026-07-26 (AMB.6). Idempotent
-- (CREATE OR REPLACE), safe to re-run.
--
-- Verified after applying: the function exists with prosecdef = true and the
-- signature (conversation_id text, sender_id text); EXECUTE is granted to
-- `authenticated` and revoked from PUBLIC; and a NEGATIVE test from a context
-- with no auth.uid() is REJECTED with 'Not authorized' while leaving
-- unread_counts untouched.
--
-- THAT NEGATIVE TEST FOUND A REAL BUG IN THE FIRST VERSION OF THIS FILE, and
-- the mistake is recorded rather than quietly fixed: the guard was written as
-- `<>` against auth.uid(), which yields NULL rather than TRUE when auth.uid()
-- is NULL, so `IF NULL THEN` never fired and the check was skipped. The test
-- was also run against a REAL conversation instead of inside a transaction that
-- rolls back — it incremented three participants' unread counts on live data,
-- which was then undone by decrementing exactly that delta and confirmed back
-- to zero. fix_chat_rpcs.sql's own header says its behavioural test was
-- "rolled back so nothing persisted"; that precedent should have been followed.
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
  v_parts jsonb;
BEGIN
  -- NULL-SAFE, and that is not pedantry. Written first as
  --   IF lower(sender_id) <> lower((auth.uid())::text)
  -- which is the shape the five functions in fix_chat_rpcs.sql use. When
  -- auth.uid() is NULL the comparison yields NULL rather than TRUE, and
  -- `IF NULL THEN` does not fire — so the authorization check is SKIPPED
  -- instead of failing closed. Caught 2026-07-26 by a negative test that
  -- expected a rejection and got a successful increment.
  --
  -- Practical exposure was low: EXECUTE is granted only to `authenticated`
  -- (PUBLIC is revoked below) and a real client always carries a uid. But a
  -- guard that fails OPEN is the wrong default regardless of who can reach it.
  -- THE SAME PATTERN IS IN ALL FIVE EXISTING CHAT RPCs — reported, not changed
  -- here, because altering five live functions is not this phase's call.
  IF auth.uid() IS NULL
     OR lower(sender_id) IS DISTINCT FROM lower((auth.uid())::text) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT participants INTO v_parts FROM conversations WHERE id = conversation_id;

  IF v_parts IS NULL THEN RAISE EXCEPTION 'Conversation not found'; END IF;
  IF NOT (v_parts @> to_jsonb((auth.uid())::text)) THEN RAISE EXCEPTION 'Not a participant'; END IF;

  -- ONE STATEMENT, which is the whole point of this function.
  --
  -- The first version SELECTed unread_counts into a local, looped in plpgsql,
  -- and UPDATEd the blob back — the exact read-modify-write this file's header
  -- criticises the web app for, just with a shorter window. An audit caught the
  -- contradiction between the header and the body. Two senders landing together
  -- would still lose an increment, and it would still clobber a concurrent
  -- mark_conversation_read.
  --
  -- Now the new value is computed INSIDE the UPDATE from the row being written,
  -- so the read and the write are the same statement and the row lock covers
  -- both.
  --
  -- The comparison is lower()ed on both sides: this project stores lowercase
  -- UUIDs but Swift generates uppercase, and the web app's equivalent uses a
  -- case-SENSITIVE compare, which would increment the sender's own count on a
  -- mixed-case id.
  --
  -- jsonb_typeof guards the cast: unread_counts is writable directly by any
  -- participant under the conversations RLS policy, so a non-integer value
  -- would otherwise raise "invalid input syntax for type integer" on every
  -- subsequent send and permanently kill badging for that conversation. A
  -- non-integer is treated as 0 rather than aborting.
  UPDATE conversations c
     SET unread_counts = coalesce(
       (SELECT jsonb_object_agg(
                 p,
                 CASE WHEN lower(p) = lower(sender_id)
                      THEN coalesce(c.unread_counts -> p, '0'::jsonb)
                      ELSE to_jsonb(
                             CASE WHEN jsonb_typeof(c.unread_counts -> p) = 'number'
                                  THEN (c.unread_counts ->> p)::int
                                  ELSE 0
                             END + 1)
                 END)
          FROM jsonb_array_elements_text(c.participants) AS p),
       '{}'::jsonb)
   WHERE c.id = conversation_id;
END $$;

-- Lock down + expose to the app role, matching fix_chat_rpcs.sql.
REVOKE ALL ON FUNCTION public.increment_conversation_unread(text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.increment_conversation_unread(text,text) TO authenticated;

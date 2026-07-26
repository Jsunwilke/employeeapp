# Chat needs a data-layer rebuild — findings from AMB.6, 2026-07-26

Written at the close of AMB.6 so this is not reconstructed from memory later.

AMB.6 set out to restyle Chat and found a feature that had not worked since
September 2025. The screens are converted and the worst defects are fixed, but
the SHAPE of the data underneath is what produced them, and that is not
something a design phase should change.

THIS IS A REPORT. Nothing here is scheduled. It needs its own registered arc,
the plain-English architecture gate, and sequencing with whoever owns the web
app.


## The one sentence version

The database stores raw data and every client re-implements the rules over it.
There are at least two clients. They disagree. Every bug below is that.


## THE CONSTRAINT THAT SHAPES EVERYTHING: this is multiplatform

The Supabase project is shared by the iOS employee app, the Focal Point web app,
and Captura. Chat is used by at least the first two. So:

    a schema change is a coordinated migration across apps, not an iOS task
    any rule implemented in a client is a rule the other client can contradict
    the fix is to move truth INTO the database, where all clients read the same
      answer and none can corrupt it

That last line is the actual design principle, and it is a stronger argument for
doing the work than any individual bug: the current design makes divergence
inevitable rather than unlikely.


## What was verified against the live database on 2026-07-26

Stated separately from what was read in code, because the difference matters.

    conversations.last_message is a TEXT column
    participants, unread_counts and pinned_by are jsonb
    14 conversations exist; 10 have a non-null last_message
    all 10 hold a stringified LEGACY FIREBASE object, senderId in camelCase and
      a Firestore Timestamp of the form {"_seconds":…, "_nanoseconds":…}
    the membership query the iOS app used could never succeed: a Swift array
      became a POSTGRES ARRAY literal, {uuid}, sent against a JSONB column, so
      Postgres answered "invalid input syntax for type json" every time
    the corrected form, ["uuid"], returns six conversations for the operator


## The three structural problems

1. PARTICIPANTS ARE A JSON BLOB, NOT RELATIONSHIPS.
   Each conversation carries its members as a jsonb array of user id strings.
   There is no foreign key, so nothing validates them and nothing can join to
   get a name — the app instead fetches every user in the organisation and
   matches in memory. Nine of the fourteen conversations are believed to point
   at Firebase ids that no longer resolve (recorded in RLS_AUDIT.md; NOT
   re-verified against the database, and it should be before this is relied on).
   Membership filtering in jsonb is also what both clients got wrong.

   Shape it should be: a conversation_participants join table, one row per
   person per conversation, with real foreign keys.

2. UNREAD COUNTS ARE A STORED NUMBER THAT TWO CLIENTS BOTH EDIT.
   unread_counts is a jsonb map of person to count. Both apps read it, mutate it
   in memory, and write the whole blob back. That loses increments when two
   people send at once, and a reader opening a conversation can overwrite
   someone else's count. AMB.6 added an atomic RPC for the iOS half; the web app
   still writes the whole blob, so the race is only half closed.

   Shape it should be: one last_read_at per person per conversation, and unread
   DERIVED as a count of newer messages. Nothing to increment, nothing to race,
   cannot drift. It deletes the RPC and the whole class of bug — but only if it
   is server-side, otherwise the disagreement has simply moved.

3. MESSAGE TYPE IS GUESSED FROM THE MESSAGE TEXT.
   There is no field saying what a message is. The app searches the body for
   ".jpg", ".png", "giphy.com" and so on. A message reading "check logo.png" is
   therefore rendered as an image and the words are lost. Found in the AMB.6
   audit and deliberately left, because fixing it properly means a real
   attachments table.

   Shape it should be: a message_attachments table, and a type column with a
   constraint rather than a string clients parse.


## Smaller inherited problems

    last_message is TEXT holding JSON, and the two apps write DIFFERENT shapes
      into it — the iOS app a bare string, the web app an object. This is the
      bug that blanked the conversation list, and it will recur until they agree
      or the column stops being free-form.
    The message model expects ten system-message columns (X added Y to the
      group, X removed Y, X left) that DO NOT EXIST in the table, so system
      messages cannot be created at all. Recorded in fix_chat_rpcs.sql's header.
    messages.id has no database default, so a client must invent it.
    Every message stores a COPY of the sender's name, so a name change never
      propagates to old messages.
    Three modelled fields are never read: read receipts, file metadata, delivery
      status. (From a subagent's grep, not re-verified.)
    History pages by OFFSET rather than by cursor, which is why AMB.6 had to add
      a sort tiebreaker to stop rows being skipped between pages.
    Typing indicators and presence exist as models and a writer with no readers.
    All five pre-existing chat RPCs guard with "<>" against auth.uid(), which
      yields NULL rather than TRUE when there is no uid — so the check is SKIPPED
      instead of failing closed. Low exposure (EXECUTE is granted only to
      authenticated) but wrong by default. AMB.6 fixed only its own new RPC.
    Caching is in UserDefaults, and its prune had never run until AMB.6 fixed
      the call site that was supposed to trigger it.


## Why now is the cheapest this will ever be

Chat has been dormant since September 2025, has fourteen conversations, and most
of that data is already dead. A redesign normally means migrating years of live
messages. There is almost nothing here to preserve — and that stops being true
the moment people start using the version that now works.


## What must happen before any of this is proposed as a plan

    read the web app's chat code properly — src/services/chatService.js,
      src/contexts/SupabaseChatContext.js, src/pages/ChatSupabase.js. A subagent
      reported that conversations is touched in only one web file, which would
      concentrate the blast radius usefully, but that is unconfirmed.
    establish whether Captura touches chat AT ALL. There is no Captura source
      tree here; "it does not" is an inference from what is visible in these two
      repos and must not be treated as a fact on a shared database.
    verify the orphaned-participant count against the database rather than
      citing an audit document from an earlier session.
    write the architecture gate in plain English: immediate fix or forward
      architecture, how it survives every real constraint, cost to undo, and
      what is validated versus assumed.

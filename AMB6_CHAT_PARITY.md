# AMB.6 Chat — parity inventory, read from the source

Written at the start of AMB.6, before a single chat screen was touched.

AMB_BATCH1_PARITY.md already carries a Chat section, written in AMB.2 while the
mockup was being drawn. This file supersedes it, for the reason three phases in a
row have now proved: an approved mockup is a design decision, not a capability
inventory. AMB.3 found three feature losses inside an approved design, AMB.4
found seventeen, AMB.5 found four. The expected outcome of this walk is that it
finds something, and it did — see the bottom of this file.

Every line below was read out of the actual Swift, not from the mockup and not
from the earlier inventory.

Marks:

    KEPT      present in the approved mockup, in some form
    MOVED     present, but somewhere else — the new home is named
    ADDED     not in the app today; a deliberate proposal
    DEFECT    a real defect on this surface, verified in code
    OPEN      the conversion phase must decide


## The one thing that changes this phase's shape

Chat is not a working feature being restyled. It is a feature whose data layer is
broken in ten verified ways, and the operator has authorised repairing it (2026-07-26)
rather than converting the screens over the top.

RLS_AUDIT.md records, live-verified 2026-07-12: chat has been dormant since
September 2025, and nine of fourteen conversations are orphaned legacy Firebase-UID
rows that current UUID users cannot see. The operator independently reports chat is
barely used. Those two agree.

So the honest framing for this phase: the redesign is the smaller half.


## Conversation list — ConversationListView

    KEPT   Avatar circle, 50pt, group glyph (person.2.fill) vs two-letter initials
    KEPT   Name, bold when unread
    KEPT   Message preview, two lines
    KEPT   Relative timestamp from the last message
    KEPT   Unread pill, blue, count
    KEPT   Pin glyph, orange, before the name
    KEPT   Media-typed previews — Photo, File, GIF, Link — sniffed from the text,
           plus the "You: " prefix when the sender is you
    KEPT   "No messages yet", italic, when a conversation has none
    KEPT   Swipe leading: Pin / Unpin, orange when unpinned, grey when pinned
    KEPT   Swipe trailing: Delete, GROUPS ONLY. A direct message cannot be swiped
           away. Deliberate, and preserved.
    KEPT   Search by conversation display name
    KEPT   New conversation, toolbar, square.and.pencil
    KEPT   Pick people, and if more than one, name the group
    KEPT   Empty state with its New Conversation button
    KEPT   Loading state
    KEPT   Pull to refresh
    KEPT   Error alert
    MOVED  The pinned row's 10 percent orange wash becomes an orange hairline.
           Under D11 the page already carries chat's own colour and a second
           full-row tint on top of it reads as a rendering fault.
    DEFECT Avatar colour is abs(conversation.id.hashValue) modulo six. Swift's
           hashValue is seeded per process, so every person changes colour on
           every launch. Fixed with AmbientStyle.stableHash.
    DEFECT The list is a List with swipeActions, and that is load-bearing rather
           than a style choice: swipeActions is List-only and does nothing at all
           on a row inside a LazyVStack. The converted screen stays a List with a
           hidden scroll background so the ambient wash still shows.


## Thread — MessageThreadView

    KEPT   Own messages right and tinted, others left on a light fill
    KEPT   60pt gutter on the opposite side
    KEPT   Sender name, groups only, never for your own messages
    KEPT   System messages, centred in a capsule, with their own timestamp:
           X added Y to the group, X removed Y, X left the group
    KEPT   GIF, image and file message types, detected by sniffing the URL
    KEPT   Tap an image to open it full screen
    KEPT   Full screen viewer: save to photos, share sheet, zoom
    KEPT   "Load earlier messages" with its spinner
    KEPT   Pull to refresh
    KEPT   Scroll to bottom on new messages and on appear
    KEPT   Composer: expanding field one to five lines, emoji panel, GIF picker,
           photo picker, file picker
    KEPT   Send button, spins while sending, disabled when empty
    KEPT   Uploading overlay
    KEPT   Overflow menu: Conversation Settings, View Profile (direct only),
           Refresh Messages
    KEPT   Tap anywhere to dismiss the keyboard
    ADDED  Date separators, and grouping of consecutive messages from one person.
           Presentation only.
    ADDED  A 15pt message body. The app has no font modifier on a message at all,
           so it rides on the 17pt default while its own timestamp is 11pt.
    ADDED  A visible failure state for a send that did not land.


## The switches the mockup left live, and how they are resolved

The approved mockup carried four controls rather than decisions. The operator
approved the mockup as it opened, so the positions it opens in are what ships.
Named here so they are cheap to correct rather than discovered later:

    Timestamps      only when the conversation paused   (mockup default)
    Grouping        on                                   (mockup default)
    My bubble       company blue, not chat pink          (mockup default)
    Body font       15pt                                 (mockup default)

The bubble colour default has a recorded reason: chat's feature colour is #D6409F
and under D11 that is also the wash behind the thread, so a pink bubble on a pink
wash risks mush. The company blue says "you" without competing with the screen.


## Conversation settings — ConversationSettingsView

    KEPT   Rename a group, Save and Cancel
    KEPT   Participants with avatar, name, "(You)", email
    KEPT   Add participants
    KEPT   Remove a participant — groups of three or more only, never yourself,
           with a confirmation naming the person
    KEPT   Leave group — groups of three or more only, with confirmation
    KEPT   Delete conversation — groups only, with confirmation
    KEPT   Type and Created info rows
    OPEN   Mocked as an entry point only. Restyled in place, not redesigned.


## The ten verified defects

Each was read in the source and the mechanism named. This is what "full repair"
covers.

    1  THE CONVERSATION LIST CAN DECODE TO EMPTY.
       conversations.last_message is a text column (live schema dump). iOS writes
       a plain String into it, which is correct. iOS DECODES it as a LastMessage
       object, which is not. Any conversation with a non-null last_message throws
       typeMismatch; Swift decodes arrays atomically, so one bad row fails the
       whole fetch; getUserConversations throws; the subscribe path catches it and
       calls completion with an empty array. The list goes blank with nothing but a
       console print. The web app writes an object into the same text column, so
       the two apps disagree about the column's shape in opposite directions.
       FIX: decode tolerantly — accept an object OR a bare string — so every row
       that exists today renders regardless of which app wrote it.

    2  THE THREAD SHOWS THE HUNDRED OLDEST MESSAGES.
       getConversationMessages orders timestamp ASCENDING and ranges forward from
       an offset. The thread's initial load asks for rows 0 to 100, which is the
       hundred OLDEST messages in the conversation. In any conversation longer
       than a hundred messages the recent ones are unreachable, and a message you
       send never appears, because every realtime refresh re-fetches the same
       hundred ancient rows.
       FIX: fetch newest-first and present ascending.

    3  LOAD EARLIER PAGES THE WRONG DIRECTION.
       Same root cause. loadMoreMessages advances the offset forward, which under
       ascending order fetches NEWER messages, and then prepends them ABOVE the
       existing ones. The thread ends up out of chronological order.

    4  hasMoreMessages IS FORCED TRUE.
       Set true unconditionally in loadMessages and refreshMessages, and only ever
       set from real data inside loadMoreMessages. A brand-new two-message
       conversation shows "Load earlier messages".

    5  OPENING A CONVERSATION SHOWS THE PREVIOUS ONE'S MESSAGES.
       loadMessages never clears the shared messages array. On a cache miss the
       previous conversation's bubbles stay on screen until the network returns.
       This is the CommentService shape AMB.5 told this phase to look for, and it
       is here. It matters more in a redesign than it did before, because a count
       drawn from that array would be the previous conversation's number.

    6  A REALTIME EVENT DISCARDS PAGED HISTORY.
       The subscription callback replaces the whole array with a fresh hundred-row
       fetch, so anything paged in by Load earlier is thrown away on the next
       insert.

    7  A FAILED SEND DELETES THE MESSAGE AND THE TYPED TEXT.
       The catch removes every message whose id ends in _temp — which also
       destroys other in-flight sends — and the composer already cleared the field
       before the send completed, so the text is unrecoverable. The error is
       published to a property that the thread never renders; the alert lives on
       the conversation LIST, and only fires when the string CHANGES, so two
       identical consecutive failures raise it once.

    8  IMAGE AND FILE UPLOAD ARE HARD-CODED TO FAIL.
       uploadImage and uploadFile set an error and return nil. The Uploading
       overlay still shows first. No chat storage bucket exists in either app.

    9  iOS NEVER INCREMENTS ANYONE'S UNREAD COUNT.
       sendMessage carries a comment saying it needs an RPC and does not do it. A
       message sent from the iOS app never raises anyone's badge; only web-sent
       messages do.

    10 ChatManager.cleanup() HAS NEVER RUN.
       Its only call site tests the already-updated value against itself, so the
       condition is unsatisfiable. Consequences: pruneOldCache has never run
       either, and channels are never torn down on leaving chat.


## Dead code this phase deletes

    MessageReactionsView and EnhancedMessageBubbleView — the reaction popover, the
      long-press sheet and the Copy/Edit/Delete/Reply context menu. Referenced only
      from each other; the thread renders MessageBubbleView instead. Never mounted.
    ChatService.swift — a 31-line tombstone with no class in it.
    ChatMessage.systemMessageText — dead; MessageBubbleView reimplements the same
      switch privately.
    ChatCacheService.appendNewMessages and getLatestCachedMessageTimestamp — the
      incremental-sync path, no callers.
    UserPresence and TypingIndicator models, and updateUserPresence — no callers,
      nothing reads the user_presence table.


## Dead controls, in the AMB.3 sense

Controls the app draws that do nothing when tapped. AMB.3 found three; this
surface has two, plus one piece of debug output.

    "View Profile" in the thread's overflow menu — the action body is a TODO
      comment. Shown only for direct conversations.
    "Open" on a file message — the action body is a TODO comment.
    ChatMessageContent's initialiser prints to the console on every render, and
      isGifURL prints again on every match. That is a print per message per body
      pass inside a LazyVStack.


## What this walk caught that the approved mockup would have lost

Four, and none of them are style.

    1. THE MESSAGE PREVIEW'S "You: " PREFIX. The mockup's conversation rows show
       the preview text alone. In the app, a preview from you is prefixed "You: "
       for all five preview kinds. In a group list that is the difference between
       knowing whether you are waiting on a reply or owe one.

    2. THE FULL-SCREEN IMAGE VIEWER'S OWN ACTIONS. The mockup takes a tap on an
       image as far as opening it. The real viewer has save-to-photos with its
       result alert, and a share sheet. Both are reachable only from there.

    3. GROUP-ONLY DELETE, AGAIN. AMB_BATCH1_PARITY caught this once and the note
       is easy to read as being about the swipe existing. It is about the swipe
       being CONDITIONAL: a direct message has no trailing swipe at all.

    4. THE COMPOSER'S DISABLED STATE. The accessory row is disabled while a send
       is in flight. The mockup draws the accessory row in one state only.

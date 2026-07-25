# Batch 1 parity inventory — Equipment, Tasks, Chat

Written 2026-07-25, after the operator opened the AMB arc from a restyle to a
REDESIGN with one hard constraint: no feature may be lost.

That constraint is only worth anything if it is checkable, so this file is the
check. Every capability below was read out of the actual source, not inferred
from a screen or remembered from the earlier research pass. AMB_BATCH1_RESEARCH.md
described how the screens LOOK; this describes what they can DO, which is the
thing a redesign can silently drop.

Each line carries a mark:

    KEPT      present in the re-cut mockup, in some form
    MOVED     present, but somewhere else — the new home is named
    ADDED     not in the app today; a deliberate proposal, flagged as one
    OPEN      not resolved by the mockup; the conversion phase must handle it

DELETE THIS FILE when batch 1 is converted (AMB.6 closes the batch), along with
AMB_BATCH1_RESEARCH.md.


## The redesign brief the operator set

    "I do not want to lose any features but it can be redesigned."
    "It needs to fit the ambient style but also be functional for everyday use."

Functional for everyday use is the tie-breaker whenever it fights pretty. The
worked example, found in the code while writing this file: KitDetailView sorts a
kit's categories in PHOTOGRAPHY WORKFLOW ORDER — cameras, then lenses, then
lighting, then stands, then bags, backdrops, power, storage, audio, accessories.
That is somebody thinking about how a case is actually packed. An alphabetical
sort would look identical in a screenshot and be worse every single day.


## EQUIPMENT

### Container — EquipmentTabView

    KEPT   Two tabs, My Kit(s) default and All Equipment
           MOVED: the tab bar is gone. One screen leads with YOUR gear (what the
           default tab showed) and carries "Browse all equipment" as a row into
           the full inventory. Both destinations stay one tap from the top.
    KEPT   QR scan, 56pt, bottom-right. Scanning "EQ-{uuid}" opens that item.
           Kept as a FAB rather than folded into the search field: it is the
           fastest route to an item and it gets tapped with a case in the other
           hand.
    KEPT   Admin kit templates (gearshape), gated on Permissions.has("equipment", .edit)
    KEPT   Home button, top-left

### My Kits — MyKitsView, KitCard

    KEPT   Kit rows: tape-colour stripe, box icon with colour dot, display name,
           description, item count, and exactly one of overdue / permanent /
           return-date
    KEPT   RAINBOW tape colour. The model has isRainbow and three views special-case
           it; a stripe drawn as a flat Color(hex:) renders it as garbage
    KEPT   "Other Equipment" section — items assigned to you outside any kit
    KEPT   Section headers with counts
    KEPT   Empty state, and its "Browse Equipment" button
    KEPT   Pull to refresh
    KEPT   Loading state
    ADDED  A standing line at the top: how many items you have out, what is due
           soon, what is overdue. Today you find out something is late by reading
           every kit card.
    OPEN   In the app, tapping an item in "Other Equipment" does NOTHING — the
           onTapGesture body is an empty comment. The mockup makes it push to the
           item, which is a bug fix, not a redesign. AMB.3 should ship it.

### Kit detail — KitDetailView

    KEPT   Header: kit icon with colour dot, name, description, item count, and
           the overdue / permanent / return badge
    KEPT   Tape-colour reference line ("for physical identification")
    KEPT   Items grouped by category
    KEPT   PHOTOGRAPHY WORKFLOW category order — cameras, lenses, lighting,
           stands, bags, backdrops, power, storage, audio, accessories, then
           unknown, then Uncategorized last
    KEPT   Per-category icons (camera.fill, camera.aperture, light.max, bag.fill…)
    KEPT   Per-item: tape stripe, photo, name, category, condition, serial
    KEPT   Per-item menu when checked out — View Details, Report Damage
    KEPT   "Check In Kit" returning all items, with its item-count caption
    MOVED  Categories now open EXPANDED. Collapsed-by-default means a six-item kit
           opens on three headers and no equipment, which is the wrong default for
           a screen you open to see what is in the case. Collapse still works.
    KEPT   Header is compact rather than a centred 80pt hero — same content, less
           of the fold spent before the first item

### All Equipment — AllEquipmentView

    KEPT   Search across name, serial number AND description
    KEPT   CATEGORY filter chips, built from the org's real categories
    KEPT   STATUS filter chips (available / checked out / needs repair / retired)
    KEPT   Both chip groups in one row with a divider between them
    KEPT   Create equipment (+), gated on Permissions.has("equipment", .edit)
    KEPT   Empty state, and its Clear Filters button, shown only when something
           is actually filtered
    KEPT   Loading state
    KEPT   Pull to refresh
    KEPT   Kit-colour stripe on list rows, mapped from kit membership
    KEPT   Assignee shown on rows (showAssignee: true)

### Item detail — EquipmentDetailView

    KEPT   Photo, and the "No Photo" placeholder
    KEPT   Status badge and condition badge
    KEPT   Category, serial number, description, notes, purchase price, purchase date
    KEPT   Kit membership — "Part of kit: X"
    KEPT   Current assignment: who has it, permanent or due date, red when overdue,
           check-in notes
    KEPT   Assignment history
    KEPT   Check Out — ONLY when status is available
    KEPT   Request Equipment — ONLY when checked out AND not to you
    KEPT   Report Damage — always
    KEPT   "Equipment Not Found" error view
    MOVED  The photo is no longer a 250pt block above everything. Status, who has
           it and when it is due now lead; the photo is a thumbnail that opens.
           You almost always already have the object in your hands.

### The four forms

    KEPT   CHECK OUT: item summary, employee picker (gated on equipment .edit,
           defaults to "Me"), Permanent toggle, expected-return date picker
           limited to future dates, notes, Cancel/Confirm, submit lock, error row
    KEPT   CHECK IN: optional kit header, PER-ITEM return condition picker seeded
           with the item's current condition, return notes, kit vs individual
           paths, Cancel/Check In
    KEPT   REQUEST: item summary, who currently holds it and until when, "when
           needed" and "return by" pickers with the return bounded by the start,
           reason (REQUIRED — Submit stays disabled without it), the explanation
           of the approval process, Cancel/Submit
    KEPT   DAMAGE REPORT: item summary, description (REQUIRED), severity picker
           with colour dots and per-severity explanation, up to FIVE photos with
           removable thumbnails, the submitting overlay with its per-photo
           progress text, Cancel/Submit
    OPEN   The four forms are mocked as their entry points and their shape, not
           field by field — they are Form sheets and Ambient does not change what
           a Form is. AMB.3 restyles them in place.


## TASKS

### List — TasksMainView, TasksViewModel

    KEPT   Search across title AND description
    KEPT   All five filters: All, My Tasks (default), Today, Urgent, Completed
    KEPT   Live counts on the chips — and NO count on All, which is deliberate
           (taskCount returns nil for .all)
    KEPT   The real filter semantics, which are not what they look like:
             All        excludes completed
             My Tasks   assignedTo contains you, excluding completed
             Today      due today, excluding completed
             Urgent     priority urgent OR OVERDUE, excluding completed
             Completed  only completed
    KEPT   Status chip row, shown only when the filter is not All, with its
           "Status:" label and an All option
    KEPT   The sort: priority descending, then due date ascending, then newest
    KEPT   FIVE DISTINCT EMPTY STATES — icon, message and subtitle all differ per
           filter ("You're all caught up!", "Tap + to create your first task"…)
    KEPT   Loading state
    KEPT   Create task (+)
    KEPT   The overflow menu: Refresh, Clear Cache
    KEPT   Tap a row to open the detail SHEET (not a push)
    KEPT   Checkbox toggles completion, and re-opens a completed task
    ADDED  The list is now GROUPED by when — Overdue, Today, This week, Later,
           No date — inside whatever filter is active. Today you discover
           something is late by driving a chip bar. The filters all still work.
    ADDED  A failure banner. Tasks publishes an error, four places set it, and NO
           view has ever read it, so every failure is silent. Flagged on screen.

### Row — TaskRowView

    KEPT   Completion checkbox, green when done
    KEPT   Priority bar
    KEPT   Title, two lines, struck through when completed
    KEPT   Status badge, due date (red when overdue), subtask count, comment count
    KEPT   Warning glyph for urgent and high
    KEPT   Relative dates — Today / Tomorrow / Yesterday / short date

### Detail — TaskDetailView

    KEPT   Priority badge, status badge
    KEPT   Watch star (and it is a TODO in the app — it renders and does nothing)
    KEPT   Due date, red when overdue
    KEPT   Subtask progress bar with count and percentage, green at 100%
    KEPT   Description, rendered from HTML (tags stripped)
    KEPT   Edit mode with Save: description editor, priority segmented picker,
           status menu picker, estimated-hours stepper (0–100, step 0.5)
    KEPT   Subtasks: toggle, and add/delete while editing, plus their empty state
    KEPT   Comments: author, relative time, body, ATTACHMENTS with file name,
           size and an image/doc glyph; add a comment
    KEPT   Comments empty state
    KEPT   Activity tab — kept AS A STUB. It says "coming soon" in the app and
           quietly mocking a real one would propose work nobody has costed.
    KEPT   Close and Edit/Save
    MOVED  The four-tab picker is gone. Details, subtasks and comments are one
           scrolling screen; a task with three subtasks and two comments does not
           need tab navigation. Activity stays, at the bottom, still a stub.
    ADDED  Session and workflow context. TaskItem carries sessionId, workflowName
           and workflowStepName and NOTHING renders any of them — a task attached
           to a job cannot show you the job.
    OPEN   Title is not editable after creation in the app. Left as-is.
    OPEN   CreateTaskView is not mocked. AMB.5 restyles it in place.


## CHAT

### Conversation list — ConversationListView

    KEPT   Avatar, name (bold when unread), preview (two lines), time, unread pill
    KEPT   Group avatar is a two-person glyph; direct is initials
    KEPT   Media-typed previews — Photo, File, GIF, Link — detected by sniffing
           the URL, plus the "You: " prefix
    KEPT   "No messages yet", in italic, when a conversation has none
    KEPT   Pinned: pin glyph and a distinct row treatment, pinned sorted first
    KEPT   Swipe leading: Pin / Unpin
    KEPT   Swipe trailing: Delete, GROUPS ONLY — a direct message cannot be swiped
           away, and that asymmetry is deliberate
    KEPT   Search conversations by name
    KEPT   New conversation → pick people → if more than one, name the group
    KEPT   Empty state with its "New Conversation" button
    KEPT   Loading state, pull to refresh, error alert
    MOVED  The pinned row's 10% orange wash becomes an orange hairline. Under D11
           the page already carries a colour, and a second full-row tint on top of
           it reads as a rendering fault rather than as emphasis.
    OPEN   Avatar colour uses abs(id.hashValue), which is seeded per process — the
           same person is a different colour after every relaunch. The mockup uses
           AmbientStyle.stableHash, which fixes it. Bug fix, not redesign.

### Thread — MessageThreadView

    KEPT   Own messages right and tinted, others left on a light fill, 60pt gutter
    KEPT   Sender name in groups only, never for your own
    KEPT   SYSTEM MESSAGES, centred in a capsule: "X added Y to the group",
           "X removed Y", "X left the group"
    KEPT   GIF, image and file messages, detected from the URL
    KEPT   Tap an image to open it full screen
    KEPT   "Load earlier messages" with its spinner
    KEPT   Pull to refresh
    KEPT   Scroll to bottom on new messages and on appear
    KEPT   Composer: expanding field (1–5 lines), emoji panel, GIF picker, photo
           picker, file picker, send button that spins while sending and is
           disabled when empty
    KEPT   "Uploading…" overlay
    KEPT   Overflow menu: Conversation Settings, View Profile (direct only, and a
           TODO in the app), Refresh Messages
    ADDED  Date separators, and grouping of consecutive messages from one person.
           Both are presentation only. Offered as switches so the operator can see
           the scrollback with and without.
    ADDED  A 15pt message body. The app has NO font modifier on a message, so it
           rides on the 17pt default while its own timestamp is 11pt.
    OPEN   Reactions are dead code — MessageReactionsView is referenced only from
           inside its own file and is never rendered. Not mocked. Deleting it is
           AMB.6's call.
    OPEN   The known defects stay defects: a failed send silently removes the
           message, image and file upload always error, "Load earlier" pages the
           wrong direction, a realtime event discards paged history, and
           hasMoreMessages is forced true so the button never leaves. A redesign
           does not fix these and the mockup does not pretend otherwise.

### Conversation settings — ConversationSettingsView

    KEPT   Rename a group, with Save/Cancel
    KEPT   Participants with avatar, name, "(You)", email
    KEPT   Add participants
    KEPT   Remove a participant — groups with 3+ only, never yourself, with a
           confirmation naming the person
    KEPT   Leave group — groups with 3+ only, with confirmation
    KEPT   Delete conversation — groups only, with confirmation
    KEPT   Type and Created info
    OPEN   Mocked as an entry point, not screen by screen. It is a List of Form
           rows and AMB.6 restyles it in place.


## What this inventory changed about the mockups

Five things the first cut had actually WRONG, all found by reading rather than
by review:

    1. Equipment's filter row is categories AND statuses. The first cut had
       statuses only, so the category filters would have been lost.
    2. Equipment's three detail actions are CONDITIONAL. The first cut drew all
       three all the time, which is a different screen.
    3. Tasks' Urgent filter is "urgent OR overdue", not "urgent or high".
    4. Tasks has five distinct empty states. The first cut had one generic one.
    5. Chat has system messages. The first cut had none at all.

None of those are style. All five would have shipped as feature loss.

# Batch 1 research — Equipment, Tasks, Chat

Written 2026-07-25 at the end of AMB.2's second session, so the three remaining
batch-1 mockups can be built without re-reading eight thousand lines of Swift
first. Every number here came from reading the actual files, not from inference.

DELETE THIS FILE once batch 1 is converted (AMB.6 closes the batch). It is
research scaffolding, not a plan — AMBIENT_ROLLOUT_PLAN.md is the plan.


## Where AMB.2 got to

Done and committed: the design system, the card-drift gate, the lab harness, the
specimen sheet, the D11 palette (approved and APPLIED to FeatureTheme), and the
home dashboard mockup.

Still to build, and the reason this file exists: mockups for EQUIPMENT, TASKS
and CHAT. All three are screens the operator has never seen, so AMB.3 must not
start until Equipment's is approved — a row specimen inside the specimen sheet
is not the D10 gate.

Locked decisions these mockups must honour:

    compact is the density for dense lists (D5, operator 2026-07-25)
    the wash is the feature's colour (D11) — Equipment #00A2C7, Tasks #E93D82,
      Chat #D6409F, all now live in FeatureTheme
    the home dashboard runs its wash at 90 percent; these three have not been
      judged for intensity yet, so start at full and let the operator dial it
    everything goes through .ambientCard — the gate blocks anything that does
      not, and DesignLab is exempt so a mockup may prototype a treatment the
      primitive cannot yet express (promote it into AmbientCard before the real
      screen is converted)


## EQUIPMENT  (AMB.3, next)

16 files. Container is EquipmentTabView: a NavigationStack with a two-way
segmented picker, My Kits and All Equipment, plus a 56pt blue circular QR button
floating bottom-right. MY KITS IS THE DEFAULT TAB, not the equipment list.

THE LIST. AllEquipmentView, over systemGroupedBackground: a hand-rolled search
field (padding 10, systemBackground, radius 10), a horizontal row of filter
chips (padding h12 v6, radius 20, blue at 20 percent when selected), then a
ScrollView with a LazyVStack at spacing 12 and 16pt padding all round.

THE ROW, EquipmentCard, which the specimen sheet already proposes a replacement
for:

    a 4pt kit-colour stripe down the leading edge, present only for kit items
    a 60 by 60 photo at radius 8, or a systemGray5 placeholder with a camera
    the name at .headline, one line
    the category at .caption, then the condition as an 8pt coloured dot with
      its label in SECONDARY grey — the condition colour appears only in the dot
    the serial as "SN: 3421887065" at .caption2
    "Currently checked out" at .caption2, only when checked out
    a trailing status pill: .caption, white on the status colour, h8 v4, radius 12

    padding h12 (h8 when the stripe is present) and v10; card is systemBackground
    at radius 12 with a shadow of black 5 percent, radius 4, offset y2; about a
    92pt pitch including the 12pt gap

SCALE. There is NO pagination and NO fetch limit anywhere in the feature. The
list renders every item the organisation owns, and all filtering is client-side
over the whole array. This is why the density question was decided by scrolling.

STATUS VOCABULARY, exact hexes from EquipmentModels.swift:

    available #22c55e   checkedOut #3b82f6   needsRepair #f97316   retired #6b7280
    excellent #22c55e   good #3b82f6         fair #eab308          poor #ef4444

STATES. Loading is a bare ProgressView plus "Loading equipment..." at .caption.
Empty is a 48pt tray glyph, "No Equipment Found" at .headline, and a conditional
"Try adjusting your search or filters" with a Clear Filters button. There is no
error view — errors are an alert.

DETAIL. A ScrollView of VStack spacing 20 over systemGroupedBackground: a 250pt
photo at radius 12, an info card of icon-label-value rows, a current-assignment
block when checked out, three actions (Check Out solid blue, Request Equipment
blue-tinted, Report Damage orange-tinted), and an assignment history rendered in
a NON-lazy ForEach.

CARRIED DEFECTS, report-only — a restyle does not fix these, but the mockup
should not pretend they are absent:

    no iPad adaptation anywhere in the feature; one single-column layout is
      stretched across a 12.9 inch screen
    CompactEquipmentCard exists and has ZERO call sites
    EquipmentStatus.icon exists and nothing renders it
    a no-op ternary in KitDetailView: isExpanded ? 10 : 10


## TASKS  (AMB.5)

9 files, 3,167 lines, 20 View structs. TasksMainView owns a NavigationView.

THE SCREEN. A hand-rolled search field, then a horizontal row of filter chips
(All, My Tasks, Today, Urgent, Completed — default is My Tasks) with live counts,
then a second conditional row of status chips, then the list.

THE ROW IS FLAT. TaskListView is a ScrollView plus LazyVStack at spacing 0; each
row is padding h16 v8 followed by a full-width Divider. There is NO card, NO
background, NO corner radius and NO shadow anywhere in the Tasks feature.
Converting to cards is therefore a real visual change, not a restyle of one —
show it as such.

    a completion checkbox at .title3, green when done
    a 3 by 16 priority bar
    the title at .body, up to two lines, struck through when completed
    a metadata row: status badge (.caption2, status colour at 20 percent, h6 v2,
      radius 4), due date Label at .caption in red when overdue, a subtask count
      like 1/3, and a comment count
    a trailing warning glyph only for urgent and high

    about 60pt for a one-line title, 81pt for two

NOT RENDERED IN THE ROW, though the model carries them: description, assignee,
attachments, task type, estimated hours.

COLOURS. Status todo grey, inProgress blue, completed green. Priority low grey,
medium blue, high orange, urgent red. That mapping is copy-pasted in FIVE places
plus two more in DashboardWidgets — a consolidation opportunity for AMB.5.

DETAIL is a SHEET, not a push: a NavigationView with a segmented picker over
Details, Subtasks, Comments and Activity. The Activity tab is a stub reading
"Activity feed coming soon". The title is not editable after creation.

CARRIED DEFECTS, report-only:

    NO error UI at all. The view model publishes an error, four places set it,
      and no view ever reads it. Failures are silent.
    no iPad adaptation; on iPad the NavigationView will default to a two-column
      split, which is likely a visible bug worth showing the operator
    filteredTasks is recomputed two or three times per body pass, and the chip
      counts scan the whole array four more times
    selectedPriority is declared and passed to the filter but no UI ever sets it
    TaskPreviewRow in DashboardWidgets is a near-duplicate of the row and IS a
      card; it will visibly diverge unless AMB.5 updates it too


## CHAT  (AMB.6, the hardest test of compact)

15 files, 4,655 lines.

THE CONVERSATION LIST. A List with PlainListStyle, .searchable, swipe actions
for pin and delete, and navigation via a hidden NavigationLink in the list's
background. The row:

    a 50pt circle avatar, colour hashed from the conversation id across six
      colours, showing initials or a two-person glyph for groups — no photos
    the name at .headline, bold when unread
    the last message at .subheadline, up to two lines, with emoji-typed previews
      for GIFs, photos and links and a "You: " prefix
    a relative timestamp at .caption
    an unread count as a white-on-blue pill at radius 12
    pinned rows get an orange pin glyph and a 10 percent orange row wash

    padding .vertical 8; roughly 82 to 90pt per row

THE THREAD. ScrollViewReader plus ScrollView plus LazyVStack at spacing 8.

    bubble: padding h12 v8, radius 16, no tail
    mine is Color.blue with white text; theirs is systemGray5 with primary text
    a 60pt minimum gutter on the opposite side
    sender name at .caption, only in groups, and NOT suppressed for consecutive
      messages from the same person
    a timestamp at .caption2 UNDER EVERY SINGLE MESSAGE
    the message body has no font modifier at all, so it rides on default .body

WHAT THE THREAD DOES NOT HAVE, all verified absent: message grouping, date
separators, read receipts, typing indicators, and any avatar in the thread.

The two biggest levers on scrollback density are therefore the per-message
timestamp line and the 17pt body against an 11pt caption.

MEDIA. GIFs render through a WKWebView EACH, fixed at 250 by 250 regardless of
real aspect ratio, with a fake spinner that dismisses on a one-second timer.
Images are AsyncImage at maxWidth 250, radius 16. Files show the literal word
"File" rather than a filename.

THE INPUT BAR. A TextField with vertical axis and lineLimit 1 to 5 in a
systemGray6 capsule at radius 20, padding h12 v8; a 32pt send glyph; a 28pt plus
button that expands into attachment, photo, GIF and emoji buttons; bar padding
h16 v8, separated by a Divider with no shadow.

RADII IN USE ACROSS THE FEATURE: 4, 8, 10, 12, 15, 16, 20. The only shadow is
on the emoji panel.

CARRIED DEFECTS, report-only, and these are the worst of the three surfaces:

    a failed send REMOVES the message from the thread and the thread has no
      alert, so it vanishes silently with no retry
    image and file upload are not implemented at all — both paths always end in
      an error, so only GIF sending works
    "Load earlier messages" pages the WRONG DIRECTION: the query orders ascending
      and walks the offset forward from the oldest message
    any realtime event replaces the message array with the first 100 ascending,
      discarding everything loaded by paging
    hasMoreMessages is forced true on every load, so the button never goes away
    the reactions UI is dead code — it mutates local state only and its only
      consumer is never rendered
    no iPad adaptation; the shell forces a stack style, so a thread runs
      full-width on a 12.9 inch screen with 60pt gutters
    ChatMessageContent prints to the console on every render of every bubble


## What a good batch-1 sitting looks like

All three screens plus the dashboard, on a device, in one go — that was the point
of batching them. The questions worth putting to the operator:

    can you scan Equipment at compact on row ninety
    do Tasks becoming cards read as better or busier than today's flat rows
    does a chat scrollback survive compact, and is the per-message timestamp
      worth the height it costs
    do the four feature washes read as four different places, or as noise

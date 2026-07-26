# AMB.5 parity inventory — Tasks

Every capability of the Tasks surface, read out of the SOURCE and marked kept,
moved, added or open. Written before any real screen was touched.

WHY THIS EXISTS SEPARATELY FROM AMB_BATCH1_PARITY.md. That document has a Tasks
section and it was written in AMB.2, from the mockup outward. This one is written
from the eight source files inward, and AMB.3 and AMB.4 both proved that is a
different exercise: AMB.3's walk caught three feature losses INSIDE a design the
operator had already approved, and AMB.4's inventory itself missed one, which the
audit then caught. An inventory is a check, not a guarantee.

SOURCE READ, in full: TasksMainView (464), TasksViewModel (310), TaskDetailView
(569), CreateTaskView (194), TaskModel (370), TaskService (439), TaskCacheService
(270), CommentModel (239), CommentService (316).

THE APPROVED DESIGN is DesignLab/Mockups/TasksMockup.swift, signed off on iPhone
and iPad on 2026-07-25 as part of batch 1.


## Four things the approved mockup does not carry, found by this walk

These are not style differences. Each one is a capability that exists in the app
today and has no home in the design as drawn.

1  EDIT MODE LOSES THREE OF ITS FOUR EDITORS. The app's detail, in edit mode,
   offers a description TextEditor, a priority SEGMENTED PICKER, a status MENU
   PICKER, and an estimated-hours STEPPER bounded 0 to 100 in steps of 0.5.
   AMB_BATCH1_PARITY.md lists all four as kept. The mockup's editing state draws
   only the description editor and the subtask add-and-delete affordances —
   priority, status and estimated hours have no editor in it at all. Since the
   mockup moved priority and status up into header badges, a reader of the mockup
   would reasonably conclude they are display-only.
   RESOLUTION: all three editors are restored, in the converted detail, in edit
   mode. This is the AMB.3 lesson repeating exactly.

2  THE TOOLBAR IS ABSENT. The lab supplies its own navigation bar, so the mockup
   drew no toolbar and could not show one. The real screen's toolbar carries three
   things: the Home button, the plus that opens Create Task, and an overflow menu
   holding Refresh and Clear Cache. All three survive. Recorded because a mockup
   scope artifact and a dropped feature look identical at conversion time.

3  THE SESSION NAME IS NOT REACHABLE, so it is not drawn. The mockup's row and its
   "Belongs to" card show a session by NAME — "Lincoln High — Fall Portraits" in
   the sample data. TaskItem carries sessionId and nothing else about the session:
   an opaque uuid, no name, no school, and no join anywhere in TaskService. Showing
   a raw uuid would be worse than showing nothing.
   RESOLUTION, and it follows AMB.3's precedent of naming a gap rather than faking
   it: workflowName and workflowStepName ARE on the model and cost nothing, so the
   workflow half of "Belongs to" ships in full and is real. The session half is not
   drawn. Making it real needs a sessions read that Tasks does not have, and adding
   one is a data-layer change D12 puts out of scope for this phase. It is named
   here and in the closeout rather than quietly dropped.

4  ASSIGNEE NAMES NEED A LOOKUP, AND THE LOOKUP ALREADY EXISTS. The mockup shows an
   assignee by name on a row that is not yours, and again in the detail's "Assigned
   to" line. TaskItem carries assignedTo as an array of user ids.
   RESOLUTION: names come from TeamService.shared, which already exists, already
   publishes teamMembers, and is already used by other screens in this app. It is a
   single-table read of users filtered by organization_id, and TeamMember carries
   id, fullName and photoURL — exactly what the design needs. No schema change, no
   RLS change, no PowerSync rule, nothing that touches the web app or Captura. That
   is what separates this from finding 3: this is a presentation join over a
   service the app already owns, not a new data path. Where a name cannot be
   resolved the model's own assignmentDisplayText is the fallback, so the line
   degrades to "3 assignees" or "Unassigned" rather than to blank.


## List — TasksMainView, TasksViewModel

    KEPT   Search across title AND description
    KEPT   All five filters: All, My Tasks (the default), Today, Urgent, Completed
    KEPT   Live counts on the chips, and NO count on All — deliberate, because
           taskCount(for: .all) returns nil
    KEPT   The real filter semantics, which are not what their names suggest:
             All        excludes completed
             My Tasks   assignedTo contains you, excluding completed
             Today      due today, excluding completed
             Urgent     priority urgent OR OVERDUE, excluding completed
             Completed  only completed
    KEPT   Status chip row, shown only when the filter is not All, with its
           "Status" label and an All option
    KEPT   The sort, exactly: priority descending, then due date ascending, then
           createdAt descending. NOTE the mockup's own sort is shorthand — it sorts
           by priority then by id and its comment claims otherwise. The app's real
           three-key sort is what ships.
    KEPT   Five distinct empty states — icon, headline and subtitle all differ per
           filter ("You're all caught up!", "Tap + to create your first task", …)
    KEPT   Loading state
    KEPT   Create task, from the toolbar plus
    KEPT   Overflow menu: Refresh, Clear Cache
    KEPT   Tap a row to open the detail as a SHEET, not a push. Turning a sheet
           into a push is a navigation-shape change and D2 and D3 keep that out.
    KEPT   Checkbox toggles completion, and re-opens an already-completed task
    KEPT   The Home toolbar button — Tasks is a self-nav feature and supplies its
           own, inline, exactly as Equipment does
    KEPT   tabBarClearance applied INSIDE this screen's own navigation container.
           The mockup's own 96pt bottom padding is lab-local and is NOT ported;
           doubling them is the AMB.4 mistake.
    MOVED  The list is GROUPED BY WHEN — Overdue, Today, This week, Later, No date
           — inside whatever filter is active. The app's sort is preserved inside
           each group. Today the only way to discover something is late is to
           drive the chip bar to Urgent, which is "urgent OR overdue", so an
           overdue medium task sorts below urgent ones that are not late at all.
    ADDED  A search-specific empty state, so "nothing matches" is distinguishable
           from "this filter is empty"
    ADDED  A failure banner with a REAL Retry. Tasks publishes an error, four
           places set it, and no view has ever read it — every failure in this
           feature is silent today. The mockup drew Retry as static text; a dead
           control is precisely what AMB.3 had to fix three of, so it is wired.
    OPEN   selectedPriority is @State in TasksMainView and is passed into
           filteredTasks, but NOTHING in the app can set it — there is no priority
           filter UI. It is always nil. Not a loss, because it was never reachable.
           The view model keeps the parameter.

## Row — TaskRowView

    KEPT   Completion checkbox, green when done
    KEPT   Title, two lines, struck through when completed
    KEPT   Status badge, due date (red when overdue), subtask count, comment count
    KEPT   Warning glyph for urgent and high
    KEPT   Relative dates — Today / Tomorrow / Yesterday / short date
    MOVED  The priority spine is REMOVED (operator, 2026-07-25 — it did not read
           right on a card). Priority reaches the row only through the trailing
           glyph, which fires for urgent and high, so low and medium are no longer
           distinguishable in the list. Acceptable because grouping by WHEN already
           carries the urgency the spine was competing to express, the in-group
           sort is still by priority, and the detail still badges it.
    ADDED  A red hairline on an overdue card, and the receded card state on a
           completed one
    ADDED  The assignee, on a task that is not yours (see finding 4)

## Detail — TaskDetailView

    KEPT   Priority badge, status badge
    CHANGED  Watch star. In the app it is a Button whose action is an empty TODO
           comment. It is now a non-interactive glyph with an accessibility label,
           still showing whether you are watching. NO BEHAVIOUR IS LOST — the old
           button did nothing when pressed — but a control that could be pressed is
           now an indicator, and that is a deliberate choice rather than an
           oversight: this project has fixed three dead controls in one previous
           phase, and drawing a fourth would be adding one back. Wiring it for real
           is a behaviour change D2 keeps out; TaskService.toggleWatch exists and is
           unused, so it is cheap whenever the operator wants it.
           (An earlier draft of this file claimed KEPT. That was wrong: the glyph
           was kept and the control was not.)
    KEPT   Due date, red when overdue
    KEPT   Subtask progress bar with count and percentage, green at 100%
    KEPT   Description, rendered from HTML with the tags stripped
    KEPT   Edit mode with Save: description editor, priority segmented picker,
           status menu picker, estimated-hours stepper 0 to 100 step 0.5
           (see finding 1 — three of these are absent from the mockup)
    KEPT   Subtasks: toggle, and add and delete while editing, plus their empty
           state
    KEPT   Comments: author, relative time, body, and ATTACHMENTS with file name,
           size and an image-or-document glyph; add a comment
    KEPT   Comments empty state
    KEPT   Activity — kept AS A STUB. It says "coming soon" in the app and quietly
           mocking a real one would propose work nobody has costed.
    KEPT   Close, and Edit / Save
    KEPT   Created date and time
    MOVED  The four-tab picker is gone. Details, subtasks and comments are one
           scrolling screen; Activity stays, at the bottom, still a stub.
    ADDED  Workflow context — "Belongs to" (see finding 3 for why the session half
           is not drawn)
    ADDED  Assigned-to line (see finding 4)
    OPEN   Title is not editable after creation in the app. Left as-is.

## Create — CreateTaskView

    KEPT   Title field, description editor, priority menu picker with its colour
           dots, the Set Due Date toggle and its date-and-time picker, the
           estimated-hours stepper, add and delete subtasks, the explanatory
           footer, Cancel, and Create disabled until a title is typed
    OPEN   There is no assignee picker and no status picker — a new task is always
           assigned to its creator and always starts at To Do. Unchanged.
    NOTE   Restyled in place, per AMB_BATCH1_PARITY.md, which recorded that this
           screen was never mocked.


## Defects in the surface, and what happens to each

L5 in the plan says expect one or two pre-existing bugs per surface, fix the ones
INSIDE the surface, name them, and do not let them expand the phase.

FIXED, because the redesign makes each unavoidable rather than optional:

  A SUBTASK TICKED OUTSIDE EDIT MODE IS SILENTLY THROWN AWAY. SubtasksTabView's
  checkbox is not gated on isEditing, and it mutates the local editedTask copy.
  Only Save persists that copy, and Save only exists in edit mode — so tapping a
  subtask checkbox while not editing animates, changes the count and the progress
  bar, and loses the change on dismiss. The old four-tab layout hid this behind a
  tab; the converted single scroll puts subtasks in front of everyone. Same class
  as the three dead controls AMB.3 fixed.

  EVERY REFRESH ADDS ANOTHER SUBSCRIPTION. TasksViewModel.startIncrementalListener
  opens a sink on TaskService.$tasks and stores it, and fetchAllTasks calls it
  every time — which means every Refresh, every Clear Cache, every task created,
  and every checkbox toggled. Nothing cancels the previous one until onDisappear.
  So after ten toggles in one visit there are eleven sinks, and each realtime
  delivery runs the merge and writes the whole task list to disk eleven times.
  Fixed by cancelling before re-subscribing.

  A NEW TASK IS CREATED WITH AN UPPERCASE UUID. TaskItem's default id is
  UUID().uuidString with no lowercasing, while Subtask's is lowercased and
  duplicate() lowercases too. CreateTaskView relies on that default. The repo's
  hard rule is lowercase everywhere, because Postgres normalises on store and
  Swift string comparison does not — so the optimistic local copy TaskService
  appends can never string-match the row that comes back. Fixed at the default.

NAMED, NOT FIXED, because they are data-layer or behaviour and D12 keeps those out:

  startIncrementalListener takes an afterTimestamp parameter and never uses it.
  The cache computes a latest timestamp, passes it in, and the function ignores it
  and subscribes to everything — so the "incremental" listener is a full listener.
  Harmless today, and rewriting it is a data-layer change.

  TaskService.updateTaskFields is private, unreachable from outside, and its body
  admits it does nothing but bump updatedAt. Dead code in a file this phase does
  not own.

  TaskService carries eleven TODO markers for activity logging and notifications —
  TASK_CREATED, TASK_COMPLETED, notify watchers, auto-stop time tracking. None of
  it is implemented. That is why the Activity tab is a stub, and it is a feature
  nobody has costed, not a defect this phase can close.

  TaskDetailView's Save does not bump updatedAt on the copy it hands back;
  TaskService.updateTask sets it server-side. So the local row is briefly stale in
  its timestamp only. No visible effect, and touching it is a data change.


## What the audit round found, in my own work

Two adversarial passes were run over the conversion before it was committed. This
section exists because PUB.1 and AMB.4 both learned the same thing the hard way:
the round that audits THE FIX is where the worst defect turns up. Nine findings
were accepted and fixed; two were rejected with a reason.

WORST FIRST — A CASUAL CHECKBOX WAS OVERWRITING THE WHOLE TASK ROW. My fix for the
thrown-away subtask tick routed through onTaskUpdated, which writes the ENTIRE task
from editedTask — a snapshot taken when the sheet opened. So ticking a subtask
would have silently reverted any title, status, priority or assignee change made by
somebody else since the sheet opened, on a database shared with the web app. The
irony is that the comment above the code named TaskService.toggleSubtask, which
re-reads the row and writes only that subtask, and the code did not call it. It
does now, with an optimistic local flip that reverts if the write fails. A fix that
introduces a data-loss path is worse than the dead control it replaced.

THE SCREEN CONTRADICTED ITSELF ABOUT WHAT IS LATE. TaskWhen.band tested
isDateInToday BEFORE the past test, so a task due at 09:00 today, read at 17:00,
filed under a "Today" header while its own date rendered in red with a warning
triangle — because TaskItem.isOverdue is simply dueDate < now. Reordered to test
the past first, so the band, the chip count and the red styling all read the same
comparison. Verified with a throwaway harness across eleven date cases: the band
and isOverdue now agree on every one. Both harnesses were deleted.

THE CHIP COUNTS WENT STALE AT MIDNIGHT. I had cached them on a tasks didSet, but
two of the four read the clock — "Today", and the overdue half of "Urgent". Left
open overnight the chips would have disagreed with the list they filter. Counts are
now computed in the same single pass as the grouping, from one captured clock, so
they cannot drift from the rows or from each other. Still one walk per render
instead of the old seven.

PRIORITY WENT INVISIBLE IN THE COMPLETED FILTER. The mockup gated the urgent/high
glyph on not-done. Combined with the approved removal of the priority spine, that
left rows in the one filter that shows nothing but completed tasks with no priority
signal at all — the old row carried both the spine and the glyph. The glyph is now
ungated. A deliberate deviation from the approved mockup, because the operator
approved removing the spine, not making priority unreadable.

"CREATED" DISAPPEARED WHEN YOU TAPPED EDIT. The first cut swapped the whole Details
card for the three editors. The old four-tab detail rendered the created date in
both modes. The facts that are not editable now stay on screen in both.

THE TASK TITLE DISAPPEARED WHEN YOU SCROLLED. The mockup sets a static
navigationTitle of "Task" and puts the real title in the header card — which
scrolls away, so on a task with a few comments nothing on screen said which task
you were in. Restored to the task's own title, as the app had it. Deliberate
deviation from the mockup.

THE FAILURE BANNER WAS PERMANENT. Nothing but the user's own Retry or Dismiss ever
cleared the error, so one failed fetch left a warning sitting over data that had
since arrived. A successful load now clears it.

THE COMMENTS SHOWN COULD BELONG TO ANOTHER TASK. CommentService is a singleton with
one shared comments array, so opening task B showed task A's comments until B's
fetch landed — permanently when offline. Pre-existing, but the redesign puts a
COUNT in the section title, which turns a flicker into a wrong number sitting on
screen. TaskComment carries taskId, so it is now filtered exactly.

TWO Task BLOCKS WROTE VIEW STATE OFF THE MAIN ACTOR. sendComment and the member-name
load both assign to @State from a bare Task, which inherits no actor. Both are
Task { @MainActor in } now.

THE SUBTASK PLUS WAS DECORATION. The old screen's plus was a real Button, disabled
while the field was empty. My composer drew it as an Image and put the action behind
a text button that only appeared once you typed. It is a Button again.

REJECTED, WITH REASONS:

  THE TOAST FIX WAS REVERTED RATHER THAN SHIPPED, and this is the finding I got
  wrong myself. I claimed in AMB_SHELL_INVENTORY.md that every toast in the app
  draws 34pt inside the floating bar's footprint, from comparing its 50pt bottom
  padding against TabBarMetrics.clearance of 84pt. Those two numbers are not
  measured from the same datum — one is plain padding on an overlay, the other a
  safe-area inset — and the toast grows upward from its padding. Then the audit
  found the part that settles it: two of the three call sites are shell-wrapped
  features that ALREADY receive the shell's 84pt inset, so adding padding inside
  them would double-count. Whether a toast is actually clipped needs one look on a
  device. ToastView is now behaviourally identical to HEAD with a comment recording
  exactly this. Shipping an unverified layout change to app-wide chrome is the
  precise mistake AMB.4 made four times, and every wrong version of it built
  cleanly.

  THE OVERDUE-AT-MIDNIGHT BUSINESS RULE STAYS AS IT IS. Same call AMB.3 made about
  the equipment version of it: what the app considers "late" is a business rule that
  pre-dates this arc, and a style phase does not change it.

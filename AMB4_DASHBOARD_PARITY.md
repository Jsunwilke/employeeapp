# AMB.4 parity inventory — the home dashboard

Written 2026-07-25, at the start of AMB.4, before any real screen was touched.

Batch 1's inventory (AMB_BATCH1_PARITY.md) covered Equipment, Tasks and Chat. It
did NOT cover the home dashboard, even though the dashboard's mockup was approved
in the same sitting. So this file is the missing half, written the same way: every
capability below was read out of the actual source — MainEmployeeView.swift and
DashboardWidgets.swift — not from the screen, not from the approved mockup, and
not from memory.

That distinction is the whole lesson of AMB.3, and it is worth restating because
this phase is where it gets tested a second time: AN APPROVED MOCKUP IS A DESIGN
DECISION, NOT A CAPABILITY INVENTORY. AMB.3's parity walk found three feature
losses INSIDE a design the operator had already signed off. This walk found more
than three.

Marks:

    KEPT      present in the approved mockup, in some form
    MOVED     present, but somewhere else — the new home is named
    ADDED     not in the app today; a deliberate proposal
    MISSING   IN THE APP, NOT IN THE MOCKUP. Feature loss unless AMB.4 restores it.
    OPEN      a defect or question the conversion has to rule on

DELETE THIS FILE when AMB.4 closes.


## The surface

    Iconik Employee/MainEmployeeView.swift      1,420 lines   the home shell
    Iconik Employee/DashboardWidgets.swift      2,229 lines   seven widgets

Drift-gate rows to delete at the close of this phase (scripts/check_card_drift.py):

    Iconik Employee/DashboardWidgets.swift|AMB.4|8
    Iconik Employee/MainEmployeeView.swift|AMB.4|2

AllFeaturesView.swift is NOT this phase's — the gate assigns it to AMB.12, and
that is where it stays. Home only owns the row that pushes to it.


## THE FINDING THAT CHANGES THE SHAPE OF THIS PHASE

THE iPAD DASHBOARD IS A COMPLETELY DIFFERENT SCREEN, AND IT HAS NO MOCKUP.

MainEmployeeView picks the widget set by device (loadWidgetOrder, reading
DashboardWidget.iPhoneWidgets vs iPadWidgets):

    iPhone      Hours · Mileage · Upcoming Shifts · Tasks
    iPad        Sports Rosters · Group Jobs · Photoshoot Notes

Not a superset. Not a reflow. Three different widgets, sharing nothing with the
four the operator approved. An iPad user's home screen has no hours, no mileage,
no shifts and no tasks on it at all.

The approved DashboardMockup draws the iPhone four. There is one dashboard entry
in the lab gallery and it has no iPad variant. So:

  - D10 (nothing is converted before the operator has seen a mockup, ON A DEVICE)
    is unmet for three of this surface's seven widgets.
  - D7 (every phase smokes on iPhone AND iPad) cannot be satisfied by converting
    only the four, because the iPad would smoke an unconverted screen.
  - The gate row for DashboardWidgets.swift cannot be deleted with three of its
    eight cards unconverted, so AMB.4 would not close its own allowlist entry.

RESOLVED FROM THE PLAN'S OWN PROCEDURE, not by asking: D10 says a rejected or
missing mockup is cut in the lab, "where it costs minutes." So AMB.4 mocks the
three iPad widgets in the lab, the operator approves them on an iPad, and only
then are they converted. The iPhone four are already approved and are converted
without waiting.

A note on why this was not caught earlier: the batch-1 mockups were built from
AMB_BATCH1_RESEARCH.md, which described how screens LOOK. A device-conditional
widget list is not something a screen shows you.


## MainEmployeeView — the home shell

### Container and navigation

    KEPT     Home lives in its own NavigationView (StackNavigationViewStyle),
             per NAV.1's one bar per screen. NOT changed by this phase (D3).
    KEPT     Profile toolbar, trailing: first name, avatar (SupabaseAvatarView
             when a photo URL exists, else a person glyph), and a menu with
             Settings / Appearance / Design Lab / Logout
    KEPT     Design Lab menu entry — TEMPORARY, deleted at AMB.12, not here
    KEPT     Theme picker sheet: System / Light / Dark with a checkmark on the
             active one, and Done. Writes appTheme and applies it immediately.
    KEPT     Push to SettingsView
    KEPT     Push to ShiftDetailView for a tapped shift, carrying allSessions
             (not just the upcoming three) and crewHidden: false
    KEPT     Toast on the ShowReportSuccessToast notification
    OPEN     THREE NavigationLink(isActive:) can be live on this one view at
             once — settings, design lab, and the session push. AMB.3's review
             flagged exactly this shape as the AMB.1 dead tap, and its rule is
             ONE push per view. The session link is built conditionally, so at
             rest there are two. This phase collapses them behind one enum
             destination and one link.

### The flag banner

    KEPT     Realtime flag status: a postgres_changes channel on users filtered
             to this user id, plus an initial fetch. Reads is_flagged, flag_note,
             flagged_by, photo_url; resolves flagged_by to a first name; and
             opportunistically refreshes the stored avatar URL from the same row.
    KEPT     THE BANNER RENDERS TWICE, and both are real: flagNotificationView
             sits inline at the top of the scroll, and flagNotificationBanner is
             a separate bottom overlay in the shell's ZStack with an x to dismiss.
             Dismissing hides only the overlay; the inline one stays.
    KEPT     The whole page background turns red at 30% opacity while flagged
    KEPT     Banner dismissal resets whenever the flag status changes

### Widgets area

    KEPT     Widget order is USER-REORDERABLE BY DRAG, with a per-device saved
             order (dashboardWidgetOrder / iPadDashboardWidgetOrder in
             AppStorage). onDrag + onDrop + WidgetDropDelegate, animated move,
             saved on every reorder.
    MISSING  The mockup draws a fixed VStack in a fixed order with no drag
             affordance and no reorder. This is the single largest capability on
             the shell and the mockup has none of it. AMB.4 keeps the drag.
    KEPT     Unknown/removed widget ids in the saved order are dropped, and
             newly added widgets are appended rather than lost
    OPEN     loadWidgetOrder runs only from onAppearActions, so the widget SET is
             chosen once per appear. An iPad entering a narrow split view flips
             isIPad but keeps the old set until the view re-appears. Pre-existing;
             this phase recomputes it on a size-class change.

### The All Features row

    KEPT     A row with a grid glyph, the words All Features and a chevron,
             pushing AllFeaturesView with the view model, tab manager and role

### Pull to refresh

    OPEN     THE HOME SCREEN'S PULL-TO-REFRESH IS ATTACHED INSIDE THE SCROLL
             VIEW. MainEmployeeView.swift line 881 puts .refreshable on the inner
             VStack; the ScrollView closes on line 884. The arc's own converted
             reference, ScheduleView.swift line 202, puts it on the ScrollView
             itself. A RefreshAction reaches a scroll view through ITS OWN
             environment, and the environment flows down, so a child cannot
             install one on its parent.
             Treated as a defect inside the surface being converted (plan L5),
             fixed by moving the modifier onto the ScrollView, and called out
             here so the operator can confirm on device that pulling down on
             home now refreshes. NOT asserted as proven-dead: it is proven
             MISPLACED, and the fix is correct either way.

### Dead code

    OPEN     CompactSessionRow (MainEmployeeView.swift:429, ~120 lines) has ZERO
             references anywhere in the app. It is a near-duplicate of
             CompactShiftRow in DashboardWidgets.swift, carrying the same broken
             colour lookup. git log -S confirms its last caller went away in
             88d3a0e. Checked against the AMB.2 lesson (zero callers measured
             against an already-degraded shipped state is not the same as dead):
             its twin CompactShiftRow is live and renders the same content, so
             nothing is lost. Deleted in the conversion commit.


## HoursWidget

    KEPT     Header: clock glyph on a yellow disc, the words Hours Tracking
    KEPT     Clock in / clock out button in the header, showing the live elapsed
             time while clocked in, red when clocked in and green when not
    KEPT     Clock IN opens SessionSelectionView (pick a session + notes)
    KEPT     Clock OUT opens NotesInputView (notes, isClockOut: true)
    KEPT     A one-second timer driving the live elapsed figure, invalidated on
             disappear
    KEPT     This Week progress against 40h
    KEPT     Pay Period progress against 80h
    KEPT     The active (currently-running) entry drawn as a lighter overlay on
             top of logged hours, and only added to the total when it is not
             already included in the fetched entries
    MISSING  THE OFFLINE INDICATOR. When timeTrackingService.isUsingOfflineData
             is true the header shows an icloud.slash glyph, the word Offline,
             and how long ago the last sync was. The mockup has no offline state
             at all. This is payroll data on a phone that works in school
             basements — it is the last thing that should quietly vanish.
             RESTORED.
    MISSING  OVERTIME. Past 40h the week bar splits into a blue regular segment
             and an ORANGE overtime segment, and the readout adds "+Xh XXm OT".
             The pay-period bar does the same and adds "(Xh XXm OT)". The
             mockup's meter is a single-tint capsule that clamps at the target,
             so an employee in overtime sees a full bar and no number. RESTORED.
    MISSING  The percentage readout shown when there is no overtime and nothing
             running ("78%"). RESTORED.
    MISSING  The loading state (a centred spinner while the first fetch runs,
             suppressed when cached values exist). RESTORED.
    KEPT     Instant first paint from UserDefaults-cached hours, and the cache
             being cleared when the pay period rolls over
    OPEN     Data layer untouched (D12): the pay-period fetch, the overtime
             breakdown, the two-second settings fallback and the caching all stay
             exactly as they are.

## MileageWidget

    KEPT     Header: car glyph, the word Mileage
    KEPT     View All, pushing MileageReportsView for this user
    KEPT     Pay-period miles as the headline number
    MISSING  ITS CAPTION. Corrected after audit — this line originally read
             "KEPT" and was wrong. The old widget captioned all three buckets
             (Pay Period / This Month / This Year); the approved mockup drew the
             headline number bare, and porting that faithfully left the only
             unlabelled figure on the widget sitting directly above two labelled
             ones, which makes it read as a grand total. RESTORED.
             Worth recording as the phase's own worked example: the inventory
             caught sixteen losses and still missed this one, because the line
             was written about the NUMBER and the thing that went missing was
             its LABEL. An inventory is a check, not a guarantee.
    KEPT     Pay-period reimbursement in green
    KEPT     Personal / Company split, SHOWN ONLY when the split has company
             miles (mileageViewModel.currentPeriodSplit.hasCompany). The mockup
             draws both pills unconditionally.
    KEPT     This Month and This Year miles
    MISSING  THE DOLLAR AMOUNTS ON MONTH AND YEAR. The app shows a green
             reimbursement figure under each of This Month and This Year; the
             mockup shows miles only. On a screen whose whole job is "what am I
             owed", dropping two of the three money figures is feature loss.
             RESTORED.
    MISSING  The caption "Enter mileage via Daily Job Reports". It is the only
             place the app tells you where mileage comes from — the widget is
             read-only and there is no other affordance. RESTORED.
    MISSING  The loading state. RESTORED.
    KEPT     Cold-start estimate: before the vehicle-aware split loads, dollars
             are estimated from cached miles at the personal rate so miles and
             money appear together instead of a bare $0.00

## UpcomingShiftsWidget

    KEPT     Header: calendar glyph, the words Upcoming Shifts
    KEPT     Up to three shifts, keyed by dayOccurrenceKey so a multi-day session
             yields one row per day without an id collision
    KEPT     Tapping a row opens ShiftDetailView
    KEPT     School name
    KEPT     Start and end times
    KEPT     The multi-day "Day N of M" badge
    MISSING  THE REFRESH BUTTON in the header, which calls loadSchedule().
             RESTORED.
    MISSING  "View All (N shifts)", pushing ScheduleView, shown only when there
             are more than three. The widget lists three; the fourth shift is
             otherwise unreachable from home. RESTORED.
    MISSING  THE DATE. The widget spans today, tomorrow AND the day after — the
             view model filters to a three-day window — and every row carries
             "E, MMM d" for exactly that reason. The mockup's row shows times
             only, on sample data that reads as one day. This is the same shape
             as AMB.3's missing YEAR in assignment history: sample data that all
             sits in one bucket hides the field that tells the buckets apart.
             RESTORED.
    MISSING  WEATHER. Each row shows a condition glyph in its condition colour
             and the temperature, fed by a whole weather pipeline in the view
             model — batched by location and date, capped at five lookups,
             staggered 100ms apart, cached by a location-date key. The mockup has
             none of it. A photographer checking tomorrow's outdoor sports shoot
             is exactly who this is for. RESTORED.
    MISSING  The loading state (spinner). RESTORED.
    MISSING  The empty state — a calendar.badge.exclamationmark glyph, "No
             upcoming shifts", and the caption "Next 2 days". RESTORED, with the
             caption corrected: the filter is a THREE-day window (startOfToday to
             startOfToday + 3 days), so "Next 2 days" has always been wrong by a
             day. Corrected wording, not a behaviour change.
    KEPT     Today's already-finished shifts are hidden (a session whose start
             plus an assumed two hours is in the past drops off). Business rule,
             untouched (D12).
    ADDED    Session type PILLS and a CREW AVATAR STACK, from the schedule's
             vocabulary. The widget shows one type badge and no crew today.
    OPEN     THE COLOUR RAIL IS BROKEN TODAY, and fixing it is the reason this
             widget is in batch 1. CompactShiftRow paints its rail from
             positionColorMap[session.position]. Verified in source:
             Session.position returns session_types.first (a session TYPE id such
             as "sports" or "underclass"), while positionColorMap is keyed by JOB
             TITLES ("Photographer 1", "Delivery", "Yearbook Team"). The lookup
             misses, the inline fallback map is keyed by job titles too and also
             misses, and the row falls through to .blue. Nearly every shift on
             the dashboard is blue regardless of the colour the scheduler chose.
             The converted row uses ScheduleStyle.accent(for:), which is the
             scheduler's session_color — the same source the converted schedule
             already reads. That is what makes the front door agree with the
             schedule, which is this phase's stated reason for existing.

## TasksWidget

    KEPT     Header: checklist glyph on a green disc, the word Tasks
    KEPT     Up to FIVE tasks assigned to you, excluding completed
    KEPT     The sort: overdue first, then priority descending, then due date
             ascending, then newest created
    KEPT     Per row: completion checkbox, title, status badge, due date (red
             with a warning glyph when overdue), subtask progress, and the
             urgent/high exclamation glyph
    KEPT     Relative dates — Today / Tomorrow / Yesterday / short date
    KEPT     Empty state: a check glyph, "No tasks", "You're all caught up!"
    KEPT     Loading state
    KEPT     View All, which switches the tab to Tasks
    MOVED    The priority colour spine is removed from the row, matching the
             decision already taken for the Tasks screen (operator, 2026-07-25).
             Priority still reaches the row through the urgent/high glyph.
    MISSING  THE CREATE TASK BUTTON (a green plus in the header) and its
             CreateTaskView sheet. The mockup's header carries only "View all".
             RESTORED.
    MISSING  THE CHECKBOX ACTUALLY WORKING. The mockup draws a static circle;
             in the app it toggles completion through the view model. RESTORED.
    MISSING  TAPPING A ROW OPENS TaskDetailView AS A SHEET (not a push), with an
             update callback into the view model. RESTORED, and it stays a sheet
             — Tasks' own screen does the same, and changing it here would make
             two screens disagree about what a task tap does.
    MISSING  The five-row limit. The mockup shows three. RESTORED to five.


## iPad widgets — NO APPROVED DESIGN, mocked in this phase

Inventoried here so the mockups are drawn from the source rather than from the
screen, and so the operator's approval is against a known list.

### SportsRostersWidget

    Header: sportscourt glyph, "Sports Rosters", and View All which switches the
      tab to sportsShoot
    Up to three of TODAY's non-archived shoots for the organisation, sorted by
      time; a "N more rosters" line when there are more
    Per row: a sport-specific glyph derived by keyword from the sport name
      (basketball, football, soccer, baseball/softball, tennis, golf, swim,
      track/cross country, volleyball, else sportscourt), the school name, the
      sport name, the shoot time, and a route indicator
    THE ROUTE INDICATOR IS LOAD-BEARING: a shoot with a galleryId shows a bolt
      and the words FP Sports and opens the Focal Point Sports view; one without
      shows a court glyph and the word View and opens the Captura view. The same
      tap goes to two different tools depending on that field.
    Loading state; empty state ("No sports rosters today")
    Cancels its load task on disappear and on backgrounding, and reloads when the
      app returns to the foreground

### ClassGroupsWidget

    Header: three-people glyph, "Group Jobs", and a filled purple Add Jobs button
      opening CreateClassGroupJobView seeded with type classGroups
    Today's jobs for the organisation, sorted by time, three shown
    Per row: school name, time, group count with the JOB-TYPE-SPECIFIC noun
      (ClassGroupJobType.countNoun / countNounPlural — singular and plural both
      handled), an orange "No <plural> added" when the count is zero, an image
      count when non-zero, and a job-type badge
    Tapping a row sets both the selected job id AND its type on the tab manager,
      so the Groups screen opens on the right segment, then switches tab
    "View All (N jobs)" clears both selections before switching tab
    Loading state; empty state with its own Add Group Jobs button
    Refreshes after a job is created

### PhotoshootNotesWidget

    THE ONLY WIDGET IN THE APP THAT EDITS DATA IN PLACE. It is a note editor, not
    a summary, and any redesign has to keep it one.
    Header: note glyph, "Photoshoot Notes", a plus that creates a note, and an
      expand button opening the full PhotoshootNotesView in a sheet with Done
    A horizontal strip of up to five notes, newest first, each 120x70: time,
      photo count when non-zero, a SYNC STATUS DOT (green submitted / blue synced
      / orange pending), school name or "No school", and two lines of the note
    Selection state on the strip (blue tint and a blue border)
    Below the strip, for the selected note: a school Picker with a loading state
      while schools are fetched, a TextEditor bound live to the note, a character
      count, a photo count label, and a delete button
    Every edit writes straight through to the AppStorage-backed note list
    A new note's school is auto-filled from TODAY'S FIRST SESSION when the
      schedule and the school list are both loaded
    Empty state with its own Add Note button
    Re-fetches today's schedule when the app returns to the foreground


## THE BOTTOM TAB BAR — added to AMB.4 by the operator, 2026-07-25

"It should be now in this phase. It should be with the main screen and before any
other feature."

The bar was in NO phase. The arc's phase list is organised by FEATURE, and the
bar is nav-shell furniture from NAV.1 that sits on every screen, so it belonged
to nothing. The card-drift gate could not catch it either: a full-width bar is
not a rounded-and-filled container, so the rule that has been driving this arc's
file-by-file conversion is blind to it by construction. It surfaced only because
the operator asked why it had not changed.

    Iconik Employee/Navigation/BottomTabBar.swift        570 lines
      BottomTabBar, TabBarButton, TabButtonStyle, TabBarConfigurationView
    Iconik Employee/Navigation/Models/TabBarItem.swift   243 lines
      TabBarItem, TabBarConfiguration, TabBarManager  (data — NOT restyled)

### THE D11 PALETTE NEVER ACTUALLY REACHED THE BAR

AMBIENT_ROLLOUT_PLAN.md's D11 says FeatureTheme has three live consumers —
MainEmployeeView, AllFeaturesView and BottomTabBar — and that re-cutting the
palette in AMB.2 "changes the home screen's tile colours and the bottom bar
immediately". THE BOTTOM BAR HALF OF THAT IS NOT TRUE, and it is verified rather
than suspected: FeatureTheme appears in BottomTabBar.swift exactly once, at line
569, inside TabBarConfigurationView — the CUSTOMISE screen, not the bar.

The live bar colours itself from TabBarButton.accentColor (lines 322-333), a
FOURTH hardcoded feature-colour map that the audit roadmap's design-token work
never found. It covers seven ids and defaults everything else to blue:

    timeTracking cyan · chat blue · scan orange · photoshootNotes purple
    dailyJobReport green · sportsShoot indigo · equipment cyan · else BLUE

So the tile you tap and the bar item you land on disagree for nearly every
feature — Tasks is not even in the map, so its bar item is blue while its tile is
#E93D82. That is precisely the drift D11 was written to eliminate, surviving in
the one file nobody assigned to a phase. Converting the bar closes it.

### Capabilities — read from the source

    KEPT   TWO DIFFERENT LAYOUTS BY DEVICE, and they are genuinely different
           screens, not a reflow (the same trap as the dashboard widgets):
             iPhone — items split left/right around a PERMANENT centre Scan
               button; up to 6 items besides Scan
             iPad   — NO Scan at all (getScanItem returns nil on iPad, because
               iPads have no NFC); a prominent centre HOME button instead; up
               to 10 items
    KEPT   The iPad Home button: a 78pt circle with a 44pt house, its LAYOUT
           height capped at 44pt and bottom-aligned so the circle overflows
           UPWARD above the bar without making the bar taller
    KEPT   The iPad top hairline NOTCHES around that circle — a 92pt gap so the
           line does not cut across it. NAV.1 shipped this deliberately.
    KEPT   Left and right groups each take half the width on iPad so Home stays
           dead centre whatever the item count; odd counts put the extra item
           on the left
    KEPT   Scan's icon deliberately OVERFLOWS its circle (60pt glyph, 50pt
           circle) — the code says so explicitly and says a house at that size
           would clip, which is why iPad Home is drawn differently
    KEPT   Per-item selected state: tinted icon, tinted label, and a 20x3
           sliding underline that travels between items via matchedGeometryEffect
    KEPT   Icon sizes 24pt iPhone / 30pt iPad / 60pt Scan
    KEPT   Optional labels, driven by configuration.showLabels — 10pt iPhone,
           12pt iPad, minimumScaleFactor 0.8
    KEPT   Press feedback: scale to 0.85, spring; selected icons sit at 1.1
    KEPT   Haptics — light for a normal tab, MEDIUM for Scan and for iPad Home
    KEPT   Badges: a red count capsule capped at "99+", and a dot — GREEN when
           the badge is .active (clocked in) and red otherwise
    KEPT   Badge wiring: chat shows the unread count, timeTracking shows the
           clocked-in dot
    KEPT   accessibilityLabel = title, accessibilityHint = description
    KEPT   The whole bar hides during a full-screen overlay (owned by
           MainEmployeeView, not the bar)
    KEPT   Customise screen (TabBarConfigurationView): pick up to N features,
           reorder by drag, add/remove with +/- buttons, live "N of N selected"
           counter that turns red at the cap, "Scan is always included" note on
           iPhone, saves immediately on every change

### The first mockup was REJECTED, and it deserved to be

Operator, 2026-07-25: "hate it. not really any different. why not do a real glass
ios 26 design? or better yet, look at the bottom bar from my keepup app on the
desktop. its a custom glass bar that can hold more than the official glass bar."

They were right, and the diagnosis matters more than the rejection. The first cut
swapped an opaque background for a material and changed NOTHING ELSE — same
full-bleed rectangle welded to the bottom edge, same fixed-width cells, same
underline. It restyled a shape nobody had questioned. That is exactly the failure
D12 was written about: I had a scope rule about code and turned it into a ceiling
on the design, on the one surface in the app that is visible from every screen.

The second cut is PORTED FROM THE OPERATOR'S OWN APP —
~/Desktop/KeepUP/KeepUp/App/GlassSegmentedTabBar.swift, read end to end rather
than described from its name. What it actually does:

    A FLOATING CAPSULE, inset 14pt from the sides and 6pt off the bottom, 60pt
      tall, with a real shadow under it — not a bar welded to the screen edge.
    REAL LIQUID GLASS on iOS 26: .glassEffect(.clear, in: Capsule()).
    A PILL IT ANIMATES ITSELF, and this is the load-bearing detail: A MATERIAL
      OR A GLASS EFFECT CANNOT ANIMATE ITS POSITION, so a glass pill that slides
      cannot be got from the system at all. KeepUp hand-builds it — accent at
      30%, a top-down white sheen for specular depth, a bright white rim — and
      slides it with an explicit ease. Their file records that they tried the
      native UISegmentedControl indicator first: it slides, but its indicator is
      a flat solid fill with no glass, its timing is not tunable, and its UIKit
      host composited OVER the SwiftUI pill at rest.
    NEIGHBOURS PART around the selection, by 7/distance, decaying outward.
    WIDTH DIVIDED BY COUNT — which is the operator's "holds more than the
      official glass bar". The system TabView caps at five; this divides the
      capsule by however many items there are. It also removes the 438pt
      overflow, because cells stop being a fixed 50pt.

Adapted rather than copied, and each one is a decision this app has already
taken:

    THE PILL TAKES THE SELECTED FEATURE'S COLOUR. KeepUp has one amber; this app
      has 27 distinct feature colours since AMB.2, and under D11 a feature's
      colour means something. So the pill changes hue as it travels and agrees
      with the tile that was tapped to get there.
    SCAN AND iPAD HOME KEEP A DEDICATED CENTRE SLOT. NAV.1 made Scan permanent
      and prominent on iPhone and gave the iPad a centre Home instead, because
      iPads have no NFC. Flattening either into an ordinary cell would discard a
      navigation decision, not a style.

      REVISED TWICE after the operator saw it, 2026-07-25.

      First: "center the scan button vertically on the bar. and dont let other
      icons flow behind it." The original floated the circle above the capsule's
      top edge while the cells divided the full width underneath, so items passed
      behind it — the cell maths did not know the button existed.

      Then: "the scan button should always be center. and should be larger than
      all other icons." BOTH WERE STILL WRONG, and the first is the interesting
      one. Splitting the row with the extra item on the left — which is what the
      LIVE bar does — leaves the slot off-centre by half a cell whenever the count
      is odd: about 30pt right of the middle at five items on an iPhone. So the
      live bar has never actually centred its Scan button on an odd count either.

      Now: both sides take an EQUAL half of the non-button width, sized for
      whichever side holds more items, and the lighter side centres its cells
      inside its half. Cell widths stay uniform and the button sits on the bar's
      midpoint at every count. Every element is positioned from one array of cell
      origins — the same numbers the pill uses — because laying it out with nested
      stacks and spacers is what let the two halves drift apart.

      Verified numerically, not by eye: button centre equals bar centre to the
      decimal at 2-6 items on three iPhone widths and 2-10 on iPad, with no cell
      under the button, none outside the bar, no overlaps, and the pill inside the
      capsule for every selection.

      SIZE, after a third round ("larger by at least 30%"): the glyph is 52pt
      against 17pt for every other icon — three times the size — in a 56pt disc
      inside a 76pt slot. The capsule grew to 68pt (KeepUp's is 60) to contain it
      with 6pt clear above and below, because it has to stay centred INSIDE the
      glass rather than breaking its edge.

      FROST IS 50% (operator, 2026-07-25). It was first shipped as a fixed
      `.glassEffect(.regular)`, which was too much; rather than guess again the
      mockup got a slider and the operator returned a number. The base is the
      clearest glass each OS gives and the dial adds diffusion behind it, so the
      value transfers between iOS 26 and the pre-26 fallback. It becomes a
      constant in the real bar — no control ships.

      THE TWO BARS ARE NOW ONE BAR (operator, 2026-07-25: "the ipad bar should be
      exactly like the iphone except the scan button is a home button"). Today they
      are genuinely different — different icon sizes, a notched hairline on iPad, a
      centre Home on one and a centre Scan on the other. In the proposal they share
      the capsule, the height, the cell maths, the 17pt icons, the 52pt centre
      glyph and the frost. What remains different is only what the app's behaviour
      requires:
        - the centre button's DESTINATION (Scan on iPhone, Home on iPad — iPads
          have no NFC, which is why Scan does not exist there);
        - its colour: Home takes the company blue because it is the container
          rather than a feature, exactly as the dashboard's wash does;
        - the item cap the device allows (6 vs 10, from getMaxItemsForDevice);
        - a 560pt width cap on iPad so the row stays phone-sized instead of
          sprawling across a 13-inch screen. That is KeepUp's own number and it
          lands in the same place: ten items on iPad give 45.6pt cells against
          45.2pt for six items on a 375pt iPhone, so the two bars are the same
          DENSITY and not merely the same design.
      One deliberate symbol swap to make them match: the iPad centre uses
      `house.circle.fill` rather than the live `house.fill`. Scan's symbol is a
      filled circle that fills its disc at 52pt; a plain house at that size is a
      wide, short glyph that would either clip or float, and the buttons would not
      read alike. One line to revert.
      ONE CONSEQUENCE, named: today's Scan glyph is 60pt on a 50pt circle, a
      deliberate overrun that worked because the button stood proud of the bar.
      Centred inside the capsule an overrun would spill past the glass, so the
      glyph nearly fills its disc instead of exceeding it.
    THE iOS 16.6 FLOOR IS HONOURED (D4). Real Liquid Glass is iOS 26 only, so
      below it the capsule is custom glass — material, sheen, rim — written to
      stand on its own rather than as a degraded afterthought. The toolchain is
      Xcode 26.6 with the iOS 26.5 SDK, so the API compiles; KeepUp's own floor
      is 17.0, which is why it needs no equivalent fallback.

### IT FLOATS — SETTLED, and my cost estimate for it was wrong

A floating bar means content scrolls UNDER it. That is what gives glass something
to refract and is the entire reason the look works — a glass bar over a flat page
is a tinted panel. It also means the bar stops participating in layout: today the
shell is `VStack { mainContent; BottomTabBar }`, so the bar owns its strip and no
screen has to think about it.

DECIDED by the operator, 2026-07-25, with the question that settles it: "what
would be the point of glass if the bar reserved its own space?" None. So it floats.

I TOLD THEM IT WOULD COST "ABOUT TWENTY SCREENS OF BOTTOM-INSET WORK". That was
pessimistic enough to have skewed the decision, and it is worth recording as a
process failure rather than quietly correcting: I estimated from the number of
screens instead of checking whether a single mechanism covers them. The real shape,
measured:

    27 root feature screens in MainEmployeeView.featureView, plus home.
    Only TWO files pad for the bar today — home (100pt, which already clears the
      capsule) and TimeTrackingButton.
    `safeAreaInset(edge: .bottom)` applied ONCE where the shell wraps a feature
      insets every one of them: content rests above the bar and still scrolls
      beneath it. THE APP ALREADY USES THAT MODIFIER, in DailyJobReportView.
    Only THREE places opt out of the bottom safe area, and one is the shell
      itself, one is the already-converted shift detail, one is keyboard-only.

So: one shell change plus spot-checks. The spot-checks are the real work, and they
are not cosmetic — a Save or Submit button pinned to the bottom of a form becomes
untappable, which is a bug rather than a blemish. The form-heavy screens (daily
job report, time off, the equipment forms) are the ones to walk.

### SWIPE TO TUCK — the operator's idea, and it replaces hide-on-scroll

Operator, 2026-07-25: "swipe the bar to the right in sports mode to hide it and it
left a small half circle with chevron to slide it back out."

Swipe the bar right and it slides off the edge, leaving a half-circle handle with a
chevron; tap it or swipe it left and the bar returns. The distinction from
hide-on-scroll is the whole point: the app never takes navigation away, the person
puts it away deliberately, and the way back is always on screen. That answers the
NAV.1 objection instead of arguing with it.

GOING HOME BRINGS IT BACK (operator, 2026-07-25: "if i use the home button from
the top tab bar, it should auto slide back out"). The rule is broader than the
button: the bar un-tucks whenever the SELECTED TAB CHANGES, and
`HomeToolbarButton` works by setting `selectedTab = "home"`. So the same rule
covers a dashboard widget's "View all" or anything else that navigates. A tuck is a
momentary "get out of my way", not a setting that outlives the screen it was made on.

AN ASYMMETRY THAT MAKES THE HANDLE LOAD-BEARING ON iPAD, found while checking that
button rather than assumed. `HomeToolbarButton` is iPHONE ONLY — its own comment
says so, because on iPad Home is the bottom bar's prominent centre button and a
top-nav Home would be redundant. Consequence: on iPad, from any feature screen,
THE BOTTOM BAR IS THE ONLY ROUTE HOME. Tuck it and the handle is not a convenience,
it is the sole navigation. So the handle can never be dismissible, can never be
covered by a sheet, and has to be comfortably hittable one-handed — and that is
doubly true of the Sports idea below, where the whole point is working with the bar
tucked for long stretches.

A REAL DEFECT THE HOME BUTTON EXPOSED, fixed in the mockup: the sliding pill parked
on the FIRST CELL whenever the current screen was not in the bar. That is the common
case rather than an edge — the app has 27 features and the bar holds at most six, so
any of the other twenty-one, plus Home itself on iPhone, leaves nothing in the row
selected. The pill was confidently pointing at the wrong screen. It now hides when
nothing matches, which the conversion has to carry.

### THE BAR IS ABSENT FROM THE SPORTS ROSTER ON iPAD, and that is what makes the
### tuck worth having

Verified, not assumed: `CapturaSportsView.onAppear` sets
`TabBarManager.shared.isFullScreenOverlayActive = true` when the idiom is iPad,
commented "Hide tab bar when in roster view (iPad) to maximize vertical space", and
clears it on disappear. `FPSportsRosterView_iPad` does the same. So on iPad there is
NO bottom navigation at all in the app's largest tool. On iPhone the bar is only
hidden while the photo viewer is up.

The operator's point follows: a bar that can be tucked away by hand does not need to
be taken away by the screen, so Sports could have one again.

THREE CONSTRAINTS BEFORE THAT CAN HAPPEN, all of them real, none of them mine to
wave through:

  1. `CapturaSportsView.swift` IS A HOOK-PROTECTED CAPTURA FILE. Changing when it
     hides the bar means editing it, which needs explicit in-conversation operator
     authorization. `FPSportsRosterView_iPad.swift` is NOT protected.
  2. D1 PUTS SPORTS PERMANENTLY OUT OF THIS ARC. The bar itself is shell code and is
     squarely in AMB.4, but making it appear inside Sports is a change to Sports'
     behaviour and needs a ruling, not an inference.
  3. THE ORIGINAL REASON WAS GOOD. Vertical space on a roster is not a style
     preference — it is rows of athletes visible at once during a live shoot. The
     tuck has to be provably easy to reach and re-hide before anyone gives that
     space back, and the person to judge that is the operator on an iPad at a shoot.

RECOMMENDED as a follow-on with its own smoke rather than folded into AMB.4: build
and prove the tuck here, on surfaces this phase already owns, and let Sports adopt
it as a separate, authorized change.

### HIDE ON SCROLL — TRIED, AND DROPPED

Operator, 2026-07-25: "could this have the same behavior as facebooks bottom tab
bar? if i scroll down the bar slides down out of view but as soon as i pull up, it
slides back up."

Asked for, built, and then dropped — by the operator, who resolved the design
question rather than the bug: "still doesnt work and you are right. navigation is
more important." That was the concern I had raised when they asked for it: NAV.1
made Home permanently reachable and Scan permanently present, Facebook is a feed
where navigation is incidental, and this is a work tool where Scan is the
most-tapped button on the bar.

DELETED rather than left switched off, along with the on-screen probe I added to
debug it. An experiment that has lost its argument is not scaffolding worth
carrying, and a disabled toggle invites re-litigating a settled decision.

TWO THINGS WORTH KEEPING FROM IT, because they cost real time to learn:

  1. IT FAILED SILENTLY FOR A REASON WORTH REMEMBERING. The offset reporter was a
     GeometryReader inside a `.background(...)`. `.background` and `.overlay` build
     a SECONDARY view hierarchy, and preferences set there do not reliably reach an
     ancestor — so `onPreferenceChange` was never called and the bar simply never
     heard about the scroll. Nothing about the direction logic was wrong. Moving the
     reporter to a real child fixed the plumbing; the operator reported it still not
     working on their device before they dropped the feature, so the second cause
     was never diagnosed and the honest state is UNRESOLVED, not fixed.

  2. I SHOULD HAVE INSTRUMENTED FIRST. I shipped an untested interaction and asked
     the operator to discover it did nothing, then added an on-screen probe only
     after they reported it. The rule already existed for exactly this shape of bug
     ("nothing happens", multiple plausible causes) and I applied it a round too
     late. Worse, I cannot run this surface myself — reaching the design lab needs a
     signed-in session against the shared Supabase project — so every guess costs
     operator time rather than mine. When I cannot see it run, the probe goes in
     with the first version, not the second.

### Defects found while inventorying — REPORTED, not yet fixed

    1. THE iPHONE BAR OVERFLOWS THE SCREEN AT ITS OWN MAXIMUM.
       Buttons are a fixed 50pt, Scan is 70pt, and the spacers are minimums
       (10 + 20 + 20 + 10 = 60pt). At the 6 items getMaxItemsForDevice allows:
         6 x 50 + 70 + 60 + 8 padding = 438pt
       against 393pt on an iPhone 15/16 and 375pt on an SE. Five items already
       overflows an SE (388pt). The default configuration ships THREE items, so
       this only bites a user who customises — which the customise screen
       actively invites, and its counter cheerfully allows.
       Nothing shrinks: fixed widths and minimum-length spacers.

    2. A REDRAW HACK THAT KILLS THE SELECTION ANIMATION.
       Line 146: .id("bottomTabBar_\(chatManager.totalUnreadCount)").
       chatManager is an @ObservedObject and totalUnreadCount is @Published
       (ChatManager.swift:19), so the redraw it forces was already happening.
       What it DOES do is change the view's identity every time a message
       arrives, rebuilding the whole bar and discarding the matchedGeometryEffect
       namespace — so the sliding underline jumps instead of travelling, and
       every button is reconstructed, whenever the unread count changes.

    3. DEAD STATE AND DEAD CODE, all verified zero-caller:
         animateSelection — written in five places, read nowhere
         TabBarConfiguration.animateSelection — stored and persisted, read nowhere
         TabBarManager.getQuickAccessItemsForDevice() — no callers
         TabBarConfigurationView.deleteSelectedFeatures(at:) — no callers; the
           List has .onMove but never .onDelete, so swipe-to-delete was wired
           only halfway. Removal still works through the minus button, so no
           capability is lost by its absence.


## The code-review gate — five findings, four fixed, one recorded

Run by the operator 2026-07-26, before any push, over the whole 21-commit range.

FIXED:

  1. THE iPAD GLASS WAS THE WRONG WIDTH. The glass and shadow were applied after the
     centring frame, so the frosted panel spanned the full iPad screen while the
     buttons stayed inside the 560pt cap. A porting slip — the mockup already had the
     order right.
  2. THE HOURS BAR CONTRADICTED ITS OWN CAPTION. The week's split used banked hours
     while its caption used the total, so a running clock-in that pushed past 40 gave
     "+3h OT" beside a bar with no orange. I HAD SPOTTED THIS AND WRITTEN IT DOWN AS A
     DELIBERATE TRADE-OFF, which was the wrong call: a payroll bar disagreeing with
     its own label is worse than either version alone. Recording a defect is not the
     same as resolving it.
  3. EQUIPMENT RESERVED 168pt INSTEAD OF 84. Self-nav features were getting the
     clearance twice — once from the shell, once from themselves. Ignored by a legacy
     NavigationView but honoured by EquipmentView's real NavigationStack.
  4. FP SPORTS ON iPAD HAD ITS BOTTOM STRIP UNDER THE CAPSULE. It stopped hiding the
     bar and never got its own clearance. I had left this "for the device smoke",
     which was deferring a known break rather than a genuine unknown.

RECORDED, NOT PATCHED — the refresh latch can release on stale rows:

  `refreshUpcomingEvents` holds the pull control until the session listener calls
  back, but `startListeningToSessionsAsync` calls back TWICE: once replaying the disk
  cache, then again with the network result. The latch clears on the first, so the
  control could release over stale rows.

  IT CANNOT HAPPEN TODAY. `ScheduleCacheManager.loadMetadata()` decodes ISO-8601
  dates with a bare JSONDecoder and always fails, so the cache replay never fires —
  the same dormancy PUB.1 documented and the OFF arc exists to fix.

  NOT PATCHED, deliberately, and this is a judgement the operator should see rather
  than a shortcut. The available fixes are each worse than the bug: the view model
  cannot tell the two callbacks apart, so it would have to either count them (fragile
  against a future third call) or run its own fetch and duplicate the three-day
  window, the already-ended-today rule and the crew filter that the listener owns —
  duplicated business rules on payroll-adjacent data to fix a cosmetic early release
  of a spinner. `isUsingOfflineData` looks like the signal and is not: it is set from
  connectivity, so online it is false even for the cache replay.

  THE HONEST OWNER IS OFF.1, whose decision O5 is already about exactly this — a
  failed cache read must not look like an empty one. Whoever switches that cache on
  makes this live in the same commit, and should fix it there where it can be tested
  against a cache that actually decodes. Flagged in AUDIT_ROADMAP against OFF.1.

CLEARED BY THE REVIEW, worth recording because they were the phase's riskiest parts:
the `ambientPush` collapse of three live `NavigationLink(isActive:)` (no dead-tap
shape left), the refresh reentrancy guard and its bounded poll, every division in
HoursMeter, the day-boundary overdue rework and its tests, and the Codable change to
`TabBarConfiguration` (an older saved config still decodes).


## Step 3b — the converted screen against the approved mockup

The arc's workflow requires this pass by name, because it is where two defects
escaped in AMB.1: a day strip that scrolled in the lab and did not in the app,
and then the same strip at the wrong capsule width. Approving a mockup is not
verifying a build. Every difference between DesignLab/Mockups/DashboardMockup
and the shipped iPhone dashboard is listed below and is either RESTORED (the
mockup was missing something the app has) or NAMED as a deliberate change.

Ported verbatim, not re-derived: the widget header (26pt disc, 13pt semibold
glyph, 16% tint fill, .headline title), the card densities (roomy widget,
compact rows), the shift row's gutter-and-content shape, the mileage headline
(30pt bold rounded number, "mi", green money on the right), the task row, and
the All Features row.

DELIBERATE DIFFERENCES, each with its reason:

    The wash slider card is lab-only. It exists so the 90% can be argued with on
    a device; production takes the number.

    The clock button has a CLOCKED-OUT state. The mockup drew only the running
    state (a red stop pill). A design shows one state; the widget has two.
    Green, "Clock in", play glyph — and the wording is new: the live app showed
    a bare play icon with no label, which on a glass card reads as ambiguous.
    Called out because it is an ADDITION, not a restoration.

    The multi-day "Day N of M" marker sits in the PILL ROW, not as a badge
    beside the school name where the mockup drew it. Reason: the row now builds
    its pills through ScheduleStyle.pills(for:), the same single definition the
    schedule uses, which already appends that marker — drawing it in both places
    would duplicate it, and suppressing it there would fork the definition this
    phase exists to share. The headline also has weather in it now, which the
    mockup did not, so a third element beside the school would crowd at 15pt.

    The shift row's time gutter is 58pt, not the mockup's 52pt. The restored day
    label ("Today" / "Tomorrow" / "Wed 30") needs the width, and 58 is what the
    schedule's own row uses, so the two screens line up.

    Bottom padding is 100pt, not the mockup's 40pt. The lab has no bottom tab
    bar; the real screen does.

    The mileage Personal/Company pills are CONDITIONAL. The mockup drew both
    unconditionally; the app shows them only when there are company miles, so a
    photographer who only drives their own car is not shown a permanent
    "Company 0". The source won.

RESTORED — in the app, absent from the approved design (the seventeen MISSING
lines above). Each verified present in the converted code: the offline
indicator, the overtime segment and its OT text, the percentage readout, the
month and year dollar figures, the "Enter mileage via Daily Job Reports"
caption, the shift date, the weather, the refresh button, "View all (N shifts)",
the Tasks create button, the working checkbox, the task detail sheet, five task
rows rather than three, every loading state, every empty state, and widget
drag-reordering.

ONE WORDING CHANGE, deliberate: the empty shifts state said "Next 2 days". The
filter is startOfToday to startOfToday + 3 days. The caption was wrong by a day
and now says "next 3 days". The code was not changed to match the caption.

ONE AFFORDANCE DROPPED, deliberate: the old row ended in a trailing chevron; the
approved row does not. The row is still a Button, inside a bordered card, in a
list of tappable cards — the same signalling the converted schedule uses. Named
here rather than restored because it is the mockup's own call about how a
tappable card announces itself, and reversing it on one screen would make home
disagree with the schedule again.


## Found by the audits, fixed in this phase

Three of these are defects the CONVERSION introduced. Recorded as such rather
than folded quietly into the "restored" list.

    INTRODUCED, and it would have shipped: pull-to-refresh could hang the
      Upcoming Shifts widget permanently. fetchUpcomingEvents raised
      isLoadingSchedule BEFORE its "already have a listener" guard and then
      returned — and every reset of that flag lives past the return. Anyone with
      no upcoming shifts who pulled to refresh got a spinner in place of the
      empty state until the org changed a session or the app was backgrounded.
      Harmless while the only trigger was a refresh button that could not fire;
      a real hang the moment this phase made the gesture work. Guard moved above
      the flag.

    INTRODUCED: pull-to-refresh did nothing at all. Moving .refreshable onto the
      ScrollView made the gesture fire, but it called into that same guard and
      returned without a network round trip — a gesture that lies is worse than
      one that is inert. There is now a real refresh path, and the pull control
      is held until data actually lands rather than snapping back instantly.
      The widget's own refresh button had the same dead behaviour and now shares
      the working path.

    INTRODUCED, caught in the FIX round: the first version of that refresh
      called cleanup() before re-subscribing. cleanup() enqueues its unsubscribe
      on one detached Task while the re-subscribe is enqueued on another, so if
      the stop landed second it would have torn down the listener just created —
      the dashboard would have silently stopped receiving updates until the app
      was backgrounded. Removed: startListeningToSessionsAsync already
      unsubscribes the same subscription id before subscribing. This is the
      PUB.1 lesson repeating exactly — audit the fix round, because fixes
      written under audit pressure are not safer than the code they fix.

    PRE-EXISTING, inside the surface, fixed: HoursWidget could install an
      orphaned 1-second repeating Timer. Its .task awaits a network call that
      never checks for cancellation, so leaving home during that await ran
      onDisappear first (invalidating a still-nil timer) and then started a timer
      on a view that no longer exists, with nothing left to stop it. Now guarded
      on Task.isCancelled.

    PRE-EXISTING, inside the surface, fixed: returning to Home re-pushed
      whatever was last opened. The bottom bar stays live while a detail is
      pushed, so tapping a shift, switching to Tasks and coming back re-opened
      the detail with no user action. The destination is now cleared when the
      tab leaves home.

    PRE-EXISTING, inside the surface, fixed: the pushed ShiftDetailView was
      identified by session id, which a multi-day job shares across its rows, so
      opening day 1 then day 2 reused the view and kept day 1's loaded state
      under day 2's data. Now keyed by day occurrence — the identity
      ShiftDetailView documents for itself and ScheduleView already uses.

    INTRODUCED: the clocked-in band on the hours bar was drawn beyond the filled
      edge, onto the empty track, in white at 35% — invisible in light mode —
      and was suppressed entirely whenever overtime was showing. It is now a
      trailing slice OF the fill, so being clocked in reads in both cases. The
      overtime segment was also a separate offset capsule, which rendered a
      small overtime slice as a lozenge floating mid-bar; regular and overtime
      are now one continuous run clipped to a single capsule.


## The fix round was audited too, and that is where the worst defect was

PUB.1's closing lesson was "audit the fix round, because fixes written under
audit pressure are not safer than the code they fix." It held again, twice.

    CRITICAL, introduced by the FIRST fix: the stuck spinner came back through
      a different door. Making pull-to-refresh clear the listener flag meant a
      refresh once again reached "raise the loading flag", and there are real
      paths where the listener then never calls back at all — offline with a
      warm in-memory cache, or a failed fetch with a warm cache. The flag would
      stick, and because the re-subscribe sets hasActiveListener, no later fetch
      could clear it: a permanent spinner for the rest of the session, in place
      of the shifts list. A refresh now never raises that flag at all.

    HIGH, introduced: the wait loop ignored cancellation. Task.sleep throws
      immediately once cancelled and the throw was being swallowed, so
      navigating away mid-refresh turned a 100ms poll into a main-actor busy
      loop until the deadline. Now breaks on cancellation.

    HIGH, introduced: two controls call the refresh and nothing stopped them
      overlapping, which could orphan a realtime channel — the unsubscribe
      inside startListeningToSessionsAsync is real but not atomic with its
      subscribe, so a second run could find nothing to stop and then overwrite
      the first channel, leaving it live for the process lifetime. Guarded.

    MEDIUM, introduced: the hours bar made a FALSE claim about payroll data.
      The pay period's regular and overtime figures describe BANKED hours only,
      but the scale included the running entry — so the "still running" marker
      was drawn over hours that were already banked and clocked out. The bar is
      now three consecutive segments (banked regular, banked overtime, running),
      which cannot say anything untrue because nothing is inferred.

      Verified numerically across fifteen states rather than by eye: every state
      is non-negative and sums to at most one, and the 45-hour overtime case
      reproduces the old bar's 40/45 split exactly.

      ONE HONEST DIFFERENCE FROM THE OLD BAR, named rather than hidden: at 38
      hours banked with 4 more running, the readout says "+2h OT" while the bar
      shows no orange. The old bar attributed the running hours across the 40
      line and coloured them; this one does not, because none of that overtime
      has been banked yet. It resolves itself as soon as the entry is recorded.

    MEDIUM, introduced: at accessibility text sizes the readout could not fit,
      and because the label had been given layout priority it was the PAYROLL
      FIGURE that truncated first. Priority removed, and the readout stacks
      instead of shrinking past legibility.


## Recorded, NOT fixed — for the operator

    THE iPAD KEEPS A STALE WIDGET SET ACROSS A SIZE-CLASS CHANGE. loadWidgetOrder
    runs only from onAppear, and the widget SET is chosen by device, so an iPad
    entering or leaving Split View keeps whichever set it woke up with until the
    screen re-appears.

    This phase FIXED it and then REVERTED the fix, which is worth explaining. The
    fix was an onChange on the horizontal size class. It works, but crossing that
    boundary swaps four widgets for three, and each widget starts its own loaders
    and realtime channels in onAppear — one of them opens a fresh Supabase
    channel per construction and another has no teardown at all. So a one-line
    convenience fix turned an occasional cosmetic staleness into routine channel
    churn against the shared database, and made the orphaned-timer leak above
    trigger regularly. It is also not a parity item, not in the mockup, and not
    asked for.

    Reverted on the same reasoning AMB.3 used to refuse the overdue-at-midnight
    change: a style phase does not get to smuggle in a behaviour change, and this
    one needs the three iPad widgets' lifecycles fixed first. Follow-on candidate.

    CHAT IS NEVER CLEANED UP WHEN YOU LEAVE IT, and has not been for a long time.
    MainEmployeeView's tab-change handler reads
    "selectedTab == chat && newTab != chat" — but by the time an onChange action
    runs the published property has ALREADY been updated, so selectedTab equals
    newTab and the condition is self-contradictory. ChatManager.cleanup() has
    therefore never run. Found while working in the same closure. NOT fixed here:
    switching on a cleanup path that has been dormant for months, on a feature
    this phase has not researched, is exactly the unscoped behaviour change D12
    exists to prevent. AMB.6 owns Chat and should take it with a smoke test.

    THE THREE iPAD WIDGETS HAVE WEAK LIFECYCLES, found while assessing the
    size-class question. PhotoshootNotesWidget opens a fresh Supabase realtime
    channel per construction (its subscription id is a UUID on a View struct);
    ClassGroupsWidget has no onDisappear at all; HoursWidget's two-second
    settings fallback fires from destroyed views and writes the payroll cache.
    None is newly broken and none is on the iPhone path this phase converted.
    They matter for whichever phase makes the widget set change at runtime.


## What this inventory changed

Seventeen MISSING lines. Every one of them is in the app today and absent from a
design that was approved on a device. None of them is stylistic:

    the offline indicator, overtime, and the percentage on Hours
    the month and year dollar figures, and the how-to caption, on Mileage
    the date, the weather, the refresh, and View All on Upcoming Shifts
    the create button, the working checkbox, the detail sheet, and two of the
      five rows on Tasks
    every loading and empty state across all four
    widget drag-reordering on the shell itself

Plus three widgets that were never designed at all.

The mockup is not wrong for omitting most of these — a mockup is a design, and a
design shows the resting state. That is precisely why this file exists, and why
"the operator approved it" is not an answer to "does it still do what it did".

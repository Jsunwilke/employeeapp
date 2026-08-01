# AMB — Ambient design language rollout (iOS employee app)

Plan doc for the AMB arc. Registered in the family registry,
~/Brain/projects/registry.md (formerly FocalPointProduction/docs/PHASES.md). One phase per session.

Written 2026-07-24, after AMB.1 (the schedule) shipped and passed operator
smoke on device.


## What this arc is

The schedule now uses a design language the operator chose from five
prototypes: a live countdown to the next call time, glass cards over an ambient
wash tinted by the job in front of you, per-type icons and wrapping pills, and
three unmistakable states for a shift — done, happening now, still to come.

This arc carries that language through the rest of the app.

It is a REDESIGN arc with a parity constraint (D12, operator 2026-07-25, and it
SUPERSEDES the restyle-only framing this document opened with). A phase may
change layout, information architecture and the shape of a screen, and it may
not lose a feature. Data layers, services and business rules stay out of scope:
the schedule proved that pattern, where ShiftDetailView's presentation was
replaced entirely while every loader, listener and calculation in it stayed
byte-identical. What changed on 2026-07-25 is that presentation is now allowed
to be re-thought rather than merely re-skinned.

See D12 for what that means in practice, and AMB_BATCH1_PARITY.md for how the
"no feature lost" half is made checkable rather than promised.


## Why it needs a plan rather than a list of screens

Measured on 2026-07-24, before any conversion:

    273 Swift files, 292 View structs, about 124,000 lines

That number is misleading twice over, and both corrections shape the plan.

FIRST, most of it is not in scope:

    Sports Shoot Feature      53 views    36,352 lines   OUT OF SCOPE
    Schedule                  57 views    13,088 lines   DONE (AMB.1)
    Everything else          ~180 views  ~74,000 lines   the actual surface

Sports Shoot Feature is excluded deliberately and permanently for this arc. It
contains the hook-protected Captura files, and FP Sports is a live iPad tool
used during shoots where a restyle risks real work in progress. Restyling it is
a separate arc with its own risk posture, if it ever happens at all.

SECOND, the app is not 180 independent designs. It is a handful of patterns
copy-pasted:

    115 hand-rolled card backgrounds   across only 39 files
    307 ad-hoc cornerRadius calls
    166 hardcoded system-grey fills
     53 hand-tuned shadows
      0 adopters of cardStyle(), the shared card modifier already in
        DesignSystem/DesignTokens.swift

That last line is the most important fact in this document. A design system was
already built for this app during the audit roadmap's Phase 3, and NOTHING EVER
USED IT. The lesson is not "write a design system" — that was done and it
failed. The lesson is that a design system with no enforcement is decoration.

So AMB.2's deliverable is not a component library. It is a component library
plus a build-time gate that makes hand-rolling a card fail.


## Pre-decided (do not re-litigate mid-phase)

D1  SCOPE. Sports Shoot Feature is out. No exceptions inside this arc.

D2  STYLE PHASES DO NOT CHANGE BEHAVIOUR. No data, service, navigation-shape
    or business-rule changes inside a conversion phase. If a phase uncovers a
    real defect, it is fixed only when it is IN the surface being converted and
    it is called out in the closeout — as AMB.1 did with the Yearbook button's
    always-true nil test. Anything larger gets its own arc code.

D3  NAVIGATION STAYS AS IT IS. The shell hands most features a NavigationView
    (NAV.1, one bar per screen). This arc does NOT migrate to NavigationStack.
    Pushes go through the schedulePush wrapper in ScheduleStyleKit, which uses
    NavigationLink(isActive:) precisely because it is the only push API valid in
    both containers. A NavigationStack migration is NAV.2 if it is ever wanted.

D4  iOS 16.6 FLOOR HOLDS. Post-16 APIs go through the availability wrappers in
    the design system. No phase raises the deployment target.

D5  DENSITY IS SETTLED BEFORE ANY SCREEN IS BUILT ON IT. Ambient's glass and
    generous spacing suit a schedule with a handful of items a day. A 200-row
    equipment list or a chat thread in that style will feel slow and airy. Every
    primitive therefore needs a compact variant alongside the roomy one.

    The compact variants are DESIGNED in AMB.2, against Equipment's real code,
    and PROVEN in AMB.3 by converting Equipment itself. Only then does the home
    dashboard follow.

    CHOSEN 2026-07-25 (operator, from the specimen sheet's live density
    switch over a 24-item list): COMPACT is the density for dense lists.
    That settles D5 — AMB.3 converts Equipment at compact, and every later
    list surface follows unless it argues otherwise in its own mockup.

    SETTLED IN CODE 2026-07-25 (AMB.2), proven in AMB.3. Three densities, named
    for intent rather than numbered: hero is the one thing on the screen (18pt
    padding, 24pt radius), roomy is a browsable list of a handful of items
    (16pt, 22pt — what the schedule ships), compact is a list you scan rather
    than read (12 horizontal, 10 vertical, 14pt radius). Compact's numbers are
    taken from Equipment's REAL row, which is horizontal 12 vertical 10 at
    radius 12 today, so converting Equipment is a change of vocabulary and not a
    change of size. Density also drives type scale, avatar size, the gap between
    cards, and whether pills keep their icons.

    One fact found while measuring: Equipment has no pagination and no fetch
    limit, and filters client-side over the whole array. A real organisation's
    list is every item it owns. That is what the specimen sheet's long list is
    for — the density question is decided by scrolling it, not by looking at one
    row.

    Revised 2026-07-24, before any of it was built: the first cut of this plan
    put the dashboard at AMB.3 and Equipment at AMB.4 while also saying density
    was settled at AMB.4 — so the highest-traffic screen in the app would have
    been built on primitives that were about to change, and either invented its
    own compact treatments or been revisited. Two decisions in the same document
    that contradicted each other. Ordering Equipment first costs the dashboard
    one phase of waiting and removes the rework entirely.

D11 THE WASH IS THE FEATURE'S COLOUR, AND THE SCHEDULE IS THE EXCEPTION.
    Operator decision 2026-07-25, in answer to the right question: on the
    schedule the ambient wash means something — it is the colour of the job in
    front of you, picked by whoever scheduled it — and nothing else in the app
    has a natural colour like that. So what tints the wash everywhere else?

    Decided: every converted screen takes its wash from ITS FEATURE'S COLOUR.
    The schedule keeps its data-driven tint as a deliberate, documented
    exception, because a shift genuinely has a colour and an equipment list does
    not.

    The source is FeatureTheme.color(for:) in DesignSystem/DesignTokens.swift.
    That is already the single source of truth for the home tiles and the bottom
    bar, so the tile you tap and the wash behind the screen you land on agree —
    which is the whole reason to prefer it over a per-screen invention.

    THE PALETTE MUST BE RE-CUT FIRST, and the operator asked for exactly that.
    As it stands the map is not unique: five features are blue (Tasks, Chat,
    Daily Job Report, Capture, Manager Mileage), four are teal, four are green,
    and several more pair up. Batch 1 alone would give Tasks and Chat the same
    wash, which makes the signal meaningless the first time it is used.

    ONE CONSEQUENCE TO GO IN WITH EYES OPEN: FeatureTheme has three live
    consumers TODAY — MainEmployeeView, AllFeaturesView and BottomTabBar. Re-
    cutting the palette therefore changes the home screen's tile colours and the
    bottom bar immediately, on screens that have not been converted yet. That is
    not a reason to avoid it, but it means the palette lands as a visible change
    in its own right and gets its own line in a closeout.

    CORRECTION, 2026-07-25 (AMB.4). THE BOTTOM BAR HALF OF THAT WAS WRONG, and
    it went uncorrected for three phases. FeatureTheme appears in
    BottomTabBar.swift exactly once, at line 569 — inside TabBarConfigurationView,
    the CUSTOMISE screen. The bar itself colours from TabBarButton.accentColor, a
    FOURTH hardcoded feature-colour map that the audit roadmap's design-token
    consolidation never found. It covers seven ids and defaults everything else to
    blue, so the tile you tap and the bar item you land on disagree for nearly
    every feature; Tasks is not in the map at all, so its bar item is blue against
    a #E93D82 tile.

    The lesson is not the miss itself but how it survived: the palette was
    verified by reading the CALL SITES that were known about, not by grepping for
    what else assigns a colour to a feature id. The card-drift gate could not
    catch it either — it looks for hand-rolled cards, and a colour map is not a
    card. AMB.4 closes it by converting the bar (D13).

    Also note the schedule's own row in that map says red, while its wash is the
    job's colour. That is not a contradiction to fix — it is D11's exception,
    and FeatureTheme's schedule colour keeps doing its real job of tinting the
    schedule's TILE on the home screen.

    APPROVED AND APPLIED 2026-07-25. FeatureTheme now carries 27 distinct
    colours in ten families. The old map is kept verbatim in the lab as
    LabPalette.legacyColor so the before and after survive the port, and the
    Feature Colours sheet has changed job from proposal to record.

    This is the first change in the arc that alters screens which have NOT
    been converted: the home tiles, the All Features grid and the bottom bar
    all read FeatureTheme, so their colours changed the moment this landed.
    That was stated before it was done rather than discovered afterwards.

    HOME. The dashboard is the container, not a feature, so it has no entry.
    Operator decision the same day: home takes the COMPANY BLUE, #009AE2,
    at 90 percent intensity. The blue came from Logo.svg, the only place it
    was ever written down — the app's AccentColor asset is empty, so the app
    had been running on Apple's default blue. It is now AmbientStyle.brand.

D6  MAIN STAYS SHIPPABLE. Every phase is independently shippable and
    independently revertible. There is never a long-lived conversion branch. If
    the arc is abandoned after any phase, the app is coherent — some screens
    converted, some not, nothing half-done.

D7  EVERY PHASE VERIFIES ON iPHONE AND iPAD. Operator decision 2026-07-24.
    Not one iPad sweep at the end — each phase smokes on both devices before it
    closes. Several surfaces in this arc have genuinely different iPad layouts
    (Equipment, Chat, Groups, the manager tools), and a single sweep at the end
    would find eleven phases' worth of iPad defects at once, with no way to tell
    which phase caused which. Practical consequence: phase scoping must budget
    for the second device, and a phase is NOT done when only the iPhone passes.

D8  SHIP EACH PHASE TO MAIN AS IT LANDS. Operator decision 2026-07-24. No
    accumulation branch for the arc. Each phase merges to main and pushes once
    its review and both device smokes pass. This is what makes D6 load-bearing
    rather than theoretical: the app in the field is always a coherent mix of
    converted and unconverted screens, never a half-applied restyle.

D10 NOTHING IS CONVERTED BEFORE THE OPERATOR HAS SEEN A MOCKUP, AND THE
    MOCKUP IS BUILT IN SWIFTUI. Operator decision 2026-07-24, and it is a HARD
    GATE — a phase does not touch the real screens until its mockup is approved.

    THE MOCKUP IS SWIFTUI, RUNNING IN THE APP. Not HTML, not a picture. The
    first cut of this decision proposed a shareable web page; the operator
    rejected it on the correct grounds — this is not a web app, and HTML cannot
    render .ultraThinMaterial, a real blur, or SwiftUI motion. Approving an
    approximation and then seeing something different on device is worse than
    having no gate, because it manufactures confidence that was never earned.

    Form: THE LAB, rebuilt once and kept for the arc. AMB.1's design lab was the
    right instrument — in-app, real SwiftUI, sample data covering the hard cases,
    a gallery with a switcher, and the operator judging it on a device. That is
    how Ambient got chosen from something actually used rather than a picture.

    ONE HARNESS FOR THE WHOLE ARC, not one per phase. The first cut of this
    decision had each phase building and deleting its own scaffolding eleven
    times, which re-invents the sample data every phase and throws away the part
    that was actually valuable. AMB.2 builds the harness once:

        one temporary entry in the profile menu
        the sample dataset, extended per phase as new surfaces need shapes
          (the schedule's set already covers overlaps, multi-day, drafts,
          time off, a six-person crew and an empty day)
        a gallery shell with the switcher pattern the operator used to flip
          between designs
        each phase's mockup views mounted inside it

    MOCKED IN BATCHES, NOT PER PHASE. Operator decision 2026-07-25. A design
    language fails at the SEAMS between screens, and a per-phase review can only
    ever show one screen at a time — so surfaces that share a design problem are
    mocked together and reviewed in one sitting:

        Batch 1  Equipment, Home dashboard, Tasks, Chat      mocked in AMB.2
        Batch 2  Reports family, Time off                    mocked in AMB.6
        Batch 3  Mileage + Stats, Groups + Yearbook          mocked in AMB.8
        Batch 4  Job box/NFC, Settings, Manager, Training    mocked in AMB.10

    Four sittings instead of eleven, each showing a coherent set that can be
    judged against itself.

    NOT ALL OF IT UP FRONT, though, and this is the reason: anything mocked
    before Equipment converts is drawn against primitives the density work is
    about to change. Mocking ten surfaces now would mean approving ten designs
    and re-cutting most of them — the approval becomes theatre. Each batch is
    mocked shortly before its own phases run, so approvals cannot rot.

    THE HOME DASHBOARD IS IN BATCH 1, not with the other number-heavy screens.
    Its Upcoming Shifts widget renders shift cards, and the schedule is already
    converted and live — so that inconsistency is on the app's front door TODAY.
    Leaving it to the back half would park the most-opened screen in the app in
    visible disagreement with the one screen the arc has finished.

    ONE PROPOSAL PER SURFACE, NOT FIVE — with exceptions. The schedule lab held
    five competing directions because the design language did not exist yet;
    that was a CHOOSING exercise. Ambient is now settled, so most phases are
    APPLYING it and a single proposal is the honest amount of work. Where a
    surface poses a real open question, it gets 2–3 variants and the switcher:
    known candidates are AMB.3 (how a dense equipment list should read — compact
    rows vs cards vs grid, which also settles D5 for the whole arc) and AMB.9
    (chat, long scrollbacks).

    ONE CORRECTION FROM AMB.1 (L1): the mockup mounts inside the REAL shell's
    navigation container. The design lab gave every prototype its own
    NavigationStack, which is exactly why it could not catch the dead tap that
    reached production. A mockup that supplies its own navigation is testing a
    frame that will not exist.

    What each phase mocks: the surface's primary screen, its detail screen if it
    has one, and the states that cause arguments — a dense list, an empty state,
    an error. For AMB.2, whose deliverable is the primitives themselves, the
    mockup is a specimen sheet: every component roomy and compact, against
    Equipment's real row content.

    Lifecycle, at two levels, because they expire at different times:
      - A PHASE'S MOCKUP VIEWS are deleted at the close of that phase, once the
        operator has confirmed the converted screens — never before, per the
        rule that a validation reference outlives the port it validated.
      - THE HARNESS ITSELF (menu entry, sample data, gallery shell) lives for
        the arc and is deleted at the close of THE ARC'S LAST PHASE, along with
        its menu entry. It is arc-level scaffolding, and the arc is what it
        serves. If the arc is abandoned early, the harness goes with the last
        phase that ran.

        CORRECTED 2026-08-01 (D15). This bullet said "at the close of AMB.12"
        for eleven phases, because AMB.12 was the last phase when it was
        written. It stopped being the last phase the moment the time clock was
        given its own, and the shorthand is what got carried — the harness now
        dies at the close of AMB.13. A lifetime pinned to a phase NUMBER
        rather than to the thing it serves goes stale the first time the phase
        list moves.

    Cost, stated honestly: the harness is most of a session ONCE, inside AMB.2;
    each phase's mockup views are then a fraction of a session because the data,
    the shell and the switcher already exist. Against a full session of rework
    when a converted surface is rejected, that is cheap — and it is cheaper than
    the per-phase scaffolding this decision originally called for.

D9  THE TAIL GETS CONVERTED. Operator decision 2026-07-24. AMB.12 runs;
    Settings, the manager tools, Stats and Training are converted rather than
    left as a visible seam. They are last precisely because they are lowest
    traffic and inherit most of their look from the primitives by then.

D12 IT IS A REDESIGN, AND NO FEATURE MAY BE LOST. Operator decision
    2026-07-25. This SUPERSEDES the restyle-only framing at the top of this
    document, which was written before AMB.2's first batch of mockups made the
    cost of it visible.

    What went wrong. "Restyle only" was written to stop a design phase from
    quietly rewriting services and business rules, which is a good rule. In
    AMB.2's first cut of the batch-1 mockups it became something else: a
    ceiling on the DESIGN. The Tasks mockup drew today's flat rows as a
    switchable variant, which turns an approval into a referendum on the status
    quo. Equipment kept a two-tab picker nobody asked whether it needed.
    Message grouping — table stakes in every messaging app for a decade — was
    argued for defensively as "presentation, not data". The operator's
    correction was direct: this is supposed to be a redesign.

    What is now IN scope for a phase:
        layout, hierarchy and what leads a screen
        information architecture — tabs, grouping, what is one screen vs two
        the reading order of a list
        states that do not exist and should (an error a user can see)

    What stays OUT of scope, unchanged:
        data layers, services, loaders, listeners, caching
        business rules and permissions
        the shared Supabase schema, RLS, PowerSync sync rules

    THE PARITY CONSTRAINT IS THE HARD HALF, and it is checkable rather than
    promised. Before a surface is redesigned, its capabilities are inventoried
    FROM THE SOURCE — not from the screen, and not from memory — and every one
    is marked kept, moved, added or open. Batch 1's inventory is
    AMB_BATCH1_PARITY.md. Writing it caught five things the first cut of the
    mockups had outright wrong, none of them stylistic, all of them feature
    loss: Equipment's category filters were missing entirely, its three detail
    actions are conditional rather than constant, Tasks' Urgent filter is
    "urgent OR overdue" rather than "urgent or high", Tasks has five distinct
    per-filter empty states rather than one, and Chat has system messages
    ("X added Y to the group") that were not drawn at all.

    A REDESIGN THAT LOOKS BETTER AND WORKS WORSE HAS FAILED. Operator, same
    day: it has to fit the ambient style AND be functional for everyday use.
    The worked example is in KitDetailView, which sorts a kit's categories in
    photography workflow order — cameras, lenses, lighting, stands, bags,
    backdrops, power, storage, audio, accessories. Somebody thought about how a
    case is actually packed. An alphabetical sort would be indistinguishable in
    a screenshot and worse every day of the year. Domain logic like that is a
    feature under this decision and is carried forward explicitly.


D13 THE BOTTOM TAB BAR IS PART OF AMB.4, AND LANDS BEFORE ANY OTHER FEATURE.
    Operator decision, 2026-07-25: "it should be now in this phase, it should be
    with the main screen and before any other feature."

    WHY IT WAS MISSING, which is the part worth keeping. The bar belonged to NO
    phase. This plan's phase list is organised by FEATURE — Equipment, Tasks,
    Chat, Reports — and the bar is nav-shell furniture from NAV.1 that sits on
    every screen, so it matched no entry. The card-drift gate could not have
    caught it either: it detects hand-rolled CARDS, and a full-width bar is not a
    rounded, filled container. Two independent mechanisms for finding unconverted
    surfaces, and the bar was invisible to both. It surfaced only because the
    operator looked at the app and asked why it had not changed.

    THE GENERAL FORM OF THE GAP: this arc's phase list covers features, and the
    app also contains SHELL. Time tracking is recorded below as the same kind of
    hole, found the same way. Before AMB.5 starts, the remaining shell should be
    enumerated deliberately rather than waiting to be noticed — the profile
    toolbar, the theme picker, the toast, and whatever else appears on screens
    nobody has assigned.

    WHY IT BELONGS WITH THE HOME SCREEN RATHER THAN AT THE TAIL: the bar sits at
    the bottom of the dashboard, so converting home without it leaves a glass,
    washed screen sitting on an opaque slab — a seam on the app's front door,
    which is exactly the failure D10's batch-review rule exists to prevent. It is
    also the app's most-seen pixel, present on every screen including the nine
    still unconverted, so it does more than any single feature to make the app
    read as one thing.

    SCOPE: BottomTabBar.swift (570 lines — the bar, its button, and the customise
    screen). Models/TabBarItem.swift is DATA and is not restyled. The two device
    layouts are preserved exactly, including the iPad's centre Home button, its
    upward overflow, and the notch in the top hairline that NAV.1 shipped.


D14 ONE WASH FOR THE WHOLE APP; RED MEANS FLAGGED. Operator decision
    2026-07-30, at the batch-4 sitting (full card:
    ~/Brain/decisions/"2026-07-30 one wash for the whole app, red means
    flagged.md"). SUPERSEDES D11-as-applied-to-backdrops and the schedule's
    job-tint wash: the operator does not want the app changing colors by
    feature, and the WEB app is standardizing every page on its schedule-style
    aura — so this app uses THAT color everywhere and the two apps read as one
    product. The color is the web aura's hue-203 company blue
    (hsl(203 100% 37%) ≈ #0074BD, defined in the web repo's
    src/styles/variables.css). Feature ACCENTS (tiles, icons, bar pills,
    badges) keep their D11 colors — the ruling is about backgrounds, not
    feature identity. A FLAGGED user's aura turns RED, app-wide, through ONE
    mechanism at the backdrop level (count stores, not call sites — the PUB.1
    lesson); no feature may wash a screen red, while momentary reds
    (destructive buttons, failures, overdue badges) stay.

## Phases

Ordered by how often a photographer touches the surface, with one deliberate
exception: the first dense list runs BEFORE the highest-traffic screen, so that
nothing is built on primitives that are still moving (D5).

    AMB.1   Schedule                                        DONE 2026-07-24
            ScheduleView + ScheduleRows + ScheduleStyleKit replace
            SlingWeeklyView; ShiftDetailView restyled, data layer untouched.
            Operator smoke passed on device. 8 review findings applied.

    AMB.2   Design system extraction + enforcement gate      NEXT
            Promote the schedule's vocabulary into DesignSystem/ as the app's
            primitives. Delete the unused cardStyle(). Add the build gate.
            Design the compact density variants against Equipment's real code,
            to be proven by converting it in AMB.3. Build the arc's mockup
            harness (D10) — menu entry, sample data, gallery shell, switcher —
            which every later phase mounts its mockups inside. Then mock BATCH 1
            inside it: Equipment, the home dashboard, Tasks and Chat, reviewed
            in one sitting alongside the specimen sheet. Realistically two
            sessions. No screen changes beyond the schedule repointing at the
            new home.

    AMB.3   Equipment                    (34 views, 5,583 lines)   BATCH 1
            The first genuinely dense, list-heavy surface, and the proof of the
            compact variants AMB.2 designed. Anything they get wrong is found
            here and folded back into the design system before the rest of the
            batch is built on them.

    AMB.4   Home dashboard                                          BATCH 1
            MainEmployeeView + DashboardWidgets, about 3,600 lines. Highest
            traffic screen in the app, and the one whose Upcoming Shifts widget
            currently disagrees with the already-converted schedule. Runs second
            rather than first only because its widgets mix dense and roomy
            content, and building it before the compact variants are proven
            would guarantee a revisit.

    AMB.5   Tasks                        (18 views, 3,167 lines)    BATCH 1

    AMB.6   Chat                         (20 views, 4,655 lines)    BATCH 1
            The hardest test of the compact set: long scrollbacks, and the most
            likely place for material and blur to cost real frames. Closes
            batch 1 and mocks batch 2.

    AMB.7   Reports family               (Misc Features, 8,695 lines)  BATCH 2
            Daily job report, custom daily reports, my reports, photoshoot
            notes. Form-heavy; first real input styling, which the schedule
            never touched.

    AMB.8   Time off                     (8 views, 3,763 lines)     BATCH 2
            Closes batch 2 and mocks batch 3.

    AMB.9   Mileage + Stats              (Misc Features + StatsView)  BATCH 3
            Number-heavy. Exercises the stat tile and any charts.

    AMB.10  Groups + Yearbook            (17 views, 4,504 lines)    BATCH 3
            Closes batch 3 and mocks batch 4.

    AMB.11  Job box / NFC                (18 views, 5,198 lines)    BATCH 4
            SHIPPED + PUSHED + CLOSED 2026-07-31 (origin/main ..12c5a45).
            Full conversion, Flag for Attention built for real and made
            visible to everyone, one job-box colour contract, the alert
            banner carries its own fix. /code-review: 8 findings, all fixed.
            Both device smokes PASSED. Mockup deleted at the close.
            Closeout detail in AUDIT_ROADMAP.md.

    AMB.12  Settings, Manager, Training + the shell   (~7,700 lines)  BATCH 4
            The tail (D9). Lowest traffic, converted last, and by this point
            mostly inherits from the primitives with little bespoke work.
            PLUS the five shell surfaces that belonged to no phase, folded in
            here by operator ruling 2026-08-01 (D15): the sign-in surface, the
            launch state, the toast, the home profile toolbar and the
            appearance picker. Also carries the arc's consolidations — the
            chips, failure cards, loading rows, search field and primary button
            that AMB.9 and AMB.10 both deferred here.
            Does NOT close the arc and does NOT delete the lab (D15).

    AMB.13  The time clock                (10 screens, 2,662 lines)
            Added 2026-08-01 by operator ruling (D15). The clock-in and
            clock-out surface, which was named in no phase from AMB.2 onward.
            Runs LAST rather than folded into the tail because it is payroll —
            seven write paths with one confirmation between them — and payroll
            deserves its own design sitting and its own smoke rather than
            sharing the tail's. CLOSES THE ARC: the lab harness and its menu
            entry are deleted here.

Roughly ten sessions after AMB.2, plus AMB.2 itself — which is now the design
system, the build gate, the lab harness AND batch 1's four surfaces' mockups,
so it is realistically TWO sessions rather than one. Said here rather than
discovered mid-phase, where the only options would be rushing the mockups or
quietly splitting the phase.

Every fourth phase carries the next batch's mockups (AMB.6, AMB.8, AMB.10), so
those run slightly long. The estimate assumes AI pair-coding pacing and that D5
lands cleanly at AMB.3; if the compact variants need a second pass, add one.


## AMB.2 in detail (the next phase)

The only phase whose content is fully specified here. Later phases are scoped
at the start of their own session against the code as it stands then.

MOVE INTO DesignSystem/, from Schedule/ScheduleStyleKit.swift:

    the material card container and its compact sibling (the compact set is
      designed against Equipment's real rows — see D5 — and proven in AMB.3)
    ScheduleBadge, ScheduleTypePills, ScheduleFlowLayout
    ScheduleAvatar, ScheduleCrewStack
    ScheduleSectionTitle, ScheduleStatTile, ScheduleNoteCard, ScheduleEmptyState
    ScheduleBackdrop and the ambient tint rule
    ScheduleMotion, ScheduleHaptics
    the iOS 16.6 availability wrappers
    the FNV-1a stable hash behind deterministic colours

Names lose the Schedule prefix on the way, since they stop being schedule
things. The schedule keeps only what is genuinely about shifts: standing, the
countdown, the timeline, per-type icons and colours.

DELETE in the same commit:

    DesignSystem/DesignTokens.swift cardStyle() and CardStyle — the modifier
    with zero adopters. FeatureTheme and Formatters in that file are used and
    stay.

THE GATE. A check that fails on a newly hand-rolled card in a view file outside
DesignSystem/. Modelled on the existing protect-captura-files.sh hook, which is
the enforcement pattern this repo already trusts. Existing occurrences are
grandfathered by path until their phase converts them, so the gate starts green
and only catches NEW drift.

Without the gate this arc produces the same outcome Phase 3 did.

CORRECTED 2026-07-25, during AMB.2, after an actual census of the codebase. The
rule as written above was wrong in three ways, and all three would have made the
gate worse than useless — a gate that is green for the wrong reasons is worse
than no gate, because it manufactures confidence:

  1  IT DETECTED THE WRONG PATTERN. "A RoundedRectangle fill combined with a
     shadow" misses about fifteen real hand-rolled cards that use cornerRadius
     instead of a RoundedRectangle shape — including Equipment's own row, the
     very card AMB.3 converts, and Chat's message input bar. The gate now
     detects both forms.

  2  IT WOULD HAVE FLAGGED THE STYLE IT PROMOTES. The schedule's own cards are a
     material fill in a RoundedRectangle with a shadow, so the arc's reference
     implementation was the first thing the rule caught. Fixed properly rather
     than by exempting the schedule: the schedule's cards now go through the
     shared primitive, so there is nothing left to flag.

  3  PATH-LEVEL GRANDFATHERING ALONE WAS TOO COARSE. Allowlisting a whole file
     blinds the gate to every other card in it, and the two worst offenders are
     DashboardWidgets (seven) and the NFC statistics screen (six) — exactly the
     files where new cards are most likely to be added next. There is now also a
     per-site marker, ambient-allow, for the things that are rounded and
     shadowed but genuinely are not cards: a selection chip, a photo hero, a
     drop shadow on a glyph. Schedule/ uses markers and is NOT allowlisted, so
     it keeps full protection.

The gate lives at scripts/check_card_drift.py and runs two ways: as a PreToolUse
hook registered in .claude/settings.json (checked in, so it travels with the
repo), and as a sweep over the whole app for the verification step of every
phase. It fails open on any error. Its allowlist is GENERATED from the rule
itself rather than hand-written, so the green start is a fact rather than a
hope: 46 files, 101 hand-rolled cards, zero unlisted. That is close to the 115
this document counted by hand, and the remainder is the difference between
counting card BACKGROUNDS and counting card CONTAINERS.

Two properties are worth stating because they are what make it survive contact
with the arc rather than being switched off in week three:

  IT RATCHETS RATHER THAN DEMANDS PERFECTION. Each grandfathered file carries
  its CURRENT card count, and an edit is refused only if it would INCREASE that
  file's count. So a phase can convert one card at a time without the gate
  fighting it, while DashboardWidgets can never reach eight cards and one. A
  clean-file rule would have blocked every partial conversion, which is how a
  gate ends up being deleted rather than obeyed.

  A NON-CARD IS ANNOTATED IN PLACE, NOT EXEMPTED WHOLESALE. A selection chip, a
  photo hero, a keyboard key gets a reasoned marker on the line above it. That
  keeps every other line in the file guarded, where allowlisting the file would
  blind the gate to all of it.

Third correction, 2026-07-25: the first cut hardcoded the script's absolute path
in .claude/settings.json. Since a PreToolUse hook treats exit 2 as BLOCK and
python3 exits 2 when it cannot open a file, that would have refused EVERY edit
in the project on any clone where the path did not resolve — and this file is
checked in, so the first clone would have hit it. The command now derives its
path and tests for the script first, so a missing gate means no gate rather than
no edits.


## Per-phase workflow

Each phase session runs:

    1  SCOPE      list the views in the surface, name what must survive
    2  MOCK       SwiftUI mockup of the surface's key screens with sample data,
                  behind one temporary menu entry, mounted in the REAL shell's
                  navigation container. HARD GATE (D10) — the real screens are
                  not touched until it is approved. A rejected mockup is re-cut
                  here, where it costs minutes, not after conversion.
    3  CONVERT    presentation only; data layer untouched; delete the old
                  presentation in the same commit, never alongside. The mockup is
                  mockup is scaffolding, not a second implementation of the
                  shipping screen, and it is deleted at the close of the phase
                  (after the operator confirms the port) — so delete-first and
                  the no-parallel-implementations rule both still hold.
    3b MATCH      put the converted screen beside the approved mockup and
                  account for every difference — interaction, frames, spacing,
                  states. A frame correct in the mockup's container can be wrong
                  in the real one. Restore it, or name it as a deliberate change.
    4  BUILD      xcodebuild clean, zero warnings from changed files
    5  REVIEW     /code-review before any push, operator-triggered
    6  SMOKE      operator on iPhone AND iPad (D7), with before/after screenshots
    7  CLOSE OUT  AUDIT_ROADMAP.md entry + registry status line

Acceptance criteria, every phase, no exceptions:

    the mockup was approved before conversion started (D10)
    the built screen was diffed back against that mockup (workflow step 3b)
    iPhone AND iPad
    light AND dark
    Dynamic Type at large accessibility sizes
    iOS 16.6 floor respected
    every capability that existed before still exists, enumerated in the
      closeout — the AMB.1 commit message is the model
    main still shippable


## Lessons from AMB.1, carried forward

These are here because each one cost real time on the schedule and each one
will recur.

L1  A PROTOTYPE THAT CARRIES ITS OWN NAVIGATION CONTAINER IS LYING TO YOU.
    Every design-lab prototype built its own NavigationStack, so navigation
    worked there and could only fail once the real shell wrapped it in a
    NavigationView. Tapping a shift did nothing on first ship. Prototype inside
    the real container, or expect to find it in production.

L2  "DO IT ONCE" FLAGS MUST MEAN "IT SUCCEEDED", NOT "WE TRIED".
    Shipped twice on this arc: the timeline anchored before the data arrived and
    marked itself done, and the second attempt at the fix set the flag before
    the scroll ran. Both were caught only by review or by the operator.

L3  WHATEVER RE-ENTRANCY GUARD YOU ADD, CHECK WHAT ELSE onAppear WAS DOING.
    Guarding start() to stop a duplicate fetch also stopped the organization
    listener from restarting, which silently froze session-type colours and both
    Publish buttons for the app's lifetime.

L4  PER-CELL COMPUTATION IS FINE UNTIL IT IS INSIDE A LAZY STACK.
    Day queries that scanned the session list were invisible until they ran ~50
    times per body pass under a moving thumb. The fix — fold the data into an
    index once per change — is the pattern for any converted list.

L5  RESTYLING SURFACES PRE-EXISTING BUGS. The schedule's weather fetch had been
    dead since Session.location was hard-coded to nil; the Yearbook button
    tested a non-optional for nil; Message crew failed silently when nobody had
    a phone number on file. Expect one or two per surface. Fix them if they are
    inside the surface, name them in the closeout, and do not let them expand
    the phase.

L7  APPROVING A MOCKUP IS NOT VERIFYING THE BUILD. AMB.1 shipped a static
    seven-day day strip where the lab scrolled continuously, and when that was
    restored, shipped it at the wrong capsule width — the capsules kept a
    maxWidth: .infinity that was correct in the old seven-across HStack and
    collapses to content width inside a horizontal ScrollView. Both reached the
    operator. Neither was caught by the build, the review, or the mockup gate,
    because nothing compared the built screen to the approved one. Hence
    workflow step 3b.

L6  RUN THE REVIEW BEFORE PUSHING. Post-push there is no branch delta left to
    bundle. This is the CRS.1 lesson and it held again here: the review found
    eight findings, five of them regressions this arc introduced, including one
    that would have frozen both Publish buttons.


## Explicit non-goals

    NOT migrating to NavigationStack (see D3)
    NOT touching Sports Shoot Feature (see D1)
    NOT raising the deployment target
    NOT restructuring navigation, data models, services or PowerSync
    NOT a performance arc, though L4's pattern is applied where a converted
      list needs it
    NOT adding features to converted surfaces


## RESOLVED 2026-08-01 — raised 2026-07-25 during AMB.2, answered at AMB.12's
## kickoff, which was the last phase in which it could be

TIME TRACKING WAS NOT IN ANY PHASE. Building the gate's allowlist meant walking
every surface in the app, and the clock-in and clock-out screens were named
nowhere in the phase list above:

    TimeTrackingMainView, TimeTrackingButton, TimeEntryListView,
    TimeEntryDetailView, ActiveClockInEditView, ManualTimeEntryView,
    EditTimeEntryView, CustomClockOutView, SessionSelectionView

That is about 2,540 lines across nine screens, and photographers touch the clock
every working day — so it is not tail traffic. It is also payroll-adjacent,
which raises the bar on any change to it.

Three ways to resolve were offered, for the operator to pick, not for a phase to
decide quietly mid-build:

  fold it into AMB.12, which is already the tail and would simply grow;
  give it its own phase between AMB.8 and AMB.9, near the other number-heavy
    screens;
  leave it unconverted on purpose and record that as a deliberate seam.

Recorded rather than resolved, because silently adding a tenth surface to
someone else's phase is how a plan stops being the thing that governs the work.

**HE TOOK THE SECOND, moved to the end: its OWN phase, AMB.13, running after the
tail.** His reason was the one recommended — it is payroll, and it deserves its
own design sitting and its own careful smoke rather than sharing the tail's. See
D15 below and the decision card
`~/Brain/decisions/2026-08-01 the time clock gets its own phase, the furniture
ships with the tail.md`.

That answer had a consequence nobody had written down, which is D15's real
lesson: **moving work out of the last phase moves the last phase**, and the lab
harness was scheduled to die "at AMB.12" purely because AMB.12 used to be last.


D15 THE TIME CLOCK GETS ITS OWN PHASE; THE FURNITURE SHIPS WITH THE TAIL; THE
    LAB OUTLIVES AMB.12. Operator decision 2026-08-01, at AMB.12's kickoff.

    THE CLOCK. Ten screens, 2,662 lines, seven payroll write paths with exactly
    ONE confirmation between them, touched every working day. It becomes AMB.13
    rather than folding into the tail — payroll gets its own sitting and its own
    smoke.

    THE FURNITURE. The five shell surfaces `AMB_SHELL_INVENTORY.md` named at
    AMB.5 — the sign-in surface, the launch state, the toast, the home profile
    toolbar and the appearance picker — fold into AMB.12. They inherit most of
    their look from the primitives, and leaving them out would have left THE
    FIRST SCREEN EVERY USER SEES as the only unconverted one in the app.

    THE LAB. It does not die at AMB.12. AMB.13 needs the harness to design the
    clock screens against, and deleting scaffolding in the phase BEFORE the one
    that needs it would leave that phase with nothing to design in. The harness,
    its menu entry, its sample data and every surviving mockup die together at
    the close of AMB.13.

    GENERALISABLE, and it is the part worth keeping: anything scheduled to die
    "at the end" is pinned to a phase NUMBER somewhere, and a deferral moves the
    end. Re-check every such lifetime in the SAME change as the deferral, rather
    than letting the next phase discover it by needing the deleted thing.


## Answered, 2026-07-24

The three questions this plan opened with are now decisions D7 (iPad every
phase), D8 (ship to main as we go) and D9 (convert the tail). Nothing in this
plan is awaiting an operator answer.

The next decision point is not a question but a checkpoint: D5 (density) is
designed in AMB.2 and proven in AMB.3 by converting Equipment. If the compact
variants do not survive contact with Chat at AMB.9, that is a revision to the
design system, not a re-opening of this plan.

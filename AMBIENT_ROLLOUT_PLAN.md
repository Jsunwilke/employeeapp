# AMB — Ambient design language rollout (iOS employee app)

Plan doc for the AMB arc. Registered in the family registry,
FocalPointProduction/docs/PHASES.md. One phase per session.

Written 2026-07-24, after AMB.1 (the schedule) shipped and passed operator
smoke on device.


## What this arc is

The schedule now uses a design language the operator chose from five
prototypes: a live countdown to the next call time, glass cards over an ambient
wash tinted by the job in front of you, per-type icons and wrapping pills, and
three unmistakable states for a shift — done, happening now, still to come.

This arc carries that language through the rest of the app.

It is a RESTYLE arc, not a rewrite arc. Data layers, services, navigation
shape and business rules are out of scope inside a phase. The schedule proved
the pattern: ShiftDetailView's presentation was replaced entirely while every
loader, listener and calculation in it stayed byte-identical.


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

D5  DENSITY IS DECIDED AT AMB.4, NOT AT THE END. Ambient's glass and generous
    spacing suit a schedule with a handful of items a day. A 200-row equipment
    list or a chat thread in that style will feel slow and airy. Every primitive
    therefore needs a compact variant alongside the roomy one, and that variant
    is designed against a real dense screen early — not retrofitted after nine
    phases have shipped assuming the roomy one.

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

D9  THE TAIL GETS CONVERTED. Operator decision 2026-07-24. AMB.12 runs;
    Settings, the manager tools, Stats and Training are converted rather than
    left as a visible seam. They are last precisely because they are lowest
    traffic and inherit most of their look from the primitives by then.


## Phases

Ordered by how often a photographer touches the surface, with one deliberate
exception: the first dense list is pulled early to settle D5.

    AMB.1   Schedule                                        DONE 2026-07-24
            ScheduleView + ScheduleRows + ScheduleStyleKit replace
            SlingWeeklyView; ShiftDetailView restyled, data layer untouched.
            Operator smoke passed on device. 8 review findings applied.

    AMB.2   Design system extraction + enforcement gate      NEXT
            Promote the schedule's vocabulary into DesignSystem/ as the app's
            primitives. Delete the unused cardStyle(). Add the build gate.
            No screen changes beyond the schedule repointing at the new home.

    AMB.3   Home dashboard
            MainEmployeeView + DashboardWidgets, about 3,600 lines. Highest
            traffic screen in the app and the most mixed content, so it is the
            real proof the primitives cover more than a schedule.

    AMB.4   Equipment                    (34 views, 5,583 lines)
            The first genuinely dense, list-heavy surface. Settles D5: the
            compact variants of card, row, badge and avatar are designed here
            and folded back into the design system before anything else uses
            them.

    AMB.5   Reports family               (Misc Features, 8,695 lines)
            Daily job report, custom daily reports, my reports, photoshoot
            notes. Form-heavy; will exercise input styling, which the schedule
            never touched.

    AMB.6   Mileage + Stats              (within Misc Features + StatsView)
            Number-heavy surfaces. Exercises the stat tile and any charts.

    AMB.7   Time off                     (8 views, 3,763 lines)

    AMB.8   Tasks                        (18 views, 3,167 lines)

    AMB.9   Chat                         (20 views, 4,655 lines)
            Second dense surface, and the one most likely to expose material
            performance limits in long scrollbacks.

    AMB.10  Groups + Yearbook            (10 + 7 views, 4,504 lines)

    AMB.11  Job box / NFC                (18 views, 5,198 lines)

    AMB.12  Settings, Manager, Training  (about 6,600 lines)
            The tail. Lowest traffic, converted last, and by this point mostly
            inherits from the primitives with little bespoke work.

Roughly eleven sessions after AMB.2. That estimate assumes AI pair-coding
pacing and that D5 lands cleanly at AMB.4; if the compact variants need a
second pass, add one session.


## AMB.2 in detail (the next phase)

The only phase whose content is fully specified here. Later phases are scoped
at the start of their own session against the code as it stands then.

MOVE INTO DesignSystem/, from Schedule/ScheduleStyleKit.swift:

    the material card container and its compact sibling
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

THE GATE. A pre-commit or build-phase check that fails on a newly hand-rolled
card: a RoundedRectangle fill combined with a shadow in a view file outside
DesignSystem/. Modelled on the existing protect-captura-files.sh hook, which is
the enforcement pattern this repo already trusts. The existing 115 occurrences
are grandfathered by path until their phase converts them, so the gate starts
green and only catches NEW drift.

Without the gate this arc produces the same outcome Phase 3 did.


## Per-phase workflow

Each phase session runs:

    1  SCOPE      list the views in the surface, name what must survive
    2  CONVERT    presentation only; data layer untouched; delete the old
                  presentation in the same commit, never alongside
    3  BUILD      xcodebuild clean, zero warnings from changed files
    4  REVIEW     /code-review before any push, operator-triggered
    5  SMOKE      operator on device, with before/after screenshots
    6  CLOSE OUT  AUDIT_ROADMAP.md entry + registry status line

Acceptance criteria, every phase, no exceptions:

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


## Answered, 2026-07-24

The three questions this plan opened with are now decisions D7 (iPad every
phase), D8 (ship to main as we go) and D9 (convert the tail). Nothing in this
plan is awaiting an operator answer.

The next decision point is not a question but a checkpoint: D5 (density) is
settled by building it at AMB.4, against Equipment. If the compact variants
designed there do not survive contact with Chat at AMB.9, that is a revision to
the design system, not a re-opening of this plan.

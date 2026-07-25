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

D5  DENSITY IS SETTLED BEFORE ANY SCREEN IS BUILT ON IT. Ambient's glass and
    generous spacing suit a schedule with a handful of items a day. A 200-row
    equipment list or a chat thread in that style will feel slow and airy. Every
    primitive therefore needs a compact variant alongside the roomy one.

    The compact variants are DESIGNED in AMB.2, against Equipment's real code,
    and PROVEN in AMB.3 by converting Equipment itself. Only then does the home
    dashboard follow.

    Revised 2026-07-24, before any of it was built: the first cut of this plan
    put the dashboard at AMB.3 and Equipment at AMB.4 while also saying density
    was settled at AMB.4 — so the highest-traffic screen in the app would have
    been built on primitives that were about to change, and either invented its
    own compact treatments or been revisited. Two decisions in the same document
    that contradicted each other. Ordering Equipment first costs the dashboard
    one phase of waiting and removes the rework entirely.

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
        the arc and is deleted at the close of AMB.12, along with its menu
        entry. It is arc-level scaffolding, and the arc is what it serves.
        If the arc is abandoned early, the harness goes with the last phase
        that ran.

    Cost, stated honestly: the harness is most of a session ONCE, inside AMB.2;
    each phase's mockup views are then a fraction of a session because the data,
    the shell and the switcher already exist. Against a full session of rework
    when a converted surface is rejected, that is cheap — and it is cheaper than
    the per-phase scaffolding this decision originally called for.

D9  THE TAIL GETS CONVERTED. Operator decision 2026-07-24. AMB.12 runs;
    Settings, the manager tools, Stats and Training are converted rather than
    left as a visible seam. They are last precisely because they are lowest
    traffic and inherit most of their look from the primitives by then.


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
            which every later phase mounts its mockups inside. No screen changes
            beyond the schedule repointing at the new home.

    AMB.3   Equipment                    (34 views, 5,583 lines)
            The first genuinely dense, list-heavy surface, and the proof of the
            compact variants AMB.2 designed. Anything they get wrong is found
            here and folded back into the design system before the dashboard —
            or anything else — is built on them.

    AMB.4   Home dashboard
            MainEmployeeView + DashboardWidgets, about 3,600 lines. Highest
            traffic screen in the app and the most mixed content, so it is the
            real proof the primitives cover more than a schedule. Runs second
            rather than first only because its widgets mix dense and roomy
            content, and building it before the compact variants are proven
            would guarantee a revisit.

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
    4  BUILD      xcodebuild clean, zero warnings from changed files
    5  REVIEW     /code-review before any push, operator-triggered
    6  SMOKE      operator on iPhone AND iPad (D7), with before/after screenshots
    7  CLOSE OUT  AUDIT_ROADMAP.md entry + registry status line

Acceptance criteria, every phase, no exceptions:

    the mockup was approved before conversion started (D10)
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
designed in AMB.2 and proven in AMB.3 by converting Equipment. If the compact
variants do not survive contact with Chat at AMB.9, that is a revision to the
design system, not a re-opening of this plan.

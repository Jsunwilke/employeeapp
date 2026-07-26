# The shell inventory — everything the AMB phase list does not own

Written at the start of AMB.5, because AMB.4 was told to do this and the reason is
worth restating: THE BOTTOM TAB BAR BELONGED TO NO PHASE. This arc's phase list is
organised by FEATURE (Equipment, Tasks, Chat, Reports), and the bar is nav-shell
furniture that sits on every screen, so it matched no entry. The card-drift gate
could not catch it either, because a full-width bar is not a rounded, filled
container. Two independent mechanisms for finding unconverted surfaces, both blind
to it by construction — and the thing that actually found it was the operator
looking at the app and asking why it had not changed.

D13 folded the bar into AMB.4 and ordered the rest of the shell enumerated
deliberately rather than waiting to be noticed a second time. This file is that
enumeration.

METHOD, so the gaps in the method are visible too. Three passes, all against the
source rather than against memory or a screenshot:

    1  every Swift file at the app root and in Navigation, Components, Dashboard,
       Extensions, Utilities and Models, read for view code
    2  the drift gate's allowlist, cross-referenced against the phase list, to
       separate "unconverted with an owner" from "unconverted with no owner"
    3  a grep for Capsule fills outside DesignSystem and DesignLab, because the
       gate matches RoundedRectangle and cornerRadius and is therefore blind to a
       capsule — which is what the toast is


## The toast and the floating bar: OPEN, needs one look on a device

CORRECTED 2026-07-26, and the correction is the useful part. The first version of
this section asserted that every toast in the app draws 34pt inside the floating
bar's footprint, from comparing ToastView's 50pt bottom padding against
TabBarMetrics.clearance of 84pt. That arithmetic was wrong, and I wrote a fix on
the strength of it. The fix has been reverted; ToastView is behaviourally
unchanged, with a comment in it recording this.

Why the arithmetic was wrong:

    the two numbers are not measured from the same datum — the clearance is a
      safe-area INSET, the 50pt is plain padding on an overlay
    the toast grows UPWARD from its padding, so it is not a point
    the clearance deliberately carries a 10pt breathing margin, so being under it
      is not the same as being under the bar

And the part that actually settles it, which the audit found rather than I:
TWO OF THE THREE CALL SITES ALREADY GET THE SHELL'S INSET. Scan and the daily job
report are shell-wrapped features, so MainEmployeeView.featureContainer applies the
84pt tabBarClearance to them, and their .toast() overlays live inside it. Adding
padding in the toast would double-count for those two. Only the MainEmployeeView
call site is bare.

So the honest state is: the toast MAY be clipped by the bar at one of three call
sites and would have been over-corrected at the other two. It needs one look on a
device — open Scan, trigger a toast, and see where it lands. Recorded rather than
guessed at, because shipping an unverified layout change to app-wide chrome is the
exact mistake AMB.4 made four times over, and every wrong version of it built
cleanly.

What still stands from the original finding: the drift gate could never have caught
the toast either way, because the toast is a Capsule and the gate matches
RoundedRectangle and cornerRadius. That is a second structural blind spot alongside
the full-width bar, and it is worth keeping.

Three call sites: MainEmployeeView (the report-submitted toast), NFC/ScanView, and
Misc Features/DailyJobReportView.


## Unconverted, and NO phase owns it

These are the real holes — nothing in the phase list claims them and they carry no
allowlist row, so both discovery mechanisms read clean.

    ToastView                     Components/ToastView.swift
                                  Solid green or red capsule, white glyph and
                                  text, shadow radius 10. No ambient vocabulary.
                                  Plus the open bar-collision question above,
                                  which is a device check rather than a restyle.
                                  Three call sites.

    The home profile toolbar      MainEmployeeView, homeProfileToolbar
                                  First name, avatar or a grey person glyph, and a
                                  hamburger opening Settings, Appearance, Design
                                  Lab and Logout. Plain system styling on the
                                  app's front door, beside a screen that is now
                                  fully converted. The Design Lab entry is
                                  temporary and goes at AMB.12 with the lab.

    The appearance picker         MainEmployeeView, themePickerSheet
                                  A plain NavigationView wrapping a plain List of
                                  three buttons with checkmarks. Reached from the
                                  profile menu above.

    The sign-in surface           Settings/SignInView, Settings/ForgotPasswordView,
                                  Settings/ResetPasswordView
                                  EVERY user sees SignInView, and it is the first
                                  thing they see. Named in no phase at all. Its
                                  only rounding today is a cornerRadius of 8.

    The launch state              RootView
                                  A bare ProgressView on the default background
                                  while the Supabase session is checked, which can
                                  run up to ten seconds by its own deadline. The
                                  app's actual first frame.

    HomeToolbarButton             Navigation/HomeToolbarButton.swift
                                  A single SF Symbol in a toolbar slot. Listed for
                                  completeness; there is close to nothing to
                                  convert, and a toolbar glyph is system chrome.


## Unconverted, but a phase DOES own it

Recorded so the list is honest about what is already assigned. These carry
allowlist rows naming their phase, so the existing mechanism does cover them.

    AllFeaturesView               AMB.12, 1 card. Already reads the D11 palette
                                  from FeatureTheme, so it is half-converted:
                                  right colours, hand-rolled container.
    LoadingOverlay                AMB.12, 1 card. Used by ScanView.
    UIComponents.swift            AMB.12, 1 card. ModernCheckboxRow and
                                  ModernSegmentButton.
    SessionSelectionView          AMB.12, 1 card.
    TimeTrackingButton,           AMB.12, 2 cards each. Part of the time-tracking
    TimeTrackingMainView,         surface that the plan's Open section already
    TimeEntryListView             raises as belonging to no phase by feature.
    RealTimeSyncIndicator         AMB.1 residual, 1 card.


## Already converted, for the avoidance of a second look

    BottomTabBar and its customise screen        AMB.4
    The home dashboard and all seven widgets     AMB.4
    DashboardChrome                              AMB.4
    The flag banner and its inline note card     AMB.4
    The All Features row on home                 AMB.4
    FeatureTheme's palette                       AMB.2, D11


## What this changes about the two discovery mechanisms

Neither mechanism is a coverage test, and this is the generalisable part.

The ALLOWLIST answers "which files hand-roll a card". A surface with no card in it
is absent from the allowlist whether it is converted or has never been touched.
Tasks is the live example: it carries no allowlist row, not because it is done but
because it has no card, background, radius or shadow anywhere. An empty allowlist
row means nothing about whether a surface is converted.

The PHASE LIST answers "which features get converted". It cannot see shell, and it
cannot see a surface that is chrome rather than a feature.

So the only thing that closes the gap is an enumeration like this one, done from
the source. It is offered as a report: what joins AMB.5, what becomes its own
phase, and what folds into AMB.12 is the operator's call, exactly as D13 was.

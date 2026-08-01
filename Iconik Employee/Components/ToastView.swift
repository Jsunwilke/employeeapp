//  ToastView.swift
//  Iconik Employee — the app's transient confirmation
//
//  CONVERTED IN AMB.12, as one of the five shell surfaces that belonged to no
//  phase (operator ruling D15, 2026-08-01). It was invisible to BOTH of the arc's
//  discovery mechanisms: the phase list is organised by FEATURE and a toast is
//  not one, and the card-drift gate matches a rounded, filled container while
//  this draws a Capsule.
//
//  FOUR REAL DEFECTS FIXED HERE, all of them found by reading it rather than by
//  looking at it:
//
//  1. THE FIRST TOAST'S TIMER DISMISSED THE SECOND TOAST'S MESSAGE. The
//     auto-dismiss was scheduled in `.onAppear`. Raising a second toast while one
//     is visible replaces the string in place — the view does not re-appear, so
//     `onAppear` does not re-fire, so the second message inherited whatever was
//     left of the first one's three seconds. The dismiss is now keyed to the
//     MESSAGE, so a NEW message gets its own full life. One case survives and is
//     documented at the keying site rather than papered over: the same string
//     raised again while it is already showing changes no state at all, so there
//     is nothing for SwiftUI to key on. Closing that needs an explicit `show()`
//     instead of a Bool binding.
//
//  2. THE SHOW WAS UN-ANIMATED; only the hide was. Every call site set the flag
//     bare and only the dismissal was wrapped in `withAnimation`, so the toast
//     appeared instantly and left gracefully.
//
//  3. IT SAT ON THE TAB BAR AT ONE OF ITS TWO CALL SITES. `.padding(.bottom, 50)`
//     is measured from the host's bottom edge, and the two hosts do not have the
//     same one: the ScanView host carries the shell's 84pt inset, the
//     MainEmployeeView host carries nothing. So the same 50 put the toast at
//     134pt above the bar at one site and 24pt INSIDE the bar band at the other —
//     covering the bar's left and right cells and taking their taps for three
//     seconds. And the bare site is the one that fires on every successful daily
//     report, which is the routine path, not the edge case.
//
//     THE FIX IS TO STOP DEPENDING ON THE HOST. The layer expands back through
//     whatever safe area its host has (`ignoresSafeArea(.container, edges:
//     .bottom)`) and then measures from the real bottom using the bar's own
//     published metrics. Both call sites now land in the same place, and a third
//     one would too. Note the shell inventory's own reasoning about this was
//     structurally wrong — it said two of three call sites were inset-protected;
//     there are only two call sites and only ONE is.
//
//  A FOURTH, CHECKED AND FOUND ALREADY FIXED — recorded because the inventory
//  this conversion was built from still lists it. Batch 4's inventory (§3.1) says
//  two scan messages delivered success-shaped copy on the red treatment: "Could
//  not fetch card history. Starting fresh." and its job-box twin were raised with
//  `isSuccess: false`, so a sentence saying everything is fine arrived under a red
//  cross. Both strings are GONE from `ScanView` as of AMB.11 — grep returns
//  nothing — and every remaining `false` site there is a genuine failure. The
//  third kind below is added anyway, because the vocabulary gap was real and the
//  next screen that needs "it did not work but nothing is broken" should not have
//  to choose between a green tick and a red cross.
//
//  Also added, all absent before and all verified absent by a full read rather
//  than assumed to be elsewhere: tap to dismiss, an accessibility announcement, a
//  duration that scales with how much there is to read, and a maximum width so a
//  long failure string does not span an iPad.

import SwiftUI

// MARK: - Kind

/// What a toast MEANS. The glyph and the fill follow from it, once.
enum ToastKind {
    case success
    case failure
    /// It did not work the way you asked, but nothing is broken and the thing you
    /// were doing continued. Distinct from `failure` because delivering "starting
    /// fresh" on a red cross tells the user something false.
    case warning

    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    var fill: Color {
        switch self {
        case .success: return .green
        case .failure: return .red
        case .warning: return .orange
        }
    }

    /// D14 reserves a RED WASH for a flagged user, app-wide. A toast is momentary
    /// chrome, not a wash, and the ruling explicitly keeps momentary reds — but
    /// the distinction is worth stating where the colour is chosen.
    var accessibilityPrefix: String {
        switch self {
        case .success: return "Done"
        case .failure: return "Failed"
        case .warning: return "Warning"
        }
    }
}

// MARK: - The toast

struct ToastView: View {
    let message: String
    var kind: ToastKind = .success

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .foregroundStyle(.white)
                .font(.title3)

            Text(message)
                .foregroundStyle(.white)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // ambient-allow: transient chrome floating over a whole screen — a
        // control surface, not one of the page's containers. It cannot be an
        // ambientCard: a material takes its value from what is behind it, and
        // this has to be readable over anything the app can draw.
        .background(Capsule().fill(kind.fill))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        .frame(maxWidth: 420)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.accessibilityPrefix). \(message)")
    }
}

// MARK: - Presentation

extension View {
    /// Raise a toast over this view.
    ///
    /// Positioning is deliberately INDEPENDENT of whatever safe area the host
    /// carries — see defect 3 in the file header.
    func toast(isPresented: Binding<Bool>,
               message: String,
               kind: ToastKind = .success) -> some View {
        modifier(ToastPresenter(isPresented: isPresented, message: message, kind: kind))
    }

    /// Kept so the boolean call sites that predate `ToastKind` keep compiling and
    /// keep meaning what they meant.
    func toast(isPresented: Binding<Bool>,
               message: String,
               isSuccess: Bool) -> some View {
        toast(isPresented: isPresented, message: message, kind: isSuccess ? .success : .failure)
    }
}

private struct ToastPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let kind: ToastKind

    @ObservedObject private var tabBarManager = TabBarManager.shared

    /// Long enough to read, short enough not to sit on the bar. The multi-line
    /// failure strings in the scan flow were given the same three seconds as
    /// "Report submitted successfully".
    private var duration: Double {
        let words = message.split(separator: " ").count
        return min(7.0, max(3.0, 1.6 + Double(words) * 0.32))
    }

    /// The bar is a sibling of this overlay in the shell's ZStack, so its own
    /// numbers are the right ones to clear. When the bar is away — a full-screen
    /// overlay, or the keyboard pushing it down — the toast only has to clear the
    /// home indicator.
    private var bottomPadding: CGFloat {
        let barVisible = !tabBarManager.isFullScreenOverlayActive && !tabBarManager.isKeyboardVisible
        return barVisible ? TabBarMetrics.clearance + 12 : 44
    }

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if isPresented {
                ToastView(message: message, kind: kind)
                    .padding(.horizontal, 16)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture {
                        withAnimation(AmbientMotion.snappy) { isPresented = false }
                    }
                    // Keyed to the MESSAGE, not to the view's appearance: a
                    // second toast raised while the first is still up restarts
                    // the clock instead of inheriting what was left of it
                    // (defect 1).
                    //
                    // THE LIMIT, stated because it is real and not fixable here:
                    // if a call site raises the SAME string while that string is
                    // already showing, neither the flag nor the message changes,
                    // so SwiftUI sees no state change at all and there is nothing
                    // to key on — that toast still inherits the remaining time.
                    // ScanView can produce it ("User organization not found."
                    // fires from four paths). Closing it needs an explicit
                    // `show()` call rather than a Bool binding, i.e. a toast
                    // centre, which is a bigger change than this surface's
                    // conversion and would touch a file AMB.11 has just smoked.
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        withAnimation(AmbientMotion.snappy) { isPresented = false }
                    }
                    // Expand back through the host's safe area so the position is
                    // the same at every call site (defect 3).
                    .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        // The show is animated too, not only the hide (defect 2).
        .animation(AmbientMotion.snappy, value: isPresented)
    }
}

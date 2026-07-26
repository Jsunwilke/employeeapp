//  DashboardChrome.swift
//  Iconik Employee — the home dashboard's shared furniture (AMB.4)
//
//  Every widget on home is the same shape: a glass card, a titled header with a
//  coloured glyph on a disc and one control on the right, and then whatever the
//  widget is about. Before AMB.4 each of the seven widgets hand-rolled that
//  shape — seven copies of the same padding, corner radius, separator stroke and
//  shadow, which is why DashboardWidgets.swift was the highest-drift file in the
//  app (eight hand-rolled cards, per scripts/check_card_drift.py).
//
//  The header's exact numbers — 26pt disc, 13pt semibold glyph, 16% tint fill,
//  .headline title — are ported verbatim from the mockup the operator approved
//  on a device (DesignLab/Mockups/DashboardMockup.swift), not re-derived.
//
//  The loading and empty states live here for a less obvious reason: they were
//  the single most-dropped thing when AMB.4's parity inventory compared the
//  approved design against the source. A design shows a resting state; a widget
//  spends real time loading and real days empty. Making them shared furniture
//  means the next widget gets them by default instead of by remembering.

import SwiftUI

// MARK: - Container

/// The card every home widget sits in.
///
/// Roomy rather than compact: a widget is a handful of items you read, not a
/// list you scan (AMB plan, D5). The rows INSIDE a widget are compact — that
/// contrast is what makes a widget read as one thing rather than as a pile.
struct DashboardWidgetCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }
}

// MARK: - Header

struct DashboardWidgetHeader<Trailing: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, systemImage: String, tint: Color,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(0.16)))
            Text(title).font(.headline)
            Spacer(minLength: 0)
            trailing()
        }
    }
}

extension DashboardWidgetHeader where Trailing == EmptyView {
    init(_ title: String, systemImage: String, tint: Color) {
        self.init(title, systemImage: systemImage, tint: tint) { EmptyView() }
    }
}

// MARK: - States

/// The spinner a widget shows on its first load.
///
/// Every widget on this screen paints instantly from a cache and only shows this
/// when there is genuinely nothing yet, which is why it is small and centred
/// rather than a full-height block: it is a brief gap in a card that already has
/// a header, not an empty screen.
struct DashboardWidgetLoading: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 22)
    }
}

/// A widget with nothing in it, which on this screen is a normal state rather
/// than an error — no shifts on a day off, no tasks when you are caught up.
struct DashboardWidgetEmpty: View {
    let systemImage: String
    let title: String
    var message: String?
    /// An action the empty state itself offers. Two widgets have one today (add
    /// a group job, add a note) and losing it would leave a dead end.
    var actionTitle: String?
    var actionSystemImage: String = "plus.circle"
    var tint: Color = .accentColor
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionSystemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(tint.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Footer link

/// The "there are more of these" line at the foot of a widget.
///
/// Always a real control. The approved mockup drew a count and no way to reach
/// the rest; in the app this is how a fourth shift or a fourth group job is
/// reachable from home at all.
struct DashboardMoreRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Spacer()
                Text(title).font(.caption.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                Spacer()
            }
            .foregroundStyle(AmbientStyle.brand)
            .padding(.top, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The small text button that sits on the right of a widget header ("View all").
struct DashboardHeaderLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AmbientStyle.brand)
        }
        .buttonStyle(.plain)
    }
}
